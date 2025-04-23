import os
import sys
import secrets
import string
import shutil
import subprocess
from pathlib import Path
import re
from datetime import datetime

from sparkbaas.core.compose import DockerCompose
from sparkbaas.core.config import Config
from sparkbaas.core.utils import ensure_dir, get_os_type
from sparkbaas.ui.console import (
    console, print_banner, print_step, print_success, 
    print_error, print_warning, print_info, print_section, confirm
)

def setup_parser(parser):
    """Set up command-line arguments for init command"""
    parser.add_argument(
        "--force", action="store_true", 
        help="Force initialization even if already initialized"
    )
    parser.add_argument(
        "--skip-checks", action="store_true",
        help="Skip prerequisite checks"
    )
    parser.add_argument(
        "--env-file", type=str,
        help="Path to custom .env file template"
    )
    parser.add_argument(
        "--no-traefik", action="store_true",
        help="Initialize without Traefik as reverse proxy"
    )
    return parser

def check_prerequisites():
    """Check if all prerequisites are installed"""
    from sparkbaas.core.utils import is_docker_available, is_docker_compose_available
    
    print_step("Checking prerequisites...")
    
    # Check Docker
    if not is_docker_available():
        print_error("Docker is not installed or not available.")
        print_info("Please install Docker and try again.")
        print_info("Visit https://docs.docker.com/get-docker/ for installation instructions.")
        return False
    
    # Check Docker Compose
    if not is_docker_compose_available():
        print_error("Docker Compose is not installed or not available.")
        print_info("Please install Docker Compose and try again.")
        print_info("Visit https://docs.docker.com/compose/install/ for installation instructions.")
        return False
    
    print_success("All prerequisites are installed.")
    return True

def generate_secure_password(length=32):
    """Generate a secure random password using CSPRNG"""
    # Use a mix of uppercase, lowercase, digits, and some special chars for better security
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()-_=+[]{}|;:,.<>?"
    # Ensure at least one of each type for password requirements
    password = secrets.choice(string.ascii_lowercase)
    password += secrets.choice(string.ascii_uppercase)
    password += secrets.choice(string.digits)
    password += secrets.choice("!@#$%^&*()-_=+")
    # Fill the rest with random characters
    password += ''.join(secrets.choice(alphabet) for _ in range(length - 4))
    # Shuffle the password to randomize the position of the guaranteed characters
    password_list = list(password)
    secrets.SystemRandom().shuffle(password_list)
    return ''.join(password_list)

def generate_env_file(config, template_path=None, force=False):
    """Generate .env file with secure random passwords"""
    print_step("Generating environment configuration...")
    
    # Get project root and env file path
    env_file = config.env_file
    
    # Check if .env file already exists
    if env_file.exists() and not force:
        print_warning("Environment file already exists. Use --force to overwrite.")
        return True
    
    # Backup existing .env file if it exists and we're forcing overwrite
    if env_file.exists() and force:
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        backup_file = env_file.with_name(f".env.backup-{timestamp}")
        shutil.copy2(env_file, backup_file)
        print_info(f"Backed up existing .env file to {backup_file.name}")
    
    # Use provided template path or try to find the template
    if template_path:
        template = Path(template_path)
    else:
        template = config.project_root / "src" / "compose" / "config" / ".env.template"
        # Fallback if template doesn't exist
        if not template.exists():
            print_warning(".env.template not found, generating default configuration")
    
    # Dictionary to store environment variables
    env_vars = {}
    
    # Load existing values if .env exists and we want to preserve some values
    if env_file.exists():
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if not line or line.startswith('#'):
                    continue
                if '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key] = value
    
    # Define default environment variables with secure passwords
    defaults = {
        # General settings
        "HOST_DOMAIN": "localhost",
        "LOG_LEVEL": "info",
        
        # Database settings
        "POSTGRES_USER": "postgres",
        "POSTGRES_PASSWORD": generate_secure_password(24),
        "POSTGRES_DB": "postgres",
        "POSTGRES_PORT": "5432",
        
        # Database users
        "KEYCLOAK_DB_USER": "keycloak",
        "KEYCLOAK_DB_PASSWORD": generate_secure_password(24),
        "KEYCLOAK_DB_DATABASE": "keycloak",
        
        "KONG_PG_USER": "kong",
        "KONG_PG_PASSWORD": generate_secure_password(24),
        "KONG_PG_DATABASE": "kong",
        "KONG_PG_HOST": "postgres",
        "KONG_DATABASE": "postgres",
        
        "AUTHENTICATOR_PASSWORD": generate_secure_password(24),
        
        # Authentication settings
        "KEYCLOAK_ADMIN": "admin",
        "KEYCLOAK_ADMIN_PASSWORD": generate_secure_password(16),
        "KEYCLOAK_DB_ADDR": "postgres",
        "KEYCLOAK_DB_VENDOR": "postgres",
        
        # JWT settings
        "POSTGREST_JWT_SECRET": generate_secure_password(48),
        "PGRST_JWT_SECRET_IS_BASE64": "false",
        "POSTGREST_DB_SCHEMA": "public,api",
        "POSTGREST_DB_ANON_ROLE": "anon",
        
        # Traefik settings
        "TRAEFIK_DASHBOARD_PORT": "8080",
        "TRAEFIK_INSECURE_API": "false",
        # Use literal strings for pre-hashed passwords to avoid interpolation issues
        "TRAEFIK_ADMIN_AUTH": 'admin:$$apr1$$tZ8so14Y$$0kzh5YwGCdTUzWJHTRdXm1',
        "ACME_EMAIL": "admin@example.com",
        
        # Function server settings
        "FUNCTIONS_PORT": "8888",
        "FUNCTIONS_AUTH_ENABLED": "true",
        
        # Admin settings
        "ADMIN_USER": "admin",
        "ADMIN_PASSWORD_HASH": '$$apr1$$tZ8so14Y$$0kzh5YwGCdTUzWJHTRdXm1',
        "KONG_ADMIN_AUTH": 'admin:$$apr1$$tZ8so14Y$$0kzh5YwGCdTUzWJHTRdXm1'
    }
    
    # Special handling for derived variables
    defaults["POSTGREST_DB_URI"] = f"postgres://authenticator:${{AUTHENTICATOR_PASSWORD}}@postgres:5432/postgres"
    
    # Set default values for missing keys
    for key, value in defaults.items():
        if key not in env_vars:
            env_vars[key] = value
    
    # Write the new .env file
    with open(env_file, 'w') as f:
        f.write(f"# SparkBaaS Environment Configuration\n")
        f.write(f"# Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"# ---------------------------------\n\n")
        
        f.write("# =============================================================================\n")
        f.write("# GENERAL SETTINGS\n")
        f.write("# =============================================================================\n")
        f.write("# Domain name for services - set this to your domain if you have one\n")
        f.write(f"HOST_DOMAIN={env_vars['HOST_DOMAIN']}\n\n")
        
        f.write(f"# Log level - one of: debug, info, warn, error\n")
        f.write(f"LOG_LEVEL={env_vars['LOG_LEVEL']}\n\n")
        
        f.write("# =============================================================================\n")
        f.write("# DATABASE SETTINGS\n")
        f.write("# =============================================================================\n")
        f.write("# PostgreSQL settings\n")
        f.write(f"POSTGRES_USER={env_vars['POSTGRES_USER']}\n")
        f.write(f"POSTGRES_PASSWORD={env_vars['POSTGRES_PASSWORD']}\n")
        f.write(f"POSTGRES_DB={env_vars['POSTGRES_DB']}\n")
        f.write(f"POSTGRES_PORT={env_vars['POSTGRES_PORT']}\n\n")
        
        f.write("# Database users\n")
        f.write(f"KEYCLOAK_DB_USER={env_vars['KEYCLOAK_DB_USER']}\n")
        f.write(f"KEYCLOAK_DB_PASSWORD={env_vars['KEYCLOAK_DB_PASSWORD']}\n")
        f.write(f"KEYCLOAK_DB_DATABASE={env_vars['KEYCLOAK_DB_DATABASE']}\n\n")
        
        f.write(f"KONG_PG_USER={env_vars['KONG_PG_USER']}\n")
        f.write(f"KONG_PG_PASSWORD={env_vars['KONG_PG_PASSWORD']}\n")
        f.write(f"KONG_PG_DATABASE={env_vars['KONG_PG_DATABASE']}\n")
        f.write(f"KONG_PG_HOST={env_vars['KONG_PG_HOST']}\n")
        f.write(f"KONG_DATABASE={env_vars['KONG_DATABASE']}\n\n")
        
        f.write(f"AUTHENTICATOR_PASSWORD={env_vars['AUTHENTICATOR_PASSWORD']}\n\n")
        
        f.write("# =============================================================================\n")
        f.write("# AUTHENTICATION SETTINGS\n")
        f.write("# =============================================================================\n")
        f.write("# Keycloak settings\n")
        f.write(f"KEYCLOAK_ADMIN={env_vars['KEYCLOAK_ADMIN']}\n")
        f.write(f"KEYCLOAK_ADMIN_PASSWORD={env_vars['KEYCLOAK_ADMIN_PASSWORD']}\n")
        f.write(f"KEYCLOAK_DB_ADDR={env_vars['KEYCLOAK_DB_ADDR']}\n")
        f.write(f"KEYCLOAK_DB_VENDOR={env_vars['KEYCLOAK_DB_VENDOR']}\n\n")
        
        f.write("# JWT settings\n")
        f.write(f"POSTGREST_JWT_SECRET={env_vars['POSTGREST_JWT_SECRET']}\n")
        f.write(f"PGRST_JWT_SECRET_IS_BASE64={env_vars['PGRST_JWT_SECRET_IS_BASE64']}\n")
        f.write(f"POSTGREST_DB_URI={env_vars['POSTGREST_DB_URI']}\n")
        f.write(f"POSTGREST_DB_SCHEMA={env_vars['POSTGREST_DB_SCHEMA']}\n")
        f.write(f"POSTGREST_DB_ANON_ROLE={env_vars['POSTGREST_DB_ANON_ROLE']}\n\n")
        
        f.write("# =============================================================================\n")
        f.write("# TRAEFIK SETTINGS\n")
        f.write("# =============================================================================\n")
        f.write(f"TRAEFIK_DASHBOARD_PORT={env_vars['TRAEFIK_DASHBOARD_PORT']}\n")
        f.write(f"TRAEFIK_INSECURE_API={env_vars['TRAEFIK_INSECURE_API']}\n")
        f.write(f"TRAEFIK_ADMIN_AUTH={env_vars['TRAEFIK_ADMIN_AUTH']}\n")
        f.write(f"ACME_EMAIL={env_vars['ACME_EMAIL']}\n\n")
        
        f.write("# =============================================================================\n")
        f.write("# FUNCTION SERVER SETTINGS\n")
        f.write("# =============================================================================\n")
        f.write(f"FUNCTIONS_PORT={env_vars['FUNCTIONS_PORT']}\n")
        f.write(f"FUNCTIONS_AUTH_ENABLED={env_vars['FUNCTIONS_AUTH_ENABLED']}\n\n")
        
        f.write("# =============================================================================\n")
        f.write("# ADMIN SETTINGS\n")
        f.write("# =============================================================================\n")
        f.write(f"ADMIN_USER={env_vars['ADMIN_USER']}\n")
        f.write(f"ADMIN_PASSWORD_HASH={env_vars['ADMIN_PASSWORD_HASH']}\n")
        f.write(f"KONG_ADMIN_AUTH={env_vars['KONG_ADMIN_AUTH']}\n")
    
    print_success(f"Environment file created: {env_file}")
    return True

def create_directories(config):
    """Create required directories"""
    print_step("Creating directories...")
    
    # Create data directories
    data_dir = config.get_data_dir()
    ensure_dir(data_dir / "postgres")
    ensure_dir(data_dir / "keycloak")
    ensure_dir(data_dir / "kong")
    ensure_dir(data_dir / "functions")
    ensure_dir(data_dir / "backups")
    ensure_dir(data_dir / "security-results")
    
    # Create logs directory
    logs_dir = config.get_logs_dir()
    ensure_dir(logs_dir)
    
    # Create migrations directory
    migrations_dir = config.get_migrations_dir()
    ensure_dir(migrations_dir / "core")
    ensure_dir(migrations_dir / "user")
    
    print_success("Directories created.")
    return True

def run_setup_containers(config, with_traefik=True):
    """Run setup containers"""
    print_step("Running setup containers...")
    
    # Get Docker Compose wrapper for setup
    compose = DockerCompose()
    setup_compose = compose.setup_compose()
    
    try:
        # Create or update the environment file
        print_info("Setting up environment variables...")
        env_vars = config.get_env_vars()
        
        # Run setup containers with proper error handling
        print_info("Starting database setup process...")
        try:
            setup_result = setup_compose.up(detached=False)
            if setup_result.returncode != 0:
                print_error("Database setup failed.")
                return False
        except Exception as e:
            print_error(f"Setup failed: {str(e)}")
            # Try to collect logs for troubleshooting
            try:
                logs = setup_compose.logs(services=["setup", "postgres"], tail="50")
                print_error("Last setup logs:")
                console.print(logs.stdout if hasattr(logs, 'stdout') else "No logs available")
            except:
                pass
            return False
            
        # Run database initialization scripts
        print_info("Initializing database schemas...")
        try:
            init_result = setup_compose.run_service(
                "postgres", 
                ["/docker-entrypoint-initdb.d/init-db.sh"], 
                env_vars={
                    "POSTGRES_USER": env_vars.get("POSTGRES_USER", "postgres"),
                    "POSTGRES_PASSWORD": env_vars.get("POSTGRES_PASSWORD", "changeme"),
                    "POSTGRES_DB": env_vars.get("POSTGRES_DB", "postgres"),
                    "KEYCLOAK_DB_USER": env_vars.get("KEYCLOAK_DB_USER", "keycloak"),
                    "KEYCLOAK_DB_PASSWORD": env_vars.get("KEYCLOAK_DB_PASSWORD", "changeme"),
                    "KEYCLOAK_DB_DATABASE": env_vars.get("KEYCLOAK_DB_DATABASE", "keycloak"),
                    "KONG_PG_USER": env_vars.get("KONG_PG_USER", "kong"),
                    "KONG_PG_PASSWORD": env_vars.get("KONG_PG_PASSWORD", "changeme"),
                    "KONG_PG_DATABASE": env_vars.get("KONG_PG_DATABASE", "kong"),
                    "AUTHENTICATOR_PASSWORD": env_vars.get("AUTHENTICATOR_PASSWORD", "changeme")
                }
            )
            if init_result.returncode != 0:
                print_error("Database initialization failed.")
                return False
        except Exception as e:
            print_error(f"Database initialization failed: {str(e)}")
            return False
            
        # Run database migrations
        print_info("Running database migrations...")
        try:
            migrations_result = setup_compose.run_service(
                "postgres", 
                ["/docker-entrypoint-initdb.d/migrations/run-migrations.sh"], 
                env_vars={
                    "POSTGRES_USER": env_vars.get("POSTGRES_USER", "postgres"),
                    "POSTGRES_PASSWORD": env_vars.get("POSTGRES_PASSWORD", "changeme"),
                    "POSTGRES_DB": env_vars.get("POSTGRES_DB", "postgres")
                }
            )
            if migrations_result.returncode != 0:
                print_error("Database migrations failed.")
                return False
        except Exception as e:
            print_error(f"Migrations failed: {str(e)}")
            return False

        # Clean up after setup
        print_info("Cleaning up setup containers...")
        setup_compose.down(volumes=False, remove_orphans=True)
        
        print_success("Setup completed successfully.")
        return True
    except Exception as e:
        print_error(f"Setup failed: {str(e)}")
        print_info("Attempting to clean up...")
        try:
            setup_compose.down(volumes=False, remove_orphans=True)
        except:
            pass
        return False

def create_setup_compose_file(config, with_traefik=True):
    """Create a docker-compose.setup.yml file"""
    setup_file = config.compose_dir / "docker-compose.setup.yml"
    
    # Basic setup compose file content
    content = """version: '3.8'

services:
  setup:
    image: alpine:latest
    command: sh -c "echo 'Running setup...' && sleep 2 && echo 'Setup complete.'"
    volumes:
      - ../data:/data
      - ./config:/config
    environment:
      - POSTGRES_HOST=postgres
      - POSTGRES_USER=postgres
      - POSTGRES_DB=postgres
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    environment:
      - POSTGRES_USER=${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-changeme}
      - POSTGRES_DB=${POSTGRES_DB:-postgres}
    volumes:
      - ../data/postgres:/var/lib/postgresql/data
      - ./config/postgres/init:/docker-entrypoint-initdb.d
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
"""

    # Add Traefik setup if requested
    if with_traefik:
        traefik_content = """
  traefik-setup:
    image: traefik:v2.10
    command: 
      - "--providers.docker=false"
      - "--log.level=DEBUG"
      - "--api.insecure=true"
      - "--providers.file.directory=/etc/traefik/dynamic"
      - "--providers.file.watch=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
    volumes:
      - ./config/traefik:/etc/traefik/dynamic
      - /var/run/docker.sock:/var/run/docker.sock:ro
"""
        content += traefik_content

    # Write the file
    with open(setup_file, 'w') as f:
        f.write(content)

def handle(args):
    """Handle init command"""
    config = Config()
    
    # Check if already initialized
    if config.is_initialized() and not args.force:
        print_warning("SparkBaaS is already initialized.")
        print_info("Use --force to reinitialize.")
        return 1
    
    print_section("Initializing SparkBaaS")
    
    # Check prerequisites
    if not args.skip_checks:
        if not check_prerequisites():
            return 1
    
    # Generate .env file
    if not generate_env_file(config, args.env_file, args.force):
        return 1
    
    # Create directories
    if not create_directories(config):
        return 1
    
    # Run setup containers
    if not run_setup_containers(config, not args.no_traefik):
        return 1
    
    # Mark as initialized
    config.mark_as_initialized()
    
    print_section("Initialization Complete")
    print_success("SparkBaaS has been successfully initialized!")
    print_info("To start all services, run: spark start")
    
    return 0