import os
import subprocess
import sys
import platform
from pathlib import Path

from sparkbaas.ui.console import console, print_info, print_error, print_success
from sparkbaas.core.utils import get_project_root

class DockerCompose:
    """Wrapper for Docker Compose operations"""

    def __init__(self, compose_file=None, env_file=None):
        """Initialize the Docker Compose wrapper"""
        self.project_root = get_project_root()
        self.compose_dir = self.project_root / "src" / "compose"
        
        # Use provided compose file or default
        if compose_file:
            self.compose_file = Path(compose_file)
        else:
            self.compose_file = self.compose_dir / "docker-compose.yml"
            
        # Use provided env file or default
        if env_file:
            self.env_file = Path(env_file)
        else:
            self.env_file = self.project_root / ".env"

    def _build_command(self, *args, env_vars=None):
        """
        Build a Docker Compose command with appropriate environment variables
        
        Args:
            *args: Command and arguments to pass to docker-compose
            env_vars: Additional environment variables as dict
            
        Returns:
            List of command parts
        """
        # Set up environment variables
        cmd_env = os.environ.copy()
        
        # Add custom environment variables
        if env_vars:
            cmd_env.update(env_vars)
        
        # Build the base command
        cmd = ["docker", "compose"]
        
        # Add file reference
        cmd.extend(["-f", str(self.compose_file)])
        
        # Add environment file if it exists
        if self.env_file.exists():
            cmd.extend(["--env-file", str(self.env_file)])
            
        # Add the specific command and arguments
        cmd.extend(args)
        
        return cmd, cmd_env

    def run(self, *args, env_vars=None, capture_output=False, check=True):
        """
        Run a Docker Compose command
        
        Args:
            *args: Command and arguments to pass to docker-compose
            env_vars: Additional environment variables as dict
            capture_output: Whether to capture and return command output
            check: Whether to check return code and raise exception
            
        Returns:
            CompletedProcess object with stdout/stderr if capture_output is True
        """
        cmd, cmd_env = self._build_command(*args, env_vars=env_vars)
        
        print_info(f"Running: {' '.join(cmd)}")
        
        try:
            if capture_output:
                result = subprocess.run(
                    cmd,
                    env=cmd_env,
                    capture_output=True,
                    text=True,
                    check=check
                )
                return result
            else:
                result = subprocess.run(
                    cmd, 
                    env=cmd_env,
                    check=check
                )
                return result
        except subprocess.CalledProcessError as e:
            print_error(f"Command failed with exit code {e.returncode}")
            if capture_output:
                print_error(f"Error output: {e.stderr}")
            raise
        except Exception as e:
            print_error(f"Failed to run Docker Compose command: {str(e)}")
            raise

    def up(self, detached=True, services=None, build=False):
        """
        Start services defined in docker-compose.yml
        
        Args:
            detached: Run in detached mode
            services: List of specific services to start
            build: Whether to build images before starting
        """
        args = ["up"]
        if detached:
            args.append("-d")
        if build:
            args.append("--build")
            
        if services:
            args.extend(services)
            
        return self.run(*args)

    def down(self, volumes=False, remove_orphans=True):
        """
        Stop and remove services defined in docker-compose.yml
        
        Args:
            volumes: Whether to remove volumes
            remove_orphans: Whether to remove containers for services not defined in compose file
        """
        args = ["down"]
        if volumes:
            args.append("-v")
        if remove_orphans:
            args.append("--remove-orphans")
            
        return self.run(*args)

    def stop(self, services=None):
        """
        Stop services defined in docker-compose.yml
        
        Args:
            services: List of specific services to stop
        """
        args = ["stop"]
        if services:
            args.extend(services)
            
        return self.run(*args)

    def ps(self, services=None):
        """
        List containers for services defined in docker-compose.yml
        
        Args:
            services: List of specific services to show
            
        Returns:
            List of running services
        """
        args = ["ps"]
        if services:
            args.extend(services)
            
        result = self.run(*args, capture_output=True)
        return result.stdout

    def logs(self, services=None, follow=False, tail=None):
        """
        View logs for services defined in docker-compose.yml
        
        Args:
            services: List of specific services to show logs for
            follow: Whether to follow log output
            tail: Number of lines to show from end of logs
        """
        args = ["logs"]
        if follow:
            args.append("-f")
        if tail:
            args.extend(["--tail", str(tail)])
        if services:
            args.extend(services)
            
        return self.run(*args)

    def run_service(self, service, command, entrypoint=None, env_vars=None):
        """
        Run a command in a one-off service container
        
        Args:
            service: Service to run command in
            command: Command to run
            entrypoint: Override entrypoint
            env_vars: Additional environment variables
        """
        args = ["run", "--rm"]
        if entrypoint:
            args.extend(["--entrypoint", entrypoint])
        
        args.append(service)
        
        if isinstance(command, list):
            args.extend(command)
        else:
            args.append(command)
            
        return self.run(*args, env_vars=env_vars)

    def setup_compose(self, compose_file="docker-compose.setup.yml"):
        """
        Get a DockerCompose instance for setup operations
        
        Args:
            compose_file: Path to setup compose file relative to compose dir
            
        Returns:
            DockerCompose instance configured for setup
        """
        setup_file = self.compose_dir / compose_file
        return DockerCompose(compose_file=setup_file, env_file=self.env_file)