# SparkBaaS: DevOps-Friendly Backend as a Service

SparkBaaS is a turnkey, self-hosted Backend as a Service (BaaS) platform that combines battle-tested open-source components into a cohesive, easy-to-deploy package. Inspired by Supabase, but designed with DevOps-first principles, SparkBaaS provides you with database, authentication, API gateway, and serverless functions in one simple deployment.

![SparkBaaS Logo](https://via.placeholder.com/800x200?text=SparkBaaS)

## Features

- **PostgreSQL Database** with REST API (via PostgREST)
- **Authentication & Authorization** (via Keycloak)
- **API Gateway** for routing and security (via Kong/Traefik)
- **Serverless Function** runtime (Node.js)
- **Web Admin Interface** for managing your services
- **CLI Tool** for easy management

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Python 3.8+ (for CLI)

### Getting Started

#### 1. Clone the Repository

```bash
git clone https://github.com/sparkbaas/sparkbaas.git
cd sparkbaas
```

#### 2. Install the CLI

```bash
# From the repository root
cd src/sparkbaas-cli

# Install the CLI in development mode
pip install -e .

# Verify installation
spark --version
```

#### 3. Initialize SparkBaaS

```bash
# Navigate to your project directory
cd /path/to/your/project

# Initialize SparkBaaS
spark init
```

This will:
- Create necessary directory structure
- Generate secure passwords and configuration
- Set up database schemas and users
- Configure services

#### 4. Start the Services

```bash
spark start
```

#### 5. Access Your Services

- **Admin Interface**: http://localhost:8080 or https://admin.localhost
- **API Gateway**: https://api.localhost
- **Auth Service**: https://auth.localhost
- **Database REST API**: https://db.localhost
- **Functions**: https://functions.localhost

## CLI Commands

SparkBaaS comes with a user-friendly command-line interface:

```
spark init       # Initialize SparkBaaS platform
spark start      # Start all services
spark stop       # Stop all services
spark status     # Show status of all services
spark backup     # Backup databases and configurations
spark restore    # Restore from backup
spark migrate    # Run database migrations
spark upgrade    # Upgrade platform components
spark function   # Manage serverless functions
```

### Function Management

```bash
# Deploy a function
spark function deploy ./my-function

# List deployed functions
spark function list

# View function logs
spark function logs my-function
```

## Configuration

SparkBaaS uses environment variables for configuration. During initialization, a `.env` file is created with secure defaults. You can modify this file to customize your deployment.

Key configuration options:

- `HOST_DOMAIN`: Domain name for your services (default: localhost)
- `POSTGRES_USER/PASSWORD`: Database credentials
- `KEYCLOAK_ADMIN/ADMIN_PASSWORD`: Auth admin credentials
- `JWT_SECRET`: Secret for JWT tokens
- `TRAEFIK_DASHBOARD_PORT`: Port for the Traefik dashboard

## Security

SparkBaaS is designed with security best practices:

- TLS encryption for all services
- Secure secrets management
- Role-based access control
- Network isolation between services
- Regular security updates

## Backup and Recovery

Backup your entire platform:

```bash
spark backup
```

Restore from a previous backup:

```bash
spark restore --file backup-20250422.tar.gz
```

## Upgrading

Update to the latest version:

```bash
spark upgrade
```

Update specific components:

```bash
spark upgrade --component database
```

## Docker Compose Direct Usage

If you prefer to use Docker Compose directly:

```bash
# Navigate to the compose directory
cd src/compose

# Initialize
./setup.sh

# Start services
docker-compose up -d

# Stop services
docker-compose down
```

## Production Deployment

For production deployments, we recommend:

1. Using a registered domain with proper DNS records
2. Setting up HTTPS with a valid certificate
3. Configuring proper storage volumes for persistence
4. Implementing regular automated backups
5. Setting up monitoring and alerting

## Troubleshooting

Common issues and solutions:

- **Services won't start**: Check Docker logs with `spark logs`
- **Can't access services**: Ensure ports are not in use and your firewall allows connections
- **Database connection issues**: Verify PostgreSQL is running with `spark status`
- **Authentication problems**: Check Keycloak logs with `spark logs auth`

## Community and Support

- **GitHub Issues**: [Report bugs or request features](https://github.com/example/sparkbaas/issues)
- **Documentation**: [Full documentation](https://docs.sparkbaas.com)
- **Discord**: [Join our community](https://discord.gg/sparkbaas)

## License

SparkBaaS is licensed under the MIT license.