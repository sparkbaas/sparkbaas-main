# SparkBaaS Style Guide

This document outlines the coding standards and style guidelines for contributing to the SparkBaaS project. Adhering to these guidelines ensures consistency, readability, and maintainability across the codebase.

## General Principles

- Write clean, readable, and maintainable code.
- Optimize for clarity and long-term maintainability over cleverness or brevity.
- Be consistent with existing code patterns and architectural choices.
- Follow Python and Docker best practices rigorously.
- Prioritize security in all aspects of development.
- Ensure all contributions align with the project goals outlined in the [PRD](docs/PRD.md).

## Python Guidelines

### Code Style

- **PEP 8:** Strictly adhere to the [PEP 8](https://www.python.org/dev/peps/pep-0008/) style guide.
- **Formatting:** Use [`black`](https://marketplace.visualstudio.com/items?itemName=ms-python.black-formatter) for automated code formatting (VS Code Extension).
- **Imports:** Use [`isort`](https://marketplace.visualstudio.com/items?itemName=ms-python.isort) to sort imports automatically (VS Code Extension). Imports should be grouped as standard library, third-party, and first-party (application-specific).
- **Linting:** Code should pass `flake8` checks without errors or warnings (Integrated into the main [Python extension for VS Code](https://marketplace.visualstudio.com/items?itemName=ms-python.python)).
- **Line Length:** Keep lines under a reasonable length (e.g., 88 characters as per `black` default). Consider setting [vertical rulers](https://code.visualstudio.com/docs/editor/codebasics#_vertical-rulers) in VS Code (e.g., at 88 and 120) via the `editor.rulers` setting for guidance, but strict adherence beyond `black`'s formatting isn't mandatory if readability improves slightly. Or, click to open: <a href="vscode://settings/editor.rulers">VS Code Settings</a>

### Typing

- **Type Hinting:** Use Python's type hinting (`typing` module) extensively. Strive for full type coverage.
- **Specificity:** Avoid using `typing.Any`. Use the most specific type possible. Use `typing.TypeAlias` for complex type definitions.
- **Docstrings vs. Types:** Type hints are mandatory. Docstrings should explain *what* the code does and *why*, not just repeat type information.

```python
# Good
from typing import List, Dict, Optional, TypeAlias

ConfigDict: TypeAlias = Dict[str, str | int | bool]

def process_data(
    records: List[Dict[str, str]], 
    config: Optional[ConfigDict] = None
) -> int:
    """Processes a list of records based on the provided configuration.

    Args:
        records: A list of dictionaries representing data records.
        config: An optional configuration dictionary.

    Returns:
        The number of records successfully processed.
    """
    # ... implementation ...
    processed_count = 0
    # ...
    return processed_count

# Avoid
def process_data(records, config = None): # Missing type hints
    # ...
    pass

# Avoid
def process_data(records: list, config: dict | None) -> any: # Less specific types, 'any' return
    # ...
    pass
```

### Naming Conventions

- **Variables, Functions, Methods:** `snake_case`
- **Classes:** `PascalCase`
- **Constants:** `UPPER_SNAKE_CASE`
- **Modules/Packages:** `snake_case` (short, lowercase names)
- **Clarity:** Use descriptive names that clearly communicate purpose. Avoid single-letter variable names except in very short, obvious contexts (like loop counters `i`, `j` or coordinates `x`, `y`).

### Docstrings

- Write comprehensive docstrings for all modules, classes, functions, and methods.
- Follow a standard format like [Google Style](https://google.github.io/styleguide/pyguide.html#38-comments-and-docstrings) or [NumPy Style](https://numpydoc.readthedocs.io/en/latest/format.html). Be consistent.
- Explain the purpose, arguments, return values, and any exceptions raised.

### Error Handling

- Use specific, built-in or custom exception types. Avoid catching generic `Exception`.
- Handle potential errors gracefully and provide informative error messages.
- Log errors effectively using the `logging` module.

### Structure and Design

- Follow principles of **Single Responsibility** and **Separation of Concerns**.
- Use modules and classes logically to structure code.
- Prefer functions for simple, stateless operations.
- Write **testable code**. Use dependency injection where appropriate to facilitate mocking and testing.

## Docker & Docker Compose Guidelines

### Dockerfiles

- **Minimal Images:** Use official, minimal base images (e.g., `python:3.X-slim-bookworm`).
- **Multi-Stage Builds:** Employ multi-stage builds to reduce final image size, separating build dependencies from runtime dependencies.
- **Non-Root User:** Create and run containers as a dedicated non-root user.
- **Minimize Layers:** Combine related commands (e.g., `apt-get update && apt-get install && rm -rf /var/lib/apt/lists/*`) to reduce image layers.
- **`.dockerignore`:** Use a comprehensive `.dockerignore` file to exclude unnecessary files from the build context.
- **Clarity:** Write clear, maintainable `Dockerfile`s with comments explaining non-obvious steps or choices.
- **Security:** Avoid storing secrets directly in the image. Scan images for vulnerabilities.

### Docker Compose (`docker-compose.yml`)

- **Clarity:** Structure the file logically, grouping related services or using comments.
- **Environment Variables:** Use `.env` files for configuration. Provide a `.env.template` file.
- **Secrets:** Use Docker secrets for sensitive information where appropriate, especially in production scenarios (though `.env` is acceptable for this project's scope).
- **Volumes:** Use named volumes for persistent data. Avoid bind mounts for application code within the container where possible (prefer `COPY` in Dockerfile).
- **Networks:** Define explicit networks for inter-service communication.
- **Health Checks:** Define meaningful `healthcheck` directives for services to ensure proper startup order and monitoring.
- **Resource Limits:** Consider defining resource limits (CPU, memory) for services, especially for production deployments.
- **Restart Policies:** Use appropriate `restart` policies (e.g., `unless-stopped`).

## Testing (`pytest`)

- Write tests for all new functionality (unit and integration tests).
- Follow the Arrange-Act-Assert pattern.
- Test behaviors and edge cases, not just implementation details.
- Mock external dependencies and services appropriately (e.g., using `unittest.mock`).
- Ensure tests are independent and can run in any order.
- Aim for high test coverage.

```python
# Good test example (using pytest)
import pytest
from sparkbaas.core import utils # Example path

def test_sanitize_input_removes_script_tags():
    # Arrange
    dirty_input = "<script>alert('xss')</script>Hello"
    expected_output = "Hello"
    
    # Act
    sanitized_output = utils.sanitize_input(dirty_input)
    
    # Assert
    assert sanitized_output == expected_output

def test_calculate_average_empty_list_raises_error():
    # Arrange
    data = []
    
    # Act / Assert
    with pytest.raises(ValueError):
        utils.calculate_average(data)
```

## Documentation

- Document public APIs, core classes, complex functions, and CLI commands thoroughly using docstrings.
- Provide usage examples where helpful.
- Keep comments concise and focused on *why* something is done, not *what* it does (the code should explain the *what*).
- Keep all documentation (README, `docs/` folder, docstrings, comments) up-to-date with code changes.

## Git and Commit Style

- Use descriptive commit messages written in the **imperative mood** (e.g., "Add feature" not "Added feature" or "Adds feature").
- Begin commit message subject lines with a type prefix (following [Conventional Commits](https://www.conventionalcommits.org/) is recommended):
    - `feat:` (new feature)
    - `fix:` (bug fix)
    - `docs:` (documentation changes)
    - `style:` (code style changes, formatting)
    - `refactor:` (code changes that neither fix a bug nor add a feature)
    - `perf:` (performance improvements)
    - `test:` (adding or correcting tests)
    - `build:` (changes affecting build system or dependencies)
    - `ci:` (changes to CI configuration)
    - `chore:` (routine tasks, maintenance)
- Keep commits focused on a single logical change. Avoid mixing unrelated changes in one commit.
- Reference relevant issue numbers in the commit message body or footer (e.g., `Fixes #123`, `Refs #456`).

Examples:
```
feat: Add --json output flag to 'spark status' command
fix: Correct handling of missing .env file during init
docs: Update ARCHITECTURE.md with MinIO component
refactor: Improve DockerCompose wrapper error handling
test: Add unit tests for config validation logic
ci: Configure GitHub Actions to run pytest on push
```

By following these guidelines, we maintain a consistent, secure, and high-quality codebase that's easier for everyone to contribute to and maintain, aligning with our goal of providing a DevOps-friendly BaaS platform.