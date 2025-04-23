# SparkBaaS - Product Requirements Document (PRD)

## 1. Overview

SparkBaaS aims to be an open-source, **DevOps-first**, self-hostable Backend-as-a-Service (BaaS) platform. It achieves this by integrating battle-tested open-source components (like PostgreSQL, Keycloak, Kong, MinIO) orchestrated via Docker Compose and managed through a dedicated, **non-interactive** Python Command-Line Interface (CLI) tool (`sparkbaas-cli`). The CLI operates strictly based on command-line arguments, environment variables, and configuration files, ensuring suitability for automation and scripting.

This repository focuses *exclusively* on the Docker Compose setup and the `sparkbaas-cli` tool. A separate management Web UI is outside the scope of this repository.

The core philosophy is to provide a **secure-by-default**, simple, maintainable, and extensible BaaS foundation that users can confidently self-host and manage via the CLI in a **DevOps-friendly** manner.

**Scope Note:** A single deployed instance of SparkBaaS represents **one distinct environment** (e.g., development, staging, or production for a single project). Managing multiple projects or environments requires deploying separate SparkBaaS instances.

## 2. Goals

*   Provide a stable, reliable, and **secure-by-default** Docker Compose configuration for the core BaaS services.
*   Offer a comprehensive, user-friendly, and **scriptable (non-interactive)** Python CLI (`sparkbaas-cli`) for managing the entire lifecycle of the SparkBaaS instance, including **JSON output** for all commands.
*   Ensure the platform leverages strong security practices, including mTLS and API keys between core components where applicable.
*   Facilitate easy configuration and deployment using standard `.env` files and Docker Compose, suitable for CI/CD pipelines.
*   Establish a solid foundation for potential future extensions while keeping the core CLI/Compose system robust.
*   Prioritize clear documentation for setup, configuration, CLI usage, security architecture, and **CLI JSON output schemas**.

## 3. Core Components (Managed via Docker Compose)

The following core services will be defined and managed within the `src/compose/docker-compose.yml` file and orchestrated by the CLI:

*   **Database Layer**:
    *   **PostgreSQL (16+)**: Primary data store.
        *   Configuration to support Row Level Security (RLS).
        *   Integration with **PostgREST** for a RESTful API.
        *   Managed migrations via CLI (`spark migrate apply`). *Note: Migration file creation workflow (e.g., using Alembic, dbmate) is external but should be documented.*
        *   Backup/Restore functionality via CLI.
*   **Identity & Access Management (IAM)**:
    *   **Keycloak**: Handles authentication (OAuth2/OIDC), authorization (RBAC), user management.
        *   Configuration managed via `src/compose/keycloak/` (declarative realm setup preferred).
*   **API Gateway / Reverse Proxy**:
    *   **Kong**: Manages ingress, routing, API key authentication, rate limiting, and acts as the central secure entry point.
        *   Handles external TLS termination.
        *   Configured to use **mTLS** for communication with backend services (Keycloak API, PostgREST, Serverless Runtime, Storage API, Realtime Service) where possible.
        *   Configured to use **API Keys** for service-to-service authentication where applicable.
        *   Configuration primarily managed declaratively (via files mounted into the container or Docker labels) to align with GitOps/DevOps practices. CLI commands may supplement for dynamic elements (e.g., consumer creation) if necessary.
*   **Serverless Runtime**:
    *   Integration of a serverless function runtime supporting **Node.js and/or Deno**.
    *   Management (deploy, list, delete, logs) via `spark function` CLI commands.
    *   Securely exposed via Kong.
*   **Object Storage Layer (Optional)**:
    *   **MinIO**: S3-compatible object storage.
    *   Securely exposed via Kong.
    *   Management (e.g., bucket policies, user creation - TBD) potentially via CLI or relies on MinIO's own tools/UI initially.
*   **Realtime Layer (Optional)**:
    *   **[Placeholder Component - e.g., Supabase Realtime, Centrifugo]**: Handles realtime data synchronization via WebSockets.
    *   Securely exposed via Kong.
    *   Configuration managed via CLI/`.env`.
*   **Email Relay Configuration**:
    *   No email server included. Configuration hooks (`.env` variables) provided for connecting to an **external SMTP relay service**. CLI validates these settings.
*   **[Optional] Logging/Monitoring Hooks**:
    *   Configuration to facilitate integration with external logging stacks (e.g., ELK/Graylog).

## 4. Management Interface (`sparkbaas-cli`)

The Python CLI is the primary tool for interacting with and managing the SparkBaaS instance. It operates **non-interactively**, relying solely on arguments, environment variables, and config files.

*   **Universal Requirement**: All CLI commands **MUST** support a `--json` flag to output results in a predictable JSON format suitable for scripting. JSON schemas for the output of each command should be documented.
*   **Initialization (`spark init`)**: Set up the initial configuration (`.env` file, necessary directories), generate required secrets/certificates (e.g., for mTLS), and potentially perform basic service bootstrapping (e.g., initial Keycloak realm setup, default DB schema) if needed beyond declarative configuration.
*   **Lifecycle Management**:
    *   `spark start`: Start all defined services.
    *   `spark stop`: Stop all defined services.
    *   `spark restart`: Restart services.
    *   `spark status`: Show the status of running services.
    *   `spark logs [service]`: View logs for specific or all services.
*   **Configuration Management**:
    *   Validate `.env` configuration values (including SMTP relay settings).
    *   Commands to assist with declarative configuration management (e.g., validating Kong config files) rather than direct imperative changes where possible.
*   **Database Management**:
    *   `spark migrate apply`: Apply database schema migrations.
    *   `spark backup`: Perform a database backup.
    *   `spark restore`: Restore the database from a backup.
*   **Function Management**:
    *   `spark function deploy`: Deploy serverless functions (Node/Deno).
    *   `spark function list`: List deployed functions.
    *   `spark function delete`: Remove functions.
    *   `spark function logs`: View function logs.
*   **[Optional] Storage Management**:
    *   `spark storage ...`: Commands for basic management tasks related to MinIO (TBD - initial focus might be just enabling/disabling).
*   **[Optional] Realtime Management**:
    *   `spark realtime ...`: Commands for managing the realtime component (TBD).
*   **Security**:
    *   `spark security scan`: Trigger automated security scans.
    *   Commands for managing certificates/keys if needed.
*   **Maintenance**:
    *   `spark upgrade`: Facilitate upgrading SparkBaaS components.
    *   `spark reset`: Reset the environment (use with caution).

## 5. Security Requirements (Platform & CLI)

*   **Secure Defaults**: Services configured securely out-of-the-box.
*   **TLS**: Kong handles external TLS termination.
*   **mTLS**: Kong uses mTLS to communicate with internal backend services (PostgREST, Keycloak API, Serverless Runtime, MinIO API, Realtime). Certificates managed appropriately.
*   **API Keys**: Kong uses API Keys for service access where appropriate.
*   **Secrets Management**: Primarily via `.env` file. CLI avoids exposing secrets. Certificates stored securely.
*   **CLI Security**: Handle paths/inputs securely; avoid command injection.
*   **Automated Scanning**: Integrate security scanning via CLI.
*   **Principle of Least Privilege**: Containers run as non-root users; services have minimal necessary permissions.

## 6. Deployment & Configuration

*   **Model**: One deployed SparkBaaS instance = one environment.
*   **Docker Compose**: Primary definition and orchestration (`src/compose/docker-compose.yml`).
*   **Environment Variables**: All configuration managed via `.env` file, generated from `.env.template` during `spark init`.
*   **Volumes**: Persistent data managed using named Docker volumes.
*   **Service Configuration**: Favor declarative configuration (files managed in Git, mounted into containers) over imperative CLI commands for service setup (e.g., Kong routes, Keycloak realms).

## 7. Roadmap (CLI & Compose Focus)

### Phase 1: Stabilization & Core CLI Enhancement
1.  **Refine `spark init`**: Robust generation of `.env`, initial configs, mTLS certificates, strong secrets, basic bootstrapping. Implement validation.
2.  **Kong Integration**: Ensure Kong is correctly configured (declaratively where possible) for routing, external TLS, mTLS backends, and basic API key setup.
3.  **Implement `--json` Output**: Add JSON output flag and implementation for core lifecycle/status commands.
4.  **Improve Configuration Validation**: Comprehensive checks for `.env` values (including SMTP).
5.  **Enhance Backup/Restore**: Make backup/restore robust and configurable.
6.  **Strengthen Testing**: Unit tests for CLI; integration tests for CLI commands (including Kong interactions, JSON output).
7.  **Improve Logging**: Standardize CLI logging; easy service log access.
8.  **Documentation**: Comprehensive docs for setup, config, CLI, security architecture, **JSON output schemas**, **migration creation workflow**.

### Phase 2: Feature Expansion & Polish
1.  **Serverless Runtime Integration**: Fully implement `spark function` commands (including JSON output).
2.  **Object Storage (MinIO) Integration**: Add MinIO service definition, basic CLI commands (`spark storage enable/disable`, config validation), Kong integration (mTLS).
3.  **Realtime Integration**: Select and integrate a realtime component, add basic CLI commands, Kong integration (mTLS).
4.  **Complete `--json` Output**: Ensure *all* CLI commands support JSON output.
5.  **Refine Security Scanning**: Improve `spark security scan`.
6.  **Develop `spark upgrade`**: Reliable mechanism to upgrade core service versions.
7.  **Enhance `spark migrate apply`**: More control over DB migrations application.
8.  **Observability Hooks**: Add config/CLI commands for exporting logs/metrics.
9.  **Advanced Kong Configuration**: CLI commands or declarative config options for managing consumers, plugins, etc. (favoring declarative).

### Phase 3: Long-Term Refinement
1.  **Advanced Configuration**: Explore options beyond `.env` if needed.
2.  **Performance Tuning**: CLI guidance/tools for tuning (PostgreSQL, Kong, MinIO).
3.  **Extensibility**: Refactor CLI for easier addition of commands/services.
4.  **Refine Storage/Realtime CLI**: Add more granular management commands if necessary.

## 8. Success Metrics (CLI & Compose)

*   Ease and time required for initial setup (`spark init` to secure, running stack).
*   Reliability of core CLI commands (start, stop, backup, restore, migrate, function deploy) **including JSON output**.
*   Clarity and completeness of documentation, especially security setup, **JSON schemas**, and **declarative configuration patterns**.
*   Demonstrable secure-by-default posture (passing basic security scans).
*   Community feedback on CLI usability and suitability for automation.