import os
from pathlib import Path

from sparkbaas.core.compose import DockerCompose
from sparkbaas.core.config import Config
from sparkbaas.ui.console import (
    console, print_step, print_success, print_error, 
    print_warning, print_info, print_section, select
)
from rich.panel import Panel

def setup_parser(parser):
    """Set up command-line arguments for start command"""
    parser.add_argument(
        "--build", action="store_true",
        help="Build images before starting"
    )
    parser.add_argument(
        "--services", type=str, nargs="+",
        help="Specific services to start"
    )
    parser.add_argument(
        "--no-migrations", action="store_true",
        help="Skip running migrations"
    )
    parser.add_argument(
        "--attach", "-a", action="store_true",
        help="Attach to services (non-detached mode)"
    )
    return parser

def run_migrations(config):
    """Run database migrations"""
    print_step("Running database migrations...")
    
    # Get Docker Compose wrapper
    compose = DockerCompose()
    
    try:
        # Run migrations using the postgres service
        compose.run_service(
            service="postgres", 
            command="sh -c 'cd /docker-entrypoint-initdb.d && ./init-db.sh'",
            entrypoint=""
        )
        print_success("Migrations completed successfully.")
        return True
    except Exception as e:
        print_error(f"Failed to run migrations: {str(e)}")
        return False

def start_services(args):
    """Start SparkBaaS services"""
    print_step("Starting services...")
    
    # Get Docker Compose wrapper
    compose = DockerCompose()
    
    try:
        # Start services
        compose.up(detached=not args.attach, services=args.services, build=args.build)
        print_success("Services started successfully.")
        return True
    except Exception as e:
        print_error(f"Failed to start services: {str(e)}")
        return False

def display_access_info(config):
    """Display access information for services"""
    print_section("Access Information")
    
    # Get URLs and credentials from config
    postgres_host = config.get_env_var("POSTGRES_HOST", "localhost")
    postgres_port = config.get_env_var("POSTGRES_PORT", "5432")
    postgres_user = config.get_env_var("POSTGRES_USER", "postgres")
    postgres_db = config.get_env_var("POSTGRES_DB", "postgres")
    
    # Keycloak info
    keycloak_port = config.get_env_var("KEYCLOAK_PORT", "8080")
    keycloak_user = config.get_env_var("KEYCLOAK_ADMIN", "admin")
    
    # API Gateway info
    api_port = config.get_env_var("API_GATEWAY_PORT", "8000")
    
    # Create info panel
    info = []
    
    # PostgreSQL
    info.append("[bold cyan]PostgreSQL[/bold cyan]")
    info.append(f"  Host: {postgres_host}")
    info.append(f"  Port: {postgres_port}")
    info.append(f"  User: {postgres_user}")
    info.append(f"  Database: {postgres_db}")
    info.append(f"  Connection: postgresql://{postgres_user}:******@{postgres_host}:{postgres_port}/{postgres_db}")
    info.append("")
    
    # Keycloak
    info.append("[bold cyan]Keycloak[/bold cyan]")
    info.append(f"  URL: http://localhost:{keycloak_port}/auth/")
    info.append(f"  Admin Console: http://localhost:{keycloak_port}/auth/admin")
    info.append(f"  Username: {keycloak_user}")
    info.append("")
    
    # API Gateway
    info.append("[bold cyan]API Gateway[/bold cyan]")
    info.append(f"  URL: http://localhost:{api_port}")
    
    # Display the panel
    console.print(Panel("\n".join(info), title="Service Access Information", border_style="green"))

def handle(args):
    """Handle start command"""
    config = Config()
    
    # Check if initialized
    if not config.is_initialized():
        print_error("SparkBaaS is not initialized.")
        print_info("Run 'spark init' to initialize SparkBaaS.")
        return 1
    
    print_section("Starting SparkBaaS")
    
    # Run migrations if not skipped
    if not args.no_migrations:
        if not run_migrations(config):
            return 1
    
    # Start services
    if not start_services(args):
        return 1
    
    # Display access information
    display_access_info(config)
    
    print_section("SparkBaaS Started")
    print_success("SparkBaaS services are now running!")
    
    if args.attach:
        print_info("Press Ctrl+C to stop services and return to the command line.")
    else:
        print_info("Use 'spark status' to check the status of services.")
        print_info("Use 'spark stop' to stop all services.")
    
    return 0