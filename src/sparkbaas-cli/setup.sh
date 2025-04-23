#!/bin/bash

# SparkBaaS CLI Setup Script
echo "Setting up SparkBaaS CLI..."

# Get the script's directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is not installed. Please install Python 3.8 or higher and try again."
    exit 1
fi

# Create a Python virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv .venv
fi

# Activate the virtual environment
echo "Activating virtual environment..."
source .venv/bin/activate

# Install required packages
echo "Installing required packages..."
pip install -r requirements.txt || pip install rich questionary python-dotenv pyyaml tabulate tqdm cryptography

# Install the package in development mode
echo "Installing SparkBaaS CLI in development mode..."
pip install -e .

# Make the CLI script executable
chmod +x spark

echo ""
echo "SparkBaaS CLI setup complete!"
echo ""
echo "You can now use the CLI by running:"
echo "  ./spark <command>"
echo ""
echo "For example:"
echo "  ./spark init"
echo "  ./spark start"
echo ""
echo "For help, run:"
echo "  ./spark --help"
echo ""