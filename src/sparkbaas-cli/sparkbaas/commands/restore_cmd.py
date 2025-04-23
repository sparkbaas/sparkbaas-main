import os
import sys
from pathlib import Path
import time
import subprocess
import glob

from sparkbaas.core.compose import DockerCompose
from sparkbaas.core.config import Config
from sparkbaas.ui.console import (
    console, print_step, print_success, print_error, 
    print_warning, print_info, print_section, confirm, select
)

def setup_parser(parser):
    """Set up command-line arguments for restore command"""
    parser.add_argument(
        "--postgres-backup", type=str,
        help="Path to PostgreSQL backup file"
    )
    parser.add_argument(
        "--files-backup", type=str,
        help="Path to file storage backup"
    )
    parser.add_argument(
        "--force", "-f", action="store_true",
        help="Force restore without confirmation"
    )
    return parser

def find_latest_backup(backup_dir, prefix):
    """
    Find the latest backup file with given prefix
    
    Args:
        backup_dir: Directory containing backups
        prefix: File prefix to match
        
    Returns:
        Path to latest backup file or None if not found
    """
    pattern = os.path.join(backup_dir, f"{prefix}_*.sql*")
    backup_files = glob.glob(pattern)
    
    if not backup_files:
        # Try compressed files
        pattern = os.path.join(backup_dir, f"{prefix}_*.sql.gz")
        backup_files = glob.glob(pattern)
    
    if not backup_files:
        # Try tar files for file backups
        pattern = os.path.join(backup_dir, f"{prefix}_*.tar*")
        backup_files = glob.glob(pattern)
        
    if not backup_files:
        return None
        
    # Sort by modification time (newest first)
    backup_files.sort(key=lambda x: os.path.getmtime(x), reverse=True)
    return Path(backup_files[0])

def select_backup(backup_dir, backup_type):
    """
    Let user select a backup file
    
    Args:
        backup_dir: Directory containing backups
        backup_type: Type of backup ("postgres" or "files")
        
    Returns:
        Path to selected backup file or None if cancelled
    """
    # Find files matching the pattern
    if backup_type == "postgres":
        pattern = os.path.join(backup_dir, "postgres_*.sql*")
        prefix = "PostgreSQL"
    else:
        pattern = os.path.join(backup_dir, "files_*.tar*")
        prefix = "Files"
        
    backup_files = glob.glob(pattern)
    
    if not backup_files:
        print_warning(f"No {backup_type} backup files found.")
        return None
        
    # Sort by modification time (newest first)
    backup_files.sort(key=lambda x: os.path.getmtime(x), reverse=True)
    
    # Format choices with timestamps
    choices = []
    for file_path in backup_files:
        filename = os.path.basename(file_path)
        mtime = os.path.getmtime(file_path)
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(mtime))
        size_mb = os.path.getsize(file_path) / (1024 * 1024)
        choices.append(f"{filename} ({timestamp}, {size_mb:.2f}MB)")
    
    # Add cancel option
    choices.append("Cancel")
    
    # Let user select
    selected = select(
        f"Select {prefix} backup to restore:",
        choices=choices
    )
    
    if selected == "Cancel":
        return None
        
    # Get selected file path
    index = choices.index(selected)
    return Path(backup_files[index])

def restore_postgres(config, backup_file):
    """
    Restore PostgreSQL database
    
    Args:
        config: Config instance
        backup_file: Path to backup file
        
    Returns:
        True if successful, False otherwise
    """
    print_step(f"Restoring PostgreSQL database from {backup_file}...")
    
    # Get Docker Compose wrapper
    compose = DockerCompose()
    
    try:
        # Check if postgres container is running
        ps_output = compose.run("ps", capture_output=True).stdout
        if "postgres" not in ps_output:
            print_warning("PostgreSQL container is not running.")
            if not confirm("Start PostgreSQL container for restore?", default=True):
                print_info("PostgreSQL restore cancelled.")
                return False
            
            print_info("Starting PostgreSQL container...")
            compose.up(services=["postgres"], detached=True)
            # Wait for postgres to be ready
            time.sleep(5)
        
        # Get container ID
        container_id = subprocess.run(
            ["docker", "compose", "-f", str(compose.compose_file), "ps", "-q", "postgres"],
            capture_output=True, text=True
        ).stdout.strip()
        
        if not container_id:
            print_error("Failed to get PostgreSQL container ID.")
            return False
        
        # Decompress if needed
        is_compressed = str(backup_file).endswith('.gz')
        if is_compressed:
            print_info("Decompressing backup file...")
            import gzip
            import tempfile
            
            # Create temp file for decompressed backup
            with tempfile.NamedTemporaryFile(delete=False, suffix='.sql') as temp_file:
                temp_path = temp_file.name
                
            with gzip.open(backup_file, 'rb') as f_in:
                with open(temp_path, 'wb') as f_out:
                    f_out.write(f_in.read())
            
            backup_file = temp_path
        
        # Copy backup file to container
        print_info("Copying backup file to container...")
        subprocess.run(
            ["docker", "cp", str(backup_file), f"{container_id}:/tmp/restore.sql"],
            check=True
        )
        
        # Drop and recreate database
        print_warning("Dropping existing database...")
        compose.run_service(
            service="postgres",
            command="psql -U postgres -c 'SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = \\'postgres\\' AND pid <> pg_backend_pid();'",
            entrypoint=""
        )
        compose.run_service(
            service="postgres",
            command="psql -U postgres -c 'DROP DATABASE postgres;'",
            entrypoint=""
        )
        compose.run_service(
            service="postgres",
            command="psql -U postgres -c 'CREATE DATABASE postgres;'",
            entrypoint=""
        )
        
        # Restore from backup
        print_info("Restoring database...")
        compose.run_service(
            service="postgres",
            command="psql -U postgres -d postgres -f /tmp/restore.sql",
            entrypoint=""
        )
        
        # Clean up temp file if created
        if is_compressed:
            os.unlink(temp_path)
        
        print_success("PostgreSQL database restored successfully.")
        return True
    except Exception as e:
        print_error(f"Failed to restore PostgreSQL database: {str(e)}")
        return False

def restore_files(config, backup_file):
    """
    Restore file storage
    
    Args:
        config: Config instance
        backup_file: Path to backup file
        
    Returns:
        True if successful, False otherwise
    """
    print_step(f"Restoring file storage from {backup_file}...")
    
    try:
        # Get data directory
        data_dir = config.get_data_dir()
        
        # Check if we need to stop services
        compose = DockerCompose()
        ps_output = compose.run("ps", capture_output=True).stdout
        
        if "minio" in ps_output or "storage" in ps_output:
            print_warning("Storage services are running.")
            if not confirm("Stop storage services for restore?", default=True):
                print_info("File storage restore cancelled.")
                return False
                
            print_info("Stopping storage services...")
            if "minio" in ps_output:
                compose.stop(services=["minio"])
            if "storage" in ps_output:
                compose.stop(services=["storage"])
        
        # Decompress if needed
        is_compressed = str(backup_file).endswith('.gz')
        if is_compressed:
            print_info("Decompressing backup file...")
            import gzip
            import tempfile
            
            # Create temp file for decompressed backup
            with tempfile.NamedTemporaryFile(delete=False, suffix='.tar') as temp_file:
                temp_path = temp_file.name
                
            with gzip.open(backup_file, 'rb') as f_in:
                with open(temp_path, 'wb') as f_out:
                    f_out.write(f_in.read())
            
            backup_file = temp_path
        
        # Extract archive
        print_info("Extracting backup archive...")
        from tarfile import TarFile
        
        with TarFile.open(backup_file, "r") as tar:
            tar.extractall(path=data_dir)
        
        # Clean up temp file if created
        if is_compressed:
            os.unlink(temp_path)
        
        print_success("File storage restored successfully.")
        
        # Restart services
        if "minio" in ps_output or "storage" in ps_output:
            print_info("Restarting storage services...")
            compose.up(detached=True)
        
        return True
    except Exception as e:
        print_error(f"Failed to restore file storage: {str(e)}")
        return False

def handle(args):
    """Handle restore command"""
    config = Config()
    
    # Check if initialized
    if not config.is_initialized():
        print_error("SparkBaaS is not initialized.")
        print_info("Run 'spark init' to initialize SparkBaaS.")
        return 1
    
    print_section("Restore SparkBaaS")
    
    # Ask for confirmation
    if not args.force:
        print_warning("Restoring will overwrite existing data!")
        if not confirm("Are you sure you want to proceed?", default=False):
            print_info("Restore cancelled.")
            return 0
    
    # Default backup directory
    backup_dir = config.project_root / "src" / "data" / "backups"
    
    # Postgres restore
    postgres_backup = None
    if args.postgres_backup:
        postgres_backup = Path(args.postgres_backup)
    else:
        # Find latest backup or let user select
        postgres_backup = find_latest_backup(backup_dir, "postgres")
        
        if not postgres_backup:
            if confirm("No PostgreSQL backup found. Do you want to select a backup file?", default=True):
                postgres_backup = select_backup(backup_dir, "postgres")
    
    if postgres_backup:
        if restore_postgres(config, postgres_backup):
            print_success("PostgreSQL database restored successfully.")
        else:
            print_error("Failed to restore PostgreSQL database.")
    
    # Files restore
    files_backup = None
    if args.files_backup:
        files_backup = Path(args.files_backup)
    else:
        # Find latest backup or let user select
        files_backup = find_latest_backup(backup_dir, "files")
        
        if not files_backup:
            if confirm("No file storage backup found. Do you want to select a backup file?", default=True):
                files_backup = select_backup(backup_dir, "files")
    
    if files_backup:
        if restore_files(config, files_backup):
            print_success("File storage restored successfully.")
        else:
            print_error("Failed to restore file storage.")
    
    print_section("Restore Complete")
    print_success("SparkBaaS has been restored.")
    print_info("Restart services with 'spark start' to apply changes.")
    
    return 0