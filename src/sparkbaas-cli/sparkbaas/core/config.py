import os
from pathlib import Path
import re
from dotenv import load_dotenv

from sparkbaas.core.utils import get_project_root, load_yaml, save_yaml

class Config:
    """Configuration management for SparkBaaS"""
    
    def __init__(self):
        """Initialize configuration manager"""
        self.project_root = get_project_root()
        self.compose_dir = self.project_root / "src" / "compose"
        self.env_file = self.project_root / ".env"
        self.config_dir = self.compose_dir / "config"
        
        # Create state directory if it doesn't exist
        self.state_dir = self.project_root / ".sparkbaas"
        self.state_dir.mkdir(exist_ok=True)
        
        # State file to track SparkBaaS version and components
        self.state_file = self.state_dir / "state.yml"
        
        # Load environment variables
        if self.env_file.exists():
            load_dotenv(self.env_file)
    
    def get_component_versions(self):
        """
        Get the versions of SparkBaaS components from docker-compose
        
        Returns:
            Dict of component names and versions
        """
        versions = {}
        
        # Parse docker-compose.yml to get service versions
        compose_file = self.compose_dir / "docker-compose.yml"
        if not compose_file.exists():
            return versions
            
        try:
            compose_data = load_yaml(compose_file)
            services = compose_data.get('services', {})
            
            for service_name, service_config in services.items():
                if 'image' in service_config:
                    image = service_config['image']
                    # Extract version from image tag (e.g., postgres:15-alpine)
                    match = re.search(r':([^:]+)$', image)
                    if match:
                        version = match.group(1)
                    else:
                        version = "latest"
                    
                    versions[service_name] = version
        except Exception as e:
            print(f"Error parsing docker-compose.yml: {str(e)}")
        
        return versions
    
    def get_env_var(self, name, default=None):
        """
        Get an environment variable
        
        Args:
            name: Name of the environment variable
            default: Default value if not set
            
        Returns:
            Value of the environment variable or default
        """
        return os.environ.get(name, default)
    
    def set_env_var(self, name, value):
        """
        Set an environment variable in the .env file
        
        Args:
            name: Name of the environment variable
            value: Value to set
        """
        # Read existing .env file
        env_content = ""
        if self.env_file.exists():
            with open(self.env_file, 'r') as f:
                env_content = f.read()
        
        # Check if variable already exists
        pattern = re.compile(f"^{re.escape(name)}=.*$", re.MULTILINE)
        if pattern.search(env_content):
            # Replace existing variable
            env_content = pattern.sub(f"{name}={value}", env_content)
        else:
            # Add new variable
            env_content += f"\n{name}={value}"
        
        # Write updated content
        with open(self.env_file, 'w') as f:
            f.write(env_content)
        
        # Update current environment
        os.environ[name] = value
    
    def get_state(self):
        """
        Get the current state of SparkBaaS
        
        Returns:
            Dict containing state information
        """
        if not self.state_file.exists():
            return {
                'version': '0.0.0',
                'initialized': False,
                'components': {}
            }
            
        try:
            return load_yaml(self.state_file)
        except Exception:
            return {
                'version': '0.0.0',
                'initialized': False,
                'components': {}
            }
    
    def save_state(self, state):
        """
        Save the current state of SparkBaaS
        
        Args:
            state: Dict containing state information
        """
        save_yaml(state, self.state_file)
    
    def is_initialized(self):
        """
        Check if SparkBaaS has been initialized
        
        Returns:
            True if initialized, False otherwise
        """
        state = self.get_state()
        return state.get('initialized', False)
    
    def mark_as_initialized(self):
        """Mark SparkBaaS as initialized"""
        state = self.get_state()
        state['initialized'] = True
        self.save_state(state)
    
    def get_data_dir(self):
        """
        Get the data directory for SparkBaaS
        
        Returns:
            Path to data directory
        """
        return self.project_root / "src" / "data"
    
    def get_logs_dir(self):
        """
        Get the logs directory for SparkBaaS
        
        Returns:
            Path to logs directory
        """
        return self.project_root / "src" / "compose" / "logs"
    
    def get_migrations_dir(self):
        """
        Get the migrations directory for SparkBaaS
        
        Returns:
            Path to migrations directory
        """
        return self.project_root / "src" / "migrations"