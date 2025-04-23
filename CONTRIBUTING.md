# Contributing to SparkBaaS

Thank you for considering contributing to the SparkBaaS project! This document outlines the process for contributing and helps ensure a smooth collaboration experience.

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md). Please read it before contributing.

## How Can I Contribute?

There are many ways you can contribute to SparkBaaS:

### Reporting Bugs

Before creating bug reports, please check the [issue tracker](https://github.com/your-username/sparkbaas-main/issues) to avoid duplicates. When you create a bug report, include as many details as possible:

- Use a clear and descriptive title.
- Describe the exact steps to reproduce the problem (including relevant configuration from your `.env` file, redacting secrets).
- Describe the behavior you observed and what you expected to see.
- Include screenshots or terminal output if applicable.
- Provide information about your OS, Docker version, and Python version.
- Use the bug report template if available.

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion:

- Use a clear and descriptive title.
- Provide a detailed description of the suggested enhancement and its relevance to the project goals ([PRD.md](docs/PRD.md)).
- Explain why this enhancement would be useful to users (especially in a DevOps context).
- Include any relevant examples or use cases.
- Use the feature request template if available.

### Pull Requests

We welcome contributions via Pull Requests (PRs).

- Ensure your PR addresses an existing issue or discusses a new feature/fix.
- Fill in the required PR template.
- Follow the Python and Docker coding standards outlined below and in `.github/copilot-instructions.md`.
- Include relevant test cases (`pytest`).
- Update documentation (README, docstrings, `docs/` folder) as needed.
- Ensure all files end with a newline.
- Ensure your code passes linting checks and tests.

## Development Workflow

### Setting Up the Development Environment

1.  **Fork the Repository:** Start by forking the main SparkBaaS repository on GitHub to your own account.
2.  **Clone Your Fork:** Clone your forked repository to your local machine:
    ```bash
    # Replace 'your-username' with your GitHub username
    git clone https://github.com/your-username/sparkbaas-main.git
    cd sparkbaas-main
    ```
3.  **Set Up Upstream Remote:** Add the original SparkBaaS repository as the `upstream` remote to keep your fork updated:
    ```bash
    # Replace 'original-owner' with the actual owner of the main repo if different
    git remote add upstream https://github.com/original-owner/sparkbaas-main.git
    ```
4.  **Install Dependencies:** Set up the Python environment for the CLI tool. Using a virtual environment is recommended:
    ```bash
    # Example using venv
    python -m venv .venv
    source .venv/bin/activate # On Windows use `.venv\Scripts\activate`
    # Install CLI dependencies (adjust path/tool if using Poetry/PDM)
    pip install -r src/sparkbaas-cli/requirements.txt # Or equivalent
    # You might also need Docker and Docker Compose installed system-wide
    ```
5.  **Initial Setup:** Run the initialization command to set up configuration (refer to `README.md` for details):
    ```bash
    # Example - adjust based on actual CLI usage
    python src/sparkbaas-cli/sparkbaas/cli.py init
    ```

### Development Process

1.  **Update Your Fork:** Before starting work, ensure your `main` branch is up-to-date with the `upstream` repository:
    ```bash
    git checkout main
    git fetch upstream
    git merge upstream/main
    git push origin main
    ```
2.  **Create a Branch:** Create a new branch for your feature or bug fix:
    ```bash
    # Use a descriptive branch name (e.g., feature/add-backup-compression, fix/cli-status-output)
    git checkout -b your-branch-name
    ```
3.  **Make Changes:** Implement your changes, adhering to the coding standards.
4.  **Test Locally:**
    *   Run linters (e.g., `flake8`, `black`, `isort`).
    *   Run unit tests:
        ```bash
        # Assuming pytest is configured
        pytest src/sparkbaas-cli/tests/
        ```
    *   Test the Docker Compose stack and CLI functionality locally:
        ```bash
        # Example - adjust based on actual CLI usage
        python src/sparkbaas-cli/sparkbaas/cli.py start
        # ... perform tests ...
        python src/sparkbaas-cli/sparkbaas/cli.py stop
        ```
5.  **Commit Changes:** Commit your changes with clear, descriptive commit messages. Reference relevant issue numbers (e.g., `Fixes #123`).
    ```bash
    git add .
    git commit -m "feat: Add compression option to backup command (Fixes #123)"
    ```
6.  **Push to Your Fork:** Push your branch to your GitHub fork:
    ```bash
    git push origin your-branch-name
    ```
7.  **Create a Pull Request:** Open a Pull Request (PR) from your branch on your fork to the `main` branch of the `upstream` SparkBaaS repository. Fill out the PR template thoroughly.

## Coding Standards

We follow strict Python and Docker best practices. Please refer to our [GitHub Copilot Instructions](.github/copilot-instructions.md) for detailed coding guidelines.

Key points:

-   **Python:** Adhere to PEP 8, use type hinting, write clear docstrings, implement robust error handling, and write testable code using `pytest`.
-   **Docker/Compose:** Create minimal and secure images, write clear `Dockerfile`s and `docker-compose.yml` files, use non-root users, define health checks.
-   Follow project structure conventions.
-   Ensure code is well-commented, especially complex logic.

## Testing

-   Write unit tests (`pytest`) for CLI logic, core functions, and utilities.
-   Write integration tests where appropriate to test interactions between components or CLI commands and Docker.
-   Run all tests before submitting a PR:
    ```bash
    # Adjust path if necessary
    pytest src/sparkbaas-cli/tests/
    ```

## Documentation

-   Update the `README.md` if you change core functionality or setup steps.
-   Add/update docstrings for all new/modified code.
-   Update any relevant documentation in the `docs/` folder (e.g., `ARCHITECTURE.md`, `PRD.md` if impacted).

## Review Process

Once you submit a PR:

1.  Maintainers will review your code for correctness, style, and adherence to project goals.
2.  Automated checks (linting, tests, etc., via GitHub Actions if configured) will run.
3.  You may need to make additional changes based on feedback. Engage in discussion via PR comments.
4.  Once approved and checks pass, a maintainer will merge your PR.

Thank you for contributing to SparkBaaS!