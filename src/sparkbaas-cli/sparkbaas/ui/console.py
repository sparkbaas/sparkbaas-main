from rich.console import Console
from rich.panel import Panel
from rich.style import Style
from rich.text import Text

try:
    import pyfiglet
    PYFIGLET_AVAILABLE = True
except ImportError:
    PYFIGLET_AVAILABLE = False

console = Console()

def print_banner():
    """Print the SparkBaaS ASCII art banner"""
    if PYFIGLET_AVAILABLE:
        # Use pyfiglet to generate ASCII art
        fig = pyfiglet.Figlet(font='slant')
        banner = fig.renderText('SparkBaaS')
    else:
        # Fallback to simple text if pyfiglet isn't available
        banner = "\n  SparkBaaS  \n"
    
    styled_banner = Text(banner)
    styled_banner.stylize("bold cyan")
    
    panel = Panel(
        styled_banner,
        title="[bold white]DevOps-friendly Backend as a Service[/bold white]",
        border_style="cyan"
    )
    
    console.print(panel)

def print_step(message):
    """Print a step in the process"""
    console.print(f"[bold blue]◉[/bold blue] [bold white]{message}[/bold white]")

def print_success(message):
    """Print a success message"""
    console.print(f"[bold green]✓[/bold green] {message}")

def print_warning(message):
    """Print a warning message"""
    console.print(f"[bold yellow]⚠[/bold yellow] {message}")

def print_error(message):
    """Print an error message"""
    console.print(f"[bold red]✗[/bold red] {message}")

def print_info(message):
    """Print an informational message"""
    console.print(f"[bold cyan]ℹ[/bold cyan] {message}")

def print_section(title):
    """Print a section header"""
    console.print(f"\n[bold cyan]━━━ {title} ━━━[/bold cyan]")

def confirm(message, default=True):
    """Ask for confirmation"""
    import questionary
    
    return questionary.confirm(
        message,
        default=default
    ).ask()

def select(message, choices, default=None):
    """Show a selection menu"""
    import questionary
    
    return questionary.select(
        message,
        choices=choices,
        default=default
    ).ask()