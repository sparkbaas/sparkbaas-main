import os
from pathlib import Path

from sparkbaas.core.compose import DockerCompose
from sparkbaas.core.config import Config
from sparkbaas.ui.console import (
    console, print_step, print_success, print_error, 
    print_warning, print_info, print_section, confirm
)

def setup_parser(parser):
    """Set up command-line arguments for stop command"""
    parser.add_argument(
        "--services", type=str, nargs="+",
        help="Specific services to stop"
    )
    parser.add_argument(
        "--volumes", "-v", action="store_true",
        help="Remove volumes (WARNING: This will delete all data)"
    )
    parser.add_argument(
        "--force", "-f", action="store_true",
        help="Don't ask for confirmation"
    )
    return parser

def stop_services(args):
    """Stop SparkBaaS services"""
    print_step("Stopping services...")
    
    # Get Docker Compose wrapper
    compose = DockerCompose()
    
    try:
        # If specific services are provided, use stop
        if args.services:
            compose.stop(services=args.services)
            print_success(f"Stopped services: {', '.join(args.services)}")
        # Otherwise, use down
        else:
            # Confirm before removing volumes
            if args.volumes and not args.force:
                if not confirm(
                    "[bold red]WARNING:[/bold red] This will delete all data. Are you sure?",
                    default=False
                ):
                    print_info("Operation cancelled.")
                    return True
            
            compose.down(volumes=args.volumes)
            print_success("All services stopped successfully.")
        
        return True
    except Exception as e:
        print_error(f"Failed to stop services: {str(e)}")
        return False

def handle(args):
    """Handle stop command"""
    config = Config()
    
    # Check if initialized
    if not config.is_initialized():
        print_error("SparkBaaS is not initialized.")
        print_info("Run 'spark init' to initialize SparkBaaS.")
        return 1
    
    print_section("Stopping SparkBaaS")
    
    # Stop services
    if not stop_services(args):
        return 1
    
    print_section("SparkBaaS Stopped")
    
    if args.volumes:
        print_warning("All volumes have been removed. Data has been deleted.")
    else:
        print_success("SparkBaaS services have been stopped. Data is preserved.")
        print_info("Use 'spark start' to start services again.")
    
    return 0