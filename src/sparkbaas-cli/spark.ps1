# PowerShell script to run SparkBaaS CLI

# Get the script's directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Activate virtual environment and run the CLI
& "$ScriptDir\.venv\Scripts\Activate.ps1"
python -m sparkbaas.cli $args