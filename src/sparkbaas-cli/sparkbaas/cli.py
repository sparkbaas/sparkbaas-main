#!/usr/bin/env python3
import sys
import argparse
from pathlib import Path

from rich.console import Console
from rich.panel import Panel
from rich.table import Table

from sparkbaas.commands import (
    init_cmd,
    start_cmd,
    stop_cmd,
    status_cmd,
    migrate_cmd,
    backup_cmd,
    restore_cmd,
    functions_cmd,
    upgrade_cmd,
    reset_cmd
)
from sparkbaas.core.config import Config
from sparkbaas.ui.console import print_banner

console = Console()

def setup_parser():
    """Set up the argument parser with all subcommands"""
    parser = argparse.ArgumentParser(
        description="SparkBaaS CLI - DevOps-friendly Backend as a Service",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        "--version", action="store_true", help="Show version information"
    )
    
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Enable verbose output"
    )
    
    # Create subparsers for different commands
    subparsers = parser.add_subparsers(dest="command", help="Commands")
    
    # Init command
    init_parser = subparsers.add_parser("init", help="Initialize SparkBaaS platform")
    init_cmd.setup_parser(init_parser)
    
    # Reset command
    reset_parser = subparsers.add_parser("reset", help="Reset SparkBaaS environment")
    reset_cmd.setup_parser(reset_parser)
    
    # Start command
    start_parser = subparsers.add_parser("start", help="Start all SparkBaaS services")
    start_cmd.setup_parser(start_parser)
    
    # Stop command
    stop_parser = subparsers.add_parser("stop", help="Stop all SparkBaaS services")
    stop_cmd.setup_parser(stop_parser)
    
    # Status command
    status_parser = subparsers.add_parser("status", help="Check status of SparkBaaS services")
    status_cmd.setup_parser(status_parser)
    
    # Migrate command
    migrate_parser = subparsers.add_parser("migrate", help="Run database migrations")
    migrate_cmd.setup_parser(migrate_parser)
    
    # Backup command
    backup_parser = subparsers.add_parser("backup", help="Backup SparkBaaS data")
    backup_cmd.setup_parser(backup_parser)
    
    # Restore command
    restore_parser = subparsers.add_parser("restore", help="Restore SparkBaaS data from backup")
    restore_cmd.setup_parser(restore_parser)
    
    # Functions command
    functions_parser = subparsers.add_parser("function", help="Manage serverless functions")
    functions_cmd.setup_parser(functions_parser)
    
    # Upgrade command
    upgrade_parser = subparsers.add_parser("upgrade", help="Upgrade SparkBaaS components")
    upgrade_cmd.setup_parser(upgrade_parser)
    
    return parser

def show_version():
    """Show version information"""
    from sparkbaas import __version__
    
    console.print(Panel.fit(
        f"[bold cyan]SparkBaaS CLI[/bold cyan] [bold white]v{__version__}[/bold white]",
        border_style="cyan"
    ))
    
    # Show component versions
    table = Table(title="Component Versions")
    table.add_column("Component", style="cyan")
    table.add_column("Version", style="green")
    
    # Get component versions from docker-compose
    config = Config()
    for component, version in config.get_component_versions().items():
        table.add_row(component, version)
    
    console.print(table)

def main():
    """Main entry point for the CLI"""
    parser = setup_parser()
    args = parser.parse_args()
    
    # Show the banner
    print_banner()
    
    # Handle version flag
    if args.version:
        show_version()
        return 0
    
    # If no command is provided, show help
    if not args.command:
        parser.print_help()
        return 0
    
    try:
        # Dispatch to the appropriate command
        if args.command == "init":
            return init_cmd.handle(args)
        elif args.command == "reset":
            return reset_cmd.handle(args)
        elif args.command == "start":
            return start_cmd.handle(args)
        elif args.command == "stop":
            return stop_cmd.handle(args)
        elif args.command == "status":
            return status_cmd.handle(args)
        elif args.command == "migrate":
            return migrate_cmd.handle(args)
        elif args.command == "backup":
            return backup_cmd.handle(args)
        elif args.command == "restore":
            return restore_cmd.handle(args)
        elif args.command == "function":
            return functions_cmd.handle(args)
        elif args.command == "upgrade":
            return upgrade_cmd.handle(args)
    except KeyboardInterrupt:
        console.print("\n[yellow]Operation cancelled by user[/yellow]")
        return 1
    except Exception as e:
        console.print(f"[bold red]Error:[/bold red] {str(e)}")
        if args.verbose:
            console.print_exception()
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())