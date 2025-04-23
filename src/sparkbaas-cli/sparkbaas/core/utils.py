import os
import sys
import platform
import shutil
import tempfile
from pathlib import Path
import yaml
import json

def get_project_root():
    """
    Find the project root directory
    
    Returns:
        Path to the project root directory
    """
    # Start with the current directory
    current_dir = Path.cwd()
    
    # Try to find the src directory
    while current_dir != current_dir.parent:
        # Check if this is the root directory (contains src/compose)
        if (current_dir / "src" / "compose").exists():
            return current_dir
            
        # Check if we're in the sparkbaas-cli directory
        if (current_dir.name == "sparkbaas-cli" and 
            current_dir.parent.name == "src" and 
            (current_dir.parent.parent / "src" / "compose").exists()):
            return current_dir.parent.parent
            
        # Check if this is inside the src directory
        if current_dir.name == "src" and (current_dir / "compose").exists():
            return current_dir.parent
            
        # Move up to parent directory
        current_dir = current_dir.parent
    
    # If we get here, we couldn't find the project root
    # Force a fallback to the expected structure
    current_dir = Path.cwd()
    if "gitlocal/zzNotInRepo/sparkbaas" in str(current_dir):
        parts = str(current_dir).split("zzNotInRepo/sparkbaas")
        repo_root = parts[0] + "zzNotInRepo/sparkbaas"
        return Path(repo_root)
        
    raise FileNotFoundError(
        "Could not find project root directory. "
        "Make sure you are running the command from within the SparkBaaS project."
    )

def ensure_dir(path):
    """
    Ensure a directory exists
    
    Args:
        path: Path to the directory
    """
    path = Path(path)
    path.mkdir(parents=True, exist_ok=True)
    return path

def copy_template(src, dest, replacements=None):
    """
    Copy a template file and replace placeholders
    
    Args:
        src: Source template file
        dest: Destination file
        replacements: Dict of placeholder replacements
    """
    # Read the template
    with open(src, 'r') as f:
        content = f.read()
    
    # Replace placeholders
    if replacements:
        for key, value in replacements.items():
            content = content.replace(f"{{{{{{ {key} }}}}}}", str(value))
    
    # Write the output
    with open(dest, 'w') as f:
        f.write(content)

def load_yaml(file_path):
    """
    Load a YAML file
    
    Args:
        file_path: Path to YAML file
        
    Returns:
        Parsed YAML content
    """
    with open(file_path, 'r') as f:
        return yaml.safe_load(f)

def save_yaml(data, file_path):
    """
    Save data to a YAML file
    
    Args:
        data: Data to save
        file_path: Path to save YAML file
    """
    with open(file_path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False)

def load_json(file_path):
    """
    Load a JSON file
    
    Args:
        file_path: Path to JSON file
        
    Returns:
        Parsed JSON content
    """
    with open(file_path, 'r') as f:
        return json.load(f)

def save_json(data, file_path):
    """
    Save data to a JSON file
    
    Args:
        data: Data to save
        file_path: Path to save JSON file
    """
    with open(file_path, 'w') as f:
        json.dump(data, f, indent=2)

def is_docker_available():
    """
    Check if Docker is installed and available
    
    Returns:
        True if Docker is available, False otherwise
    """
    docker_cmd = "docker --version"
    try:
        result = os.system(f"{docker_cmd} > {os.devnull} 2>&1")
        return result == 0
    except:
        return False

def is_docker_compose_available():
    """
    Check if Docker Compose is installed and available
    
    Returns:
        True if Docker Compose is available, False otherwise
    """
    # Modern Docker CLI with compose command
    modern_cmd = "docker compose version"
    legacy_cmd = "docker-compose --version"
    
    try:
        result = os.system(f"{modern_cmd} > {os.devnull} 2>&1")
        if result == 0:
            return True
            
        result = os.system(f"{legacy_cmd} > {os.devnull} 2>&1")
        return result == 0
    except:
        return False

def get_os_type():
    """
    Get the current operating system type
    
    Returns:
        String indicating the OS type: "Windows", "Linux", "macOS", or "Unknown"
    """
    system = platform.system()
    if system == "Windows":
        return "Windows"
    elif system == "Linux":
        return "Linux"
    elif system == "Darwin":
        return "macOS"
    else:
        return "Unknown"

def get_available_memory_gb():
    """
    Get available system memory in GB
    
    Returns:
        Available memory in GB (float) or None if could not be determined
    """
    try:
        import psutil
        return psutil.virtual_memory().available / (1024 * 1024 * 1024)
    except:
        # Fallback for when psutil is not available
        os_type = get_os_type()
        if os_type == "Linux":
            # Try to get memory from /proc/meminfo
            try:
                with open('/proc/meminfo', 'r') as f:
                    for line in f:
                        if 'MemAvailable' in line:
                            # Extract the value (in kB)
                            kb = int(line.split()[1])
                            return kb / (1024 * 1024)
                return None
            except:
                return None
        else:
            return None

def get_cpu_cores():
    """
    Get number of CPU cores
    
    Returns:
        Number of CPU cores (int) or None if could not be determined
    """
    try:
        import psutil
        return psutil.cpu_count(logical=True)
    except:
        # Fallback for when psutil is not available
        try:
            return os.cpu_count()
        except:
            return None