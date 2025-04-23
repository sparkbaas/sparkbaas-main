import os
import sys
from pathlib import Path
import time
import subprocess

from sparkbaas.core.compose import DockerCompose
from sparkbaas.core.config import Config
from sparkbaas.core.utils import ensure_dir
from sparkbaas.ui.console import (
    console, print_step, print_success, print_error, 
    print_warning, print_info, print_section, confirm, select
)

def setup_parser(parser):
    """Set up command-line arguments for backup command"""
    parser.add_argument(
        "--output", "-o", type=str,
        help="Output directory for backups (default: src/data/backups)"
    )
    parser.add_argument(
        "--skip-postgres", action="store_true",
        help="Skip PostgreSQL backup"
    )
    parser.add_argument(
        "--skip-files", action="store_true",
        help="Skip file storage backup"
    )
    parser.add_argument(
        "--compress", "-c", action="store_true",
        help="Compress backup files"
    )
    return parser

def backup_postgres(config, backup_dir):
    """
    Backup PostgreSQL database
    
    Args:
        config: Config instance
        backup_dir: Directory to store backups
        
    Returns:
        True if successful, False otherwise
    """
    print_step("Backing up PostgreSQL database...")
    
    # Generate backup filename with timestamp
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    backup_path = backup_dir / f"postgres_{timestamp}.sql"
    
    # Get Docker Compose wrapper
    compose = DockerCompose()
    
    try:
        # Check if postgres container is running
        ps_output = compose.run("ps", capture_output=True).stdout
        if "postgres" not in ps_output:
            print_warning("PostgreSQL container is not running.")
            if not confirm("Start PostgreSQL container for backup?", default=True):
                print_info("PostgreSQL backup skipped.")
                return True
            
            print_info("Starting PostgreSQL container...")
            compose.up(services=["postgres"], detached=True)
            # Wait for postgres to be ready
            time.sleep(5)
        
        # Run pg_dump in the postgres container
        compose.run_service(
            service="postgres",
            command=f'pg_dump -U postgres -d postgres -f /tmp/backup.sql',
            entrypoint=""
        )
        
        # Copy the backup file from the container to host
        host_path = str(backup_path.absolute())
        container_id = subprocess.run(
            ["docker", "compose", "-f", str(compose.compose_file), "ps", "-q", "postgres"],
            capture_output=True, text=True
        ).stdout.strip()
        
        if not container_id:
            print_error("Failed to get PostgreSQL container ID.")
            return False
        
        # Copy file from container to host
        subprocess.run(
            ["docker", "cp", f"{container_id}:/tmp/backup.sql", host_path],
            check=True
        )
        
        # Compress if requested
        if hasattr(args, 'compress') and args.compress:
            import gzip
            with open(backup_path, 'rb') as f_in:
                with gzip.open(f"{backup_path}.gz", 'wb') as f_out:
                    f_out.write(f_in.read())
            os.unlink(backup_path)
            backup_path = Path(f"{backup_path}.gz")
        
        print_success(f"PostgreSQL backup created: {backup_path}")
        return True
    except Exception as e:
        print_error(f"Failed to backup PostgreSQL database: {str(e)}")
        return False

def backup_files(config, backup_dir):
    """
    Backup file storage
    
    Args:
        config: Config instance
        backup_dir: Directory to store backups
        
    Returns:
        True if successful, False otherwise
    """
    print_step("Backing up file storage...")
    
    # Generate backup filename with timestamp
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    backup_path = backup_dir / f"files_{timestamp}.tar"
    
    try:
        # Get storage directories
        data_dir = config.get_data_dir()
        storage_dirs = [
            data_dir / "storage" if (data_dir / "storage").exists() else None,
            data_dir / "minio" if (data_dir / "minio").exists() else None
        ]
        
        storage_dirs = [d for d in storage_dirs if d]
        
        if not storage_dirs:
            print_info("No file storage directories found. Skipping file backup.")
            return True
        
        # Create tar archive
        from tarfile import TarFile
        
        with TarFile.open(backup_path, "w") as tar:
            for storage_dir in storage_dirs:
                if storage_dir.exists():
                    tar.add(
                        storage_dir, 
                        arcname=storage_dir.name
                    )
        
        # Compress if requested
        if hasattr(args, 'compress') and args.compress:
            import gzip
            with open(backup_path, 'rb') as f_in:
                with gzip.open(f"{backup_path}.gz", 'wb') as f_out:
                    f_out.write(f_in.read())
            os.unlink(backup_path)
            backup_path = Path(f"{backup_path}.gz")
        
        print_success(f"File storage backup created: {backup_path}")
        return True
    except Exception as e:
        print_error(f"Failed to backup file storage: {str(e)}")
        return False

def handle(args):
    """Handle backup command"""
    config = Config()
    
    # Check if initialized
    if not config.is_initialized():
        print_error("SparkBaaS is not initialized.")
        print_info("Run 'spark init' to initialize SparkBaaS.")
        return 1
    
    print_section("Backup SparkBaaS")
    
    # Determine backup directory
    if args.output:
        backup_dir = Path(args.output)
    else:
        backup_dir = config.project_root / "src" / "data" / "backups"
    
    # Ensure backup directory exists
    ensure_dir(backup_dir)
    
    # Backup PostgreSQL
    if not args.skip_postgres:
        if not backup_postgres(config, backup_dir):
            print_warning("PostgreSQL backup failed.")
    
    # Backup files
    if not args.skip_files:
        if not backup_files(config, backup_dir):
            print_warning("File storage backup failed.")
    
    print_section("Backup Complete")
    print_success(f"Backups stored in: {backup_dir}")
    
    return 0