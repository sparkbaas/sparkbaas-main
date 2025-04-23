import os
import sys
import shutil
import subprocess
from pathlib import Path

from sparkbaas.core.compose import DockerCompose
from sparkbaas.core.config import Config
from sparkbaas.core.utils import ensure_dir
from sparkbaas.ui.console import (
    console, print_banner, print_step, print_success, 
    print_error, print_warning, print_info, print_section, confirm
)

def setup_parser(parser):
    """Set up command-line arguments for reset command"""
    parser.add_argument(
        "--force", action="store_true", 
        help="Force reset without confirmation prompt"
    )
    parser.add_argument(
        "--keep-env", action="store_true",
        help="Keep the environment file (.env)"
    )
    return parser

def backup_env_file(config):
    """Backup the .env file if it exists"""
    env_file = config.env_file
    
    if env_file.exists():
        from datetime import datetime
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        backup_file = env_file.with_name(f".env.backup-{timestamp}")
        
        print_step(f"Backing up environment file to {backup_file.name}")
        shutil.copy2(env_file, backup_file)
        print_success("Environment file backed up")
        return True
    
    print_info("No environment file found to backup")
    return False

def remove_env_file(config):
    """Remove the .env file"""
    env_file = config.env_file
    
    if env_file.exists():
        print_step("Removing environment file")
        env_file.unlink()
        print_success("Environment file removed")
        return True
    
    return False

def stop_and_remove_containers(config):
    """Stop and remove all SparkBaaS containers"""
    print_step("Stopping and removing SparkBaaS containers")
    
    compose = DockerCompose()
    # Use the default docker-compose.yml for the main services
    try:
        # Stop and remove main containers
        compose.down(volumes=True, remove_orphans=True)
        
        # Use setup_compose for the setup services
        setup_compose = compose.setup_compose()
        setup_compose.down(volumes=True, remove_orphans=True)
        
        print_success("All SparkBaaS containers stopped and removed")
        return True
    except Exception as e:
        print_error(f"Failed to stop containers: {str(e)}")
        
        # Try direct Docker commands as fallback
        try:
            print_info("Trying direct Docker commands...")
            subprocess.run(
                ["docker", "ps", "-a", "--filter", "name=sparkbaas", "-q"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False
            )
            container_ids = subprocess.run(
                ["docker", "ps", "-a", "--filter", "name=sparkbaas", "-q"],
                capture_output=True, text=True, check=False
            ).stdout.strip()
            
            if container_ids:
                subprocess.run(
                    ["docker", "rm", "-f"] + container_ids.split('\n'),
                    stderr=subprocess.PIPE, stdout=subprocess.PIPE, check=False
                )
                print_success("Containers removed with direct Docker commands")
        except Exception as docker_err:
            print_warning(f"Docker fallback failed: {str(docker_err)}")
        
        return False

def remove_docker_volumes(config):
    """Remove all SparkBaaS Docker volumes"""
    print_step("Removing SparkBaaS Docker volumes")
    
    try:
        # Get all volumes containing "sparkbaas" in their name
        result = subprocess.run(
            ["docker", "volume", "ls", "--filter", "name=sparkbaas", "-q"],
            capture_output=True, text=True, check=True
        )
        
        volumes = result.stdout.strip().split('\n')
        volumes = [v for v in volumes if v]
        
        if volumes:
            # Remove the volumes
            subprocess.run(
                ["docker", "volume", "rm"] + volumes,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False
            )
            print_success(f"Removed {len(volumes)} Docker volumes")
        else:
            print_info("No SparkBaaS Docker volumes found")
        
        return True
    except Exception as e:
        print_warning(f"Failed to remove Docker volumes: {str(e)}")
        return False

def remove_docker_networks(config):
    """Remove all SparkBaaS Docker networks"""
    print_step("Removing SparkBaaS Docker networks")
    
    try:
        # Get all networks containing "sparkbaas" in their name
        result = subprocess.run(
            ["docker", "network", "ls", "--filter", "name=sparkbaas", "--format", "{{.Name}}"],
            capture_output=True, text=True, check=True
        )
        
        networks = result.stdout.strip().split('\n')
        networks = [n for n in networks if n]
        
        if networks:
            for network in networks:
                subprocess.run(
                    ["docker", "network", "rm", network],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False
                )
            print_success(f"Removed {len(networks)} Docker networks")
        else:
            print_info("No SparkBaaS Docker networks found")
        
        return True
    except Exception as e:
        print_warning(f"Failed to remove Docker networks: {str(e)}")
        return False

def clear_data_directories(config):
    """Clear persistent data directories"""
    print_step("Clearing persistent data directories")
    
    data_dir = config.get_data_dir()
    
    # List of directories to clear
    directories = [
        data_dir / "postgres",
        data_dir / "keycloak",
        data_dir / "kong",
        data_dir / "functions",
    ]
    
    for directory in directories:
        if directory.exists():
            try:
                # Remove directory contents
                shutil.rmtree(directory)
                # Recreate empty directory
                directory.mkdir(parents=True, exist_ok=True)
                print_success(f"Cleared directory: {directory.relative_to(config.project_root)}")
            except Exception as e:
                print_warning(f"Failed to clear directory {directory.name}: {str(e)}")
                try:
                    # Try with sudo if available
                    if shutil.which("sudo") is not None:
                        print_info(f"Trying with sudo...")
                        subprocess.run(["sudo", "rm", "-rf", str(directory)], check=False)
                        directory.mkdir(parents=True, exist_ok=True)
                        print_success(f"Cleared directory with sudo: {directory.name}")
                except:
                    print_error(f"Could not clear directory: {directory.name}")
        else:
            # Directory doesn't exist, create it
            directory.mkdir(parents=True, exist_ok=True)
            print_info(f"Created directory: {directory.relative_to(config.project_root)}")
    
    return True

def reset_state(config):
    """Reset the SparkBaaS state"""
    print_step("Resetting SparkBaaS state")
    
    # Remove state file
    state_file = config.state_file
    if state_file.exists():
        state_file.unlink()
        print_success("State file removed")
    
    # Set initialized status to False
    config.save_state({
        'version': '0.0.0',
        'initialized': False,
        'components': {}
    })
    
    print_success("SparkBaaS state reset")
    return True

def handle(args):
    """Handle reset command"""
    config = Config()
    
    print_section("Resetting SparkBaaS Environment")
    
    # Confirm reset unless --force is specified
    if not args.force:
        print_warning("This will remove all SparkBaaS containers, volumes, and data.")
        print_warning("All data will be lost. Environment variables will be backed up.")
        print_warning("This is designed for testing purposes and should NOT be used in production.")
        
        if not confirm("Are you sure you want to proceed?", default=False):
            print_info("Reset cancelled.")
            return 0
    
    # Backup and remove .env file (if requested)
    backup_env_file(config)
    if not args.keep_env:
        remove_env_file(config)
    
    # Stop and remove containers
    stop_and_remove_containers(config)
    
    # Remove Docker volumes
    remove_docker_volumes(config)
    
    # Remove Docker networks
    remove_docker_networks(config)
    
    # Clear data directories
    clear_data_directories(config)
    
    # Reset state
    reset_state(config)
    
    print_section("Reset Complete")
    print_success("SparkBaaS environment has been reset.")
    print_info("To reinitialize SparkBaaS, run: spark init")
    
    return 0