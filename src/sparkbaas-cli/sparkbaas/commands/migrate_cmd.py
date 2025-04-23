import os
import sys
from pathlib import Path
import time

from sparkbaas.core.compose import DockerCompose
from sparkbaas.core.config import Config
from sparkbaas.ui.console import (
    console, print_step, print_success, print_error, 
    print_warning, print_info, print_section, confirm, select
)

def setup_parser(parser):
    """Set up command-line arguments for migrate command"""
    parser.add_argument(
        "--schema", type=str,
        help="Specific schema to migrate (default: all)"
    )
    parser.add_argument(
        "--skip-backup", action="store_true",
        help="Skip database backup before migration"
    )
    parser.add_argument(
        "--force", "-f", action="store_true",
        help="Don't ask for confirmation"
    )
    return parser

def backup_database(config):
    """
    Backup database before migration
    
    Returns:
        Tuple of (success, backup_path)
    """
    print_step("Backing up database...")
    
    # Create backup directory if it doesn't exist
    backup_dir = config.project_root / "src" / "data" / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    
    # Generate backup filename with timestamp
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    backup_path = backup_dir / f"pre_migration_{timestamp}.sql"
    
    # Get Docker Compose wrapper
    compose = DockerCompose()
    
    try:
        # Run pg_dump in the postgres container
        compose.run_service(
            service="postgres",
            command=f'pg_dump -U postgres -d postgres -f /tmp/backup.sql',
            entrypoint=""
        )
        
        # Copy the backup file from the container
        compose.run_service(
            service="postgres",
            command=f'cat /tmp/backup.sql > /var/lib/postgresql/data/backups/pre_migration_{timestamp}.sql',
            entrypoint="sh -c"
        )
        
        print_success(f"Database backup created: {backup_path}")
        return True, backup_path
    except Exception as e:
        print_error(f"Failed to backup database: {str(e)}")
        return False, None

def run_migrations(config, schema=None):
    """
    Run database migrations
    
    Args:
        schema: Specific schema to migrate (None for all)
        
    Returns:
        True if successful, False otherwise
    """
    print_step(f"Running migrations for {schema if schema else 'all schemas'}...")
    
    # Get migrations directory
    migrations_dir = config.get_migrations_dir()
    
    # Get Docker Compose wrapper
    compose = DockerCompose()
    
    try:
        # Prepare migration command
        if schema:
            cmd = f'cd /migrations && ./run-migrations.sh {schema}'
        else:
            cmd = 'cd /migrations && ./run-migrations.sh'
        
        # Run migrations in the postgres container
        compose.run_service(
            service="postgres",
            command=cmd,
            entrypoint="sh -c",
            env_vars={"PGPASSWORD": os.environ.get("POSTGRES_PASSWORD")}
        )
        
        print_success("Migrations completed successfully.")
        return True
    except Exception as e:
        print_error(f"Failed to run migrations: {str(e)}")
        return False

def create_migration_file(config, name, schema):
    """
    Create a new migration file
    
    Args:
        name: Migration name
        schema: Schema name
        
    Returns:
        Path to the created migration file
    """
    # Format name to be filename-friendly
    safe_name = name.lower().replace(" ", "_").replace("-", "_")
    
    # Generate timestamp
    timestamp = time.strftime("%Y%m%d%H%M%S")
    
    # Get migrations directory
    migrations_dir = config.get_migrations_dir()
    
    # Determine target directory
    if schema == "core":
        target_dir = migrations_dir / "core"
    else:
        target_dir = migrations_dir / "user" / schema
    
    # Create directory if it doesn't exist
    target_dir.mkdir(parents=True, exist_ok=True)
    
    # Create migration file
    migration_file = target_dir / f"{timestamp}_{safe_name}.sql"
    
    with open(migration_file, 'w') as f:
        f.write(f"-- Migration: {name}\n")
        f.write(f"-- Created: {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write("-- Write your SQL migration here\n\n")
    
    return migration_file

def handle(args):
    """Handle migrate command"""
    config = Config()
    
    # Check if initialized
    if not config.is_initialized():
        print_error("SparkBaaS is not initialized.")
        print_info("Run 'spark init' to initialize SparkBaaS.")
        return 1
    
    print_section("Database Migrations")
    
    # Check if services are running
    compose = DockerCompose()
    try:
        service_status = compose.run("ps", capture_output=True).stdout
        if "postgres" not in service_status:
            print_warning("Postgres service is not running.")
            if not args.force and not confirm("Start services before migration?", default=True):
                print_info("Migration cancelled.")
                return 0
                
            print_info("Starting services...")
            compose.up(services=["postgres"], detached=True)
            # Wait for postgres to be ready
            time.sleep(5)
    except:
        pass
    
    # Ask to create a new migration or run migrations
    action = "run"
    if not args.force:
        action = select(
            "What would you like to do?",
            choices=["run", "create"],
            default="run"
        )
    
    # Create a new migration
    if action == "create":
        schema = select(
            "Select schema:",
            choices=["core", "auth", "storage", "custom"],
            default="core"
        )
        
        if schema == "custom":
            import questionary
            schema = questionary.text("Enter custom schema name:").ask()
        
        name = questionary.text("Enter migration name:").ask()
        
        migration_file = create_migration_file(config, name, schema)
        print_success(f"Migration file created: {migration_file}")
        return 0
    
    # Backup database if not skipped
    if not args.skip_backup:
        success, backup_path = backup_database(config)
        if not success:
            if not confirm("Continue without backup?", default=False):
                print_info("Migration cancelled.")
                return 1
    
    # Run migrations
    if not run_migrations(config, args.schema):
        return 1
    
    print_section("Migration Complete")
    print_success("Database migrations completed successfully.")
    
    return 0