#!/usr/bin/env python3
import os
import sys
from pathlib import Path
import subprocess
import json
import time

from sparkbaas.core.compose import DockerCompose
from sparkbaas.core.config import Config
from sparkbaas.core.utils import ensure_dir, load_json, save_json
from sparkbaas.ui.console import (
    console, print_step, print_success, print_error, 
    print_warning, print_info, print_section, confirm, select
)
from rich.table import Table
from sparkbaas import __version__ as current_version

def setup_parser(parser):
    """Set up command-line arguments for upgrade command"""
    parser.add_argument(
        "--check", action="store_true",
        help="Check for available upgrades without applying them"
    )
    parser.add_argument(
        "--component", type=str,
        choices=["all", "database", "auth", "api", "functions", "monitoring"],
        default="all",
        help="Specific component to upgrade (default: all)"
    )
    parser.add_argument(
        "--force", "-f", action="store_true",
        help="Force upgrade without confirmation"
    )
    parser.add_argument(
        "--no-backup", action="store_true",
        help="Skip automatic backup before upgrade"
    )
    return parser

def get_platform_versions():
    """
    Get available platform versions and upgrade paths
    
    Returns:
        Dict of version information
    """
    # In a production environment, this would fetch versions from a remote source
    # For now, we'll use a simple hardcoded version list
    return {
        "platform": {
            "current": current_version,
            "latest": "0.1.1",
            "available": ["0.1.0", "0.1.1"]
        },
        "components": {
            "database": {
                "current": "16.0",
                "latest": "16.1",
                "available": ["16.0", "16.1"]
            },
            "auth": {
                "current": "22.0.0",
                "latest": "22.0.1",
                "available": ["22.0.0", "22.0.1"]
            },
            "api": {
                "current": "3.0.0",
                "latest": "3.1.0",
                "available": ["3.0.0", "3.1.0"]
            },
            "functions": {
                "current": "1.0.0",
                "latest": "1.0.0",
                "available": ["1.0.0"]
            },
            "monitoring": {
                "current": "8.10.0",
                "latest": "8.11.0",
                "available": ["8.10.0", "8.11.0"]
            }
        }
    }

def check_for_upgrades():
    """
    Check for available upgrades
    
    Returns:
        Dict of available upgrades
    """
    versions = get_platform_versions()
    upgrades = {
        "platform": versions["platform"]["current"] != versions["platform"]["latest"],
        "components": {}
    }
    
    for component, info in versions["components"].items():
        upgrades["components"][component] = info["current"] != info["latest"]
    
    return upgrades

def print_upgrade_status():
    """
    Print upgrade status table
    """
    versions = get_platform_versions()
    upgrades = check_for_upgrades()
    
    # Print platform status
    if upgrades["platform"]:
        print_info(f"Platform upgrade available: {versions['platform']['current']} → {versions['platform']['latest']}")
    else:
        print_info(f"Platform is up to date: {versions['platform']['current']}")
    
    # Create component status table
    table = Table(title="Component Versions")
    table.add_column("Component", style="cyan")
    table.add_column("Current", style="green")
    table.add_column("Latest", style="yellow")
    table.add_column("Status", style="magenta")
    
    # Add rows for each component
    for component, info in versions["components"].items():
        current = info["current"]
        latest = info["latest"]
        status = "[bold green]Up to date" if current == latest else "[bold yellow]Upgrade available"
        
        table.add_row(component.capitalize(), current, latest, status)
    
    # Print the table
    console.print(table)

def upgrade_component(component, config, force=False):
    """
    Upgrade a specific component
    
    Args:
        component: Component name to upgrade
        config: Config instance
        force: Whether to force upgrade without confirmation
        
    Returns:
        True if successful, False otherwise
    """
    versions = get_platform_versions()
    
    if component == "platform":
        print_info("Upgrading platform components...")
        # In a real implementation, this would update the CLI itself
        print_warning("Platform upgrade would be performed here.")
        return True
    
    component_info = versions["components"].get(component)
    if not component_info:
        print_error(f"Unknown component: {component}")
        return False
    
    if component_info["current"] == component_info["latest"]:
        print_info(f"Component '{component}' is already up to date.")
        return True
    
    print_step(f"Upgrading {component} from {component_info['current']} to {component_info['latest']}...")
    
    if not force:
        if not confirm(f"Continue with {component} upgrade?", default=True):
            print_info(f"{component.capitalize()} upgrade cancelled.")
            return True
    
    # In a real implementation, this would:
    # 1. Pull new images for the component
    # 2. Stop the affected services
    # 3. Apply any migrations/changes
    # 4. Start the updated services
    compose = DockerCompose()
    
    try:
        # Example implementation for demonstration purposes
        print_info(f"Pulling latest {component} images...")
        # This would pull the specific images for the component
        compose.run("pull", services=[component] if component != "api" else ["gateway"], capture_output=True)
        
        print_info(f"Restarting {component} services...")
        # This would restart the specific services for the component
        compose.stop(services=[component] if component != "api" else ["gateway"])
        compose.up(services=[component] if component != "api" else ["gateway"], detached=True)
        
        print_success(f"{component.capitalize()} upgraded successfully to version {component_info['latest']}")
        return True
    except Exception as e:
        print_error(f"Failed to upgrade {component}: {str(e)}")
        return False

def perform_backup(config):
    """
    Perform a backup before upgrading
    
    Args:
        config: Config instance
        
    Returns:
        True if successful, False otherwise
    """
    from sparkbaas.commands import backup_cmd
    
    print_step("Creating backup before upgrade...")
    
    # Create a mock args object with default values
    class MockArgs:
        pass
    
    args = MockArgs()
    args.file = None  # Use default file name
    args.no_db = False  # Include database
    args.no_files = False  # Include files
    
    # Call backup command
    return backup_cmd.create_backup(args, config)

def handle(args):
    """Handle upgrade command"""
    config = Config()
    
    # Check if initialized
    if not config.is_initialized():
        print_error("SparkBaaS is not initialized.")
        print_info("Run 'spark init' to initialize SparkBaaS.")
        return 1
    
    # Check for upgrades only
    if args.check:
        print_section("Available Upgrades")
        print_upgrade_status()
        return 0
    
    print_section("Upgrade SparkBaaS")
    
    # Check if services are running
    compose = DockerCompose()
    ps_output = compose.run("ps", capture_output=True).stdout
    services_running = len(ps_output.strip()) > 0
    
    # Show current status
    print_upgrade_status()
    
    # Check if any upgrades are actually available
    upgrades = check_for_upgrades()
    platform_upgrade = upgrades["platform"]
    component_upgrades = any(upgrades["components"].values())
    
    if not platform_upgrade and not component_upgrades:
        print_success("All components are already up to date!")
        return 0
    
    # Create backup before upgrading
    if not args.no_backup:
        if not perform_backup(config):
            print_error("Backup failed. Upgrade aborted.")
            print_info("You can use --no-backup to skip backup, but this is not recommended.")
            return 1
    else:
        print_warning("Skipping backup before upgrade. This is not recommended.")
    
    # Handle component-specific upgrade
    if args.component != "all":
        return 0 if upgrade_component(args.component, config, args.force) else 1
    
    # Perform platform upgrade if available
    if platform_upgrade:
        if not upgrade_component("platform", config, args.force):
            print_error("Platform upgrade failed.")
            return 1
    
    # Perform component upgrades
    success = True
    for component, needs_upgrade in upgrades["components"].items():
        if needs_upgrade:
            if not upgrade_component(component, config, args.force):
                success = False
    
    if success:
        print_success("Upgrade completed successfully!")
    else:
        print_warning("Some components failed to upgrade. Check the logs for details.")
    
    # Restart services if they were running
    if services_running:
        print_info("Restarting services...")
        compose.up(detached=True)
    
    return 0 if success else 1