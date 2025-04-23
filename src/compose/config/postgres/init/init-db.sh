#!/bin/bash
set -e

# Log output with timestamp
log() {
  echo "[$(date -Iseconds)] $1"
}

log "Starting database initialization..."

# Directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INITIALIZED_DIR="$SCRIPT_DIR/initialized"

# Create initialized directory if it doesn't exist
mkdir -p "$INITIALIZED_DIR"

# Process template file if it exists
if [ -f "$SCRIPT_DIR/01-init-template.sql" ]; then
    log "Processing initialization template..."
    envsubst < "$SCRIPT_DIR/01-init-template.sql" > "$INITIALIZED_DIR/01-init.sql"
    log "Created 01-init.sql"
else
    log "Warning: No initialization template found at $SCRIPT_DIR/01-init-template.sql"
fi

# Process 02-postgrest-setup.sql if it exists
if [ -f "$SCRIPT_DIR/02-postgrest-setup.sql" ]; then
    log "Processing 02-postgrest-setup.sql..."
    cp "$SCRIPT_DIR/02-postgrest-setup.sql" "$INITIALIZED_DIR/"
    log "Copied 02-postgrest-setup.sql"
else
    log "Warning: 02-postgrest-setup.sql not found!"
fi

# Wait for PostgreSQL to be ready
until PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres -U $POSTGRES_USER -c '\q' 2>/dev/null; do
    log "PostgreSQL is unavailable - sleeping"
    sleep 1
done
log "PostgreSQL is up - executing initialization"

# Execute the processed SQL files
log "Running initialization SQL scripts..."
for f in "$INITIALIZED_DIR"/*.sql; do
    if [ -f "$f" ]; then
        log "Executing $(basename $f)..."
        PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres -U $POSTGRES_USER -f "$f" || log "Warning: Error executing $f"
        log "Completed $(basename $f)"
    fi
done

# Create authenticator role if it doesn't exist
log "Creating authenticator role..."
PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres -U $POSTGRES_USER <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticator') THEN
            CREATE ROLE authenticator WITH LOGIN PASSWORD '${AUTHENTICATOR_PASSWORD:-changeme}';
            RAISE NOTICE 'Created authenticator role';
        ELSE
            ALTER ROLE authenticator WITH PASSWORD '${AUTHENTICATOR_PASSWORD:-changeme}';
            RAISE NOTICE 'Updated authenticator role password';
        END IF;
        
        -- Set search path to include all schemas
        ALTER ROLE authenticator SET search_path TO public, api, auth, storage, functions;
    END
    \$\$;
EOSQL

# Create Keycloak database and user if they don't exist
if [ -n "$KEYCLOAK_DB_USER" ] && [ -n "$KEYCLOAK_DB_DATABASE" ]; then
    log "Creating Keycloak database and user..."
    PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres -U $POSTGRES_USER <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$KEYCLOAK_DB_USER') THEN
                CREATE ROLE "$KEYCLOAK_DB_USER" WITH LOGIN PASSWORD '${KEYCLOAK_DB_PASSWORD:-changeme}';
                RAISE NOTICE 'Created Keycloak user role';
            ELSE
                ALTER ROLE "$KEYCLOAK_DB_USER" WITH PASSWORD '${KEYCLOAK_DB_PASSWORD:-changeme}';
                RAISE NOTICE 'Updated Keycloak user role password';
            END IF;
        END
        \$\$;

        SELECT 'CREATE DATABASE "$KEYCLOAK_DB_DATABASE"'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$KEYCLOAK_DB_DATABASE')\gexec

        GRANT ALL PRIVILEGES ON DATABASE "$KEYCLOAK_DB_DATABASE" TO "$KEYCLOAK_DB_USER";
EOSQL
    log "Keycloak database setup complete."
fi

# Create Kong database and user if they don't exist
if [ -n "$KONG_PG_USER" ] && [ -n "$KONG_PG_DATABASE" ]; then
    log "Creating Kong database and user..."
    PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres -U $POSTGRES_USER <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$KONG_PG_USER') THEN
                CREATE ROLE "$KONG_PG_USER" WITH LOGIN PASSWORD '${KONG_PG_PASSWORD:-changeme}';
                RAISE NOTICE 'Created Kong user role';
            ELSE
                ALTER ROLE "$KONG_PG_USER" WITH PASSWORD '${KONG_PG_PASSWORD:-changeme}';
                RAISE NOTICE 'Updated Kong user role password';
            END IF;
        END
        \$\$;

        SELECT 'CREATE DATABASE "$KONG_PG_DATABASE"'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$KONG_PG_DATABASE')\gexec

        GRANT ALL PRIVILEGES ON DATABASE "$KONG_PG_DATABASE" TO "$KONG_PG_USER";
EOSQL
    log "Kong database setup complete."
fi

log "Database initialization complete."