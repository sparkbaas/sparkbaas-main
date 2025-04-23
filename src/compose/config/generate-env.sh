#!/bin/bash

# SparkBaaS Environment Generator
# Generates a secure .env file with randomly generated passwords and secrets

set -e

# Output file
ENV_FILE="../.env"
BACKUP_FILE="../.env.backup"

# Check if .env already exists and create backup
if [ -f "$ENV_FILE" ]; then
  echo "Found existing .env file. Creating backup to .env.backup"
  cp "$ENV_FILE" "$BACKUP_FILE"
fi

# Function to generate a random string
generate_random() {
  length=${1:-32}
  LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

# Function to get or set an environment variable
get_or_set() {
  local key=$1
  local default=$2
  local secret=$3
  local value
  
  # If the .env file exists, try to get the value from it
  if [ -f "$ENV_FILE" ]; then
    value=$(grep "^$key=" "$ENV_FILE" | cut -d '=' -f2-)
  fi
  
  # If the value is empty or we need a new secret, generate one
  if [ -z "$value" ] || [ "$secret" = true ]; then
    if [ "$secret" = true ]; then
      value=$(generate_random 32)
    else
      value="$default"
    fi
  fi
  
  echo "$key=$value"
}

# Create or update the .env file
cat > "$ENV_FILE" << EOF
# SparkBaaS Environment Configuration
# Generated on $(date)
# ---------------------------------

# =============================================================================
# GENERAL SETTINGS
# =============================================================================
# Domain name for services - set this to your domain if you have one
$(get_or_set "HOST_DOMAIN" "localhost")

# Log level - one of: debug, info, warn, error
$(get_or_set "LOG_LEVEL" "info")

# =============================================================================
# DATABASE SETTINGS
# =============================================================================
# PostgreSQL settings
$(get_or_set "POSTGRES_USER" "postgres")
$(get_or_set "POSTGRES_PASSWORD" "" true)
$(get_or_set "POSTGRES_DB" "postgres")
$(get_or_set "POSTGRES_PORT" "5432")

# Database users
$(get_or_set "KEYCLOAK_DB_USER" "keycloak")
$(get_or_set "KEYCLOAK_DB_PASSWORD" "" true)
$(get_or_set "KEYCLOAK_DB_DATABASE" "keycloak")

$(get_or_set "KONG_PG_USER" "kong")
$(get_or_set "KONG_PG_PASSWORD" "" true)
$(get_or_set "KONG_PG_DATABASE" "kong")
$(get_or_set "KONG_PG_HOST" "postgres")
$(get_or_set "KONG_DATABASE" "postgres")

$(get_or_set "AUTHENTICATOR_PASSWORD" "" true)

# =============================================================================
# AUTHENTICATION SETTINGS
# =============================================================================
# Keycloak settings
$(get_or_set "KEYCLOAK_ADMIN" "admin")
$(get_or_set "KEYCLOAK_ADMIN_PASSWORD" "" true)
$(get_or_set "KEYCLOAK_DB_ADDR" "postgres")
$(get_or_set "KEYCLOAK_DB_VENDOR" "postgres")

# JWT settings
$(get_or_set "POSTGREST_JWT_SECRET" "" true)
$(get_or_set "PGRST_JWT_SECRET_IS_BASE64" "false")
$(get_or_set "POSTGREST_DB_URI" "postgres://authenticator:\${AUTHENTICATOR_PASSWORD}@postgres:5432/postgres")
$(get_or_set "POSTGREST_DB_SCHEMA" "public,api")
$(get_or_set "POSTGREST_DB_ANON_ROLE" "anon")

# =============================================================================
# TRAEFIK SETTINGS
# =============================================================================
$(get_or_set "TRAEFIK_DASHBOARD_PORT" "8080") 
$(get_or_set "TRAEFIK_INSECURE_API" "false")
$(get_or_set "TRAEFIK_ADMIN_AUTH" "admin:\$apr1\$tZ8so14Y\$0kzh5YwGCdTUzWJHTRdXm1")
$(get_or_set "ACME_EMAIL" "admin@example.com")

# =============================================================================
# FUNCTION SERVER SETTINGS
# =============================================================================
$(get_or_set "FUNCTIONS_PORT" "8888")
$(get_or_set "FUNCTIONS_AUTH_ENABLED" "true")

# =============================================================================
# ADMIN SETTINGS
# =============================================================================
$(get_or_set "ADMIN_USER" "admin")
$(get_or_set "ADMIN_PASSWORD_HASH" "\$apr1\$tZ8so14Y\$0kzh5YwGCdTUzWJHTRdXm1")
$(get_or_set "KONG_ADMIN_AUTH" "admin:\$apr1\$tZ8so14Y\$0kzh5YwGCdTUzWJHTRdXm1")
EOF

echo "Environment configuration generated successfully at $ENV_FILE"
echo "Review and modify as needed before starting services."