import os
import subprocess
import json
from pathlib import Path

from sparkbaas.core.compose import DockerCompose
from sparkbaas.core.config import Config
from sparkbaas.ui.console import (
    console, print_step, print_success, print_error, 
    print_warning, print_info, print_section
)
from rich.table import Table
from rich.console import Console

def setup_parser(parser):
    """Set up command-line arguments for status command"""
    parser.add_argument(
        "--services", type=str, nargs="+",
        help="Specific services to check"
    )
    parser.add_argument(
        "--logs", "-l", action="store_true",
        help="Show logs for services"
    )
    parser.add_argument(
        "--tail", type=int, default=20,
        help="Number of lines to show from logs"
    )
    return parser

def parse_ps_output(output):
    """
    Parse docker compose ps output into structured data
    
    Args:
        output: String output from docker-compose ps
        
    Returns:
        List of dictionaries with service info
    """
    try:
        # Try to get JSON output directly if using newer Docker Compose
        cmd = ["docker", "compose", "ps", "--format", "json"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            services = json.loads(result.stdout)
            return services
    except:
        pass
    
    # Fallback to text parsing for older Docker Compose versions
    services = []
    lines = output.strip().split('\n')
    
    # Skip header line
    if len(lines) <= 1:
        return services
    
    # Parse each line
    for line in lines[1:]:
        parts = line.split()
        if len(parts) >= 4:
            service = {
                "name": parts[0],
                "state": parts[len(parts) - 2],
                "health": parts[len(parts) - 1] if len(parts) > 3 else "",
                "ports": " ".join([p for p in parts if ":" in p])
            }
            services.append(service)
    
    return services

def get_services_status(args):
    """
    Get status of services
    
    Returns:
        List of service status dicts
    """
    # Get Docker Compose wrapper
    compose = DockerCompose()
    
    try:
        output = compose.ps(services=args.services)
        services = parse_ps_output(output)
        return services
    except Exception as e:
        print_error(f"Failed to get service status: {str(e)}")
        return []

def show_logs(args):
    """Show logs for services"""
    if not args.logs:
        return
    
    print_section("Service Logs")
    
    # Get Docker Compose wrapper
    compose = DockerCompose()
    
    try:
        compose.logs(services=args.services, follow=False, tail=args.tail)
    except Exception as e:
        print_error(f"Failed to get logs: {str(e)}")

def get_system_info():
    """Get system information"""
    from sparkbaas.core.utils import get_os_type, get_available_memory_gb, get_cpu_cores
    
    info = {
        "os": get_os_type(),
        "memory_gb": get_available_memory_gb(),
        "cpu_cores": get_cpu_cores(),
        "docker": None,
        "docker_compose": None
    }
    
    # Get Docker version
    try:
        cmd = ["docker", "--version"]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        info["docker"] = result.stdout.strip()
    except:
        pass
    
    # Get Docker Compose version
    try:
        cmd = ["docker", "compose", "version"]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        info["docker_compose"] = result.stdout.strip()
    except:
        pass
    
    return info

def display_status(services, config):
    """Display service status in a table"""
    # Create status table
    table = Table(title="SparkBaaS Service Status")
    table.add_column("Service", style="cyan")
    table.add_column("Status", style="green")
    table.add_column("Health", style="magenta")
    table.add_column("Ports", style="yellow")
    
    if not services:
        print_warning("No services found.")
        return
    
    # Add rows for each service
    for service in services:
        name = service.get("name", "")
        state = service.get("state", "")
        health = service.get("health", "")
        ports = service.get("ports", "")
        
        # Colorize state
        if state.lower() == "running":
            state_display = "[bold green]Running[/bold green]"
        elif state.lower() == "exited":
            state_display = "[bold red]Exited[/bold red]"
        else:
            state_display = f"[bold yellow]{state}[/bold yellow]"
        
        # Colorize health
        if health.lower() == "healthy":
            health_display = "[bold green]Healthy[/bold green]"
        elif health.lower() == "unhealthy":
            health_display = "[bold red]Unhealthy[/bold red]"
        elif health.lower() == "starting":
            health_display = "[bold yellow]Starting[/bold yellow]"
        else:
            health_display = health
        
        table.add_row(name, state_display, health_display, ports)
    
    # Print the table
    console.print(table)

def display_system_info(info):
    """Display system information"""
    print_section("System Information")
    
    # Create info table
    table = Table()
    table.add_column("Component", style="cyan")
    table.add_column("Value", style="green")
    
    table.add_row("Operating System", info["os"])
    
    if info["memory_gb"] is not None:
        table.add_row("Available Memory", f"{info['memory_gb']:.2f} GB")
    
    if info["cpu_cores"] is not None:
        table.add_row("CPU Cores", str(info["cpu_cores"]))
    
    if info["docker"]:
        table.add_row("Docker", info["docker"])
    
    if info["docker_compose"]:
        table.add_row("Docker Compose", info["docker_compose"])
    
    # Print the table
    console.print(table)

def handle(args):
    """Handle status command"""
    config = Config()
    
    # Check if initialized
    if not config.is_initialized():
        print_error("SparkBaaS is not initialized.")
        print_info("Run 'spark init' to initialize SparkBaaS.")
        return 1
    
    print_section("SparkBaaS Status")
    
    # Get service status
    services = get_services_status(args)
    
    # Display service status
    display_status(services, config)
    
    # Show logs if requested
    if args.logs:
        show_logs(args)
    
    # Display system information
    system_info = get_system_info()
    display_system_info(system_info)
    
    return 0