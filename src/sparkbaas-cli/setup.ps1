# SparkBaaS CLI Setup Script for Windows
Write-Host "Setting up SparkBaaS CLI..."

# Get the script's directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Check if Python is installed
try {
    $pythonVersion = python --version
    if (-not ($pythonVersion -match "Python 3")) {
        Write-Host "Python 3 is not installed or not in PATH. Please install Python 3.8 or higher and try again."
        exit 1
    }
} catch {
    Write-Host "Python 3 is not installed or not in PATH. Please install Python 3.8 or higher and try again."
    exit 1
}

# Create a Python virtual environment if it doesn't exist
if (-not (Test-Path ".venv")) {
    Write-Host "Creating Python virtual environment..."
    python -m venv .venv
}

# Activate the virtual environment
Write-Host "Activating virtual environment..."
& ".\.venv\Scripts\Activate.ps1"

# Install required packages
Write-Host "Installing required packages..."
try {
    pip install -r requirements.txt
} catch {
    Write-Host "Trying alternative package installation method..."
    pip install rich questionary python-dotenv pyyaml tabulate tqdm cryptography
}

# Install the package in development mode
Write-Host "Installing SparkBaaS CLI in development mode..."
pip install -e .

Write-Host ""
Write-Host "SparkBaaS CLI setup complete!"
Write-Host ""
Write-Host "You can now use the CLI by running:"
Write-Host "  .\spark.ps1 <command>"
Write-Host ""
Write-Host "For example:"
Write-Host "  .\spark.ps1 init"
Write-Host "  .\spark.ps1 start"
Write-Host ""
Write-Host "For help, run:"
Write-Host "  .\spark.ps1 --help"
Write-Host ""