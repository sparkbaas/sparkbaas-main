import os
import sys
import shutil
from pathlib import Path
import json
import time
import subprocess

from sparkbaas.core.compose import DockerCompose
from sparkbaas.core.config import Config
from sparkbaas.core.utils import ensure_dir, load_json, save_json
from sparkbaas.ui.console import (
    console, print_step, print_success, print_error, 
    print_warning, print_info, print_section, confirm, select
)
from rich.table import Table

def setup_parser(parser):
    """Set up command-line arguments for function command"""
    subparsers = parser.add_subparsers(dest="action", help="Function actions")
    
    # Deploy function
    deploy_parser = subparsers.add_parser("deploy", help="Deploy a function")
    deploy_parser.add_argument(
        "path", type=str,
        help="Path to function directory or file"
    )
    deploy_parser.add_argument(
        "--name", type=str,
        help="Function name (defaults to directory/file name)"
    )
    deploy_parser.add_argument(
        "--runtime", type=str, choices=["node", "python", "go", "custom"],
        help="Function runtime"
    )
    
    # List functions
    list_parser = subparsers.add_parser("list", help="List deployed functions")
    
    # Delete function
    delete_parser = subparsers.add_parser("delete", help="Delete a function")
    delete_parser.add_argument(
        "name", type=str, nargs="?",
        help="Function name (interactive if not specified)"
    )
    delete_parser.add_argument(
        "--force", "-f", action="store_true",
        help="Force delete without confirmation"
    )
    
    # Logs function
    logs_parser = subparsers.add_parser("logs", help="Show function logs")
    logs_parser.add_argument(
        "name", type=str, nargs="?",
        help="Function name (interactive if not specified)"
    )
    logs_parser.add_argument(
        "--tail", type=int, default=100,
        help="Number of lines to show"
    )
    logs_parser.add_argument(
        "--follow", "-f", action="store_true",
        help="Follow log output"
    )
    
    return parser

def detect_runtime(function_path):
    """
    Auto-detect the function runtime based on files present
    
    Args:
        function_path: Path to function directory or file
        
    Returns:
        Detected runtime or None
    """
    path = Path(function_path)
    
    # Check if it's a file
    if path.is_file():
        ext = path.suffix.lower()
        if ext == '.js':
            return "node"
        elif ext == '.py':
            return "python"
        elif ext == '.go':
            return "go"
        else:
            return None
    
    # Check if it's a directory
    if path.is_dir():
        # Check for package.json (Node.js)
        if (path / "package.json").exists():
            return "node"
        
        # Check for requirements.txt (Python)
        if (path / "requirements.txt").exists():
            return "python"
        
        # Check for go.mod (Go)
        if (path / "go.mod").exists():
            return "go"
        
        # Count file extensions
        exts = {'.js': 0, '.py': 0, '.go': 0}
        for file in path.glob('**/*'):
            if file.is_file():
                ext = file.suffix.lower()
                if ext in exts:
                    exts[ext] += 1
        
        # Use the most common extension
        if exts['.js'] > exts['.py'] and exts['.js'] > exts['.go']:
            return "node"
        elif exts['.py'] > exts['.js'] and exts['.py'] > exts['.go']:
            return "python"
        elif exts['.go'] > exts['.js'] and exts['.go'] > exts['.py']:
            return "go"
    
    return None

def get_function_metadata(config):
    """
    Get metadata for all deployed functions
    
    Returns:
        Dict of function metadata
    """
    functions_dir = config.project_root / "src" / "data" / "functions"
    metadata_file = functions_dir / "metadata.json"
    
    if not metadata_file.exists():
        return {}
    
    try:
        return load_json(metadata_file)
    except Exception:
        return {}

def save_function_metadata(config, metadata):
    """
    Save function metadata
    
    Args:
        metadata: Dict of function metadata
    """
    functions_dir = config.project_root / "src" / "data" / "functions"
    ensure_dir(functions_dir)
    
    metadata_file = functions_dir / "metadata.json"
    save_json(metadata, metadata_file)

def deploy_function(args, config):
    """
    Deploy a function
    
    Args:
        args: Command arguments
        config: Config instance
        
    Returns:
        True if successful, False otherwise
    """
    function_path = Path(args.path)
    
    # Check if path exists
    if not function_path.exists():
        print_error(f"Function path does not exist: {function_path}")
        return False
    
    # Determine function name
    function_name = args.name
    if not function_name:
        if function_path.is_file():
            function_name = function_path.stem
        else:
            function_name = function_path.name
    
    # Normalize function name
    function_name = function_name.lower().replace(" ", "_").replace("-", "_")
    
    # Determine runtime
    runtime = args.runtime
    if not runtime:
        detected_runtime = detect_runtime(function_path)
        if not detected_runtime:
            print_warning("Could not detect function runtime.")
            runtime = select(
                "Select function runtime:",
                choices=["node", "python", "go", "custom"],
                default="node"
            )
        else:
            print_info(f"Detected runtime: {detected_runtime}")
            runtime = detected_runtime
    
    print_step(f"Deploying function '{function_name}' with {runtime} runtime...")
    
    # Create function directory
    functions_dir = config.project_root / "src" / "data" / "functions"
    ensure_dir(functions_dir)
    
    function_dir = functions_dir / function_name
    if function_dir.exists():
        print_warning(f"Function '{function_name}' already exists.")
        if not confirm("Overwrite existing function?", default=False):
            print_info("Deployment cancelled.")
            return False
        
        # Remove existing function
        shutil.rmtree(function_dir)
    
    # Create function directory
    ensure_dir(function_dir)
    
    # Copy function files
    print_info("Copying function files...")
    if function_path.is_file():
        # Copy single file
        shutil.copy(function_path, function_dir)
    else:
        # Copy entire directory
        for item in function_path.glob('**/*'):
            if item.is_file():
                rel_path = item.relative_to(function_path)
                dest_path = function_dir / rel_path
                ensure_dir(dest_path.parent)
                shutil.copy(item, dest_path)
    
    # Create function.json if it doesn't exist
    function_json = function_dir / "function.json"
    if not function_json.exists():
        # Create default function.json
        function_config = {
            "name": function_name,
            "runtime": runtime,
            "handler": "index.handler" if runtime == "node" else "main.handler" if runtime == "python" else "main",
            "timeout": 30,
            "memory": 128,
            "environment": {},
            "created": time.time(),
            "updated": time.time()
        }
        
        save_json(function_config, function_json)
    
    # Update function metadata
    metadata = get_function_metadata(config)
    metadata[function_name] = {
        "runtime": runtime,
        "path": str(function_dir.relative_to(config.project_root)),
        "created": time.time(),
        "updated": time.time()
    }
    save_function_metadata(config, metadata)
    
    # Check if we need to restart the function service
    compose = DockerCompose()
    ps_output = compose.run("ps", capture_output=True).stdout
    if "functions" in ps_output:
        print_info("Restarting functions service to apply changes...")
        compose.stop(services=["functions"])
        compose.up(services=["functions"], detached=True)
    
    print_success(f"Function '{function_name}' deployed successfully.")
    print_info(f"Invoke URL: http://localhost:8000/functions/{function_name}")
    
    return True

def list_functions(args, config):
    """
    List deployed functions
    
    Args:
        args: Command arguments
        config: Config instance
        
    Returns:
        True if successful, False otherwise
    """
    metadata = get_function_metadata(config)
    
    if not metadata:
        print_info("No functions deployed.")
        return True
    
    # Create table
    table = Table(title="Deployed Functions")
    table.add_column("Name", style="cyan")
    table.add_column("Runtime", style="green")
    table.add_column("Created", style="magenta")
    table.add_column("Updated", style="yellow")
    table.add_column("Invoke URL", style="blue")
    
    # Add rows
    for name, data in metadata.items():
        created = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(data.get("created", 0)))
        updated = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(data.get("updated", 0)))
        url = f"http://localhost:8000/functions/{name}"
        
        table.add_row(name, data.get("runtime", "unknown"), created, updated, url)
    
    # Print the table
    console.print(table)
    
    return True

def delete_function(args, config):
    """
    Delete a function
    
    Args:
        args: Command arguments
        config: Config instance
        
    Returns:
        True if successful, False otherwise
    """
    metadata = get_function_metadata(config)
    
    if not metadata:
        print_info("No functions deployed.")
        return True
    
    # Get function name
    function_name = args.name
    if not function_name:
        choices = list(metadata.keys()) + ["Cancel"]
        function_name = select(
            "Select function to delete:",
            choices=choices
        )
        
        if function_name == "Cancel":
            print_info("Delete cancelled.")
            return True
    
    # Check if function exists
    if function_name not in metadata:
        print_error(f"Function '{function_name}' not found.")
        return False
    
    # Confirm delete
    if not args.force:
        if not confirm(f"Delete function '{function_name}'?", default=False):
            print_info("Delete cancelled.")
            return True
    
    print_step(f"Deleting function '{function_name}'...")
    
    # Remove function directory
    function_dir = config.project_root / metadata[function_name].get("path", "")
    if function_dir.exists():
        shutil.rmtree(function_dir)
    
    # Update metadata
    del metadata[function_name]
    save_function_metadata(config, metadata)
    
    # Check if we need to restart the function service
    compose = DockerCompose()
    ps_output = compose.run("ps", capture_output=True).stdout
    if "functions" in ps_output:
        print_info("Restarting functions service to apply changes...")
        compose.stop(services=["functions"])
        compose.up(services=["functions"], detached=True)
    
    print_success(f"Function '{function_name}' deleted successfully.")
    
    return True

def show_function_logs(args, config):
    """
    Show function logs
    
    Args:
        args: Command arguments
        config: Config instance
        
    Returns:
        True if successful, False otherwise
    """
    metadata = get_function_metadata(config)
    
    if not metadata:
        print_info("No functions deployed.")
        return True
    
    # Get function name
    function_name = args.name
    if not function_name:
        choices = list(metadata.keys()) + ["Cancel"]
        function_name = select(
            "Select function to show logs for:",
            choices=choices
        )
        
        if function_name == "Cancel":
            print_info("Logs cancelled.")
            return True
    
    # Check if function exists
    if function_name not in metadata:
        print_error(f"Function '{function_name}' not found.")
        return False
    
    print_step(f"Showing logs for function '{function_name}'...")
    
    # Get Docker Compose wrapper
    compose = DockerCompose()
    
    try:
        # Check if functions service is running
        ps_output = compose.run("ps", capture_output=True).stdout
        if "functions" not in ps_output:
            print_warning("Functions service is not running.")
            print_info("Start services with 'spark start' to see logs.")
            return False
        
        # Show logs
        cmd = ["logs"]
        if args.follow:
            cmd.append("-f")
        if args.tail:
            cmd.extend(["--tail", str(args.tail)])
        cmd.append("functions")
        
        # Filter logs for specific function
        cmd = ["logs", "functions"]
        cmd_str = " ".join(cmd)
        
        # Use grep to filter logs for specific function
        compose.run(*cmd, check=False)
        
        return True
    except Exception as e:
        print_error(f"Failed to show logs: {str(e)}")
        return False

def handle(args):
    """Handle function commands"""
    config = Config()
    
    # Check if initialized
    if not config.is_initialized():
        print_error("SparkBaaS is not initialized.")
        print_info("Run 'spark init' to initialize SparkBaaS.")
        return 1
    
    # Dispatch to appropriate action
    if args.action == "deploy":
        print_section("Deploy Function")
        if not deploy_function(args, config):
            return 1
    elif args.action == "list":
        print_section("List Functions")
        if not list_functions(args, config):
            return 1
    elif args.action == "delete":
        print_section("Delete Function")
        if not delete_function(args, config):
            return 1
    elif args.action == "logs":
        print_section("Function Logs")
        if not show_function_logs(args, config):
            return 1
    else:
        print_error("Unknown action. Use 'spark function --help' for usage information.")
        return 1
    
    return 0