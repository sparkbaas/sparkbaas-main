#!/bin/bash
set -e

# Script to run database migrations in order

echo "Running database migrations..."

# Migration directory
MIGRATIONS_DIR="/docker-entrypoint-initdb.d/migrations"

# Connection parameters (use default postgres user for migrations)
export PGUSER="${POSTGRES_USER:-postgres}"
export PGPASSWORD="${POSTGRES_PASSWORD:-changeme}"
export PGDATABASE="${POSTGRES_DB:-postgres}"
export PGHOST="localhost"

# Find all SQL files and sort them numerically
echo "Looking for migration files in $MIGRATIONS_DIR"
MIGRATION_FILES=$(find "$MIGRATIONS_DIR" -name "*.sql" | sort)

if [ -z "$MIGRATION_FILES" ]; then
  echo "No migration files found in $MIGRATIONS_DIR"
  exit 0
fi

# Create migrations tracking table if it doesn't exist
echo "Setting up migrations tracking table..."
psql -v ON_ERROR_STOP=1 <<-EOSQL
  CREATE TABLE IF NOT EXISTS _migrations (
    id SERIAL PRIMARY KEY,
    filename TEXT NOT NULL UNIQUE,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
  );
EOSQL

# Apply migrations that haven't been applied yet
for migration_file in $MIGRATION_FILES; do
  filename=$(basename "$migration_file")
  
  # Check if migration has already been applied
  if psql -t -c "SELECT 1 FROM _migrations WHERE filename = '$filename'" | grep -q 1; then
    echo "Migration $filename has already been applied. Skipping."
    continue
  fi
  
  echo "Applying migration: $filename"
  
  # Run the migration file
  psql -v ON_ERROR_STOP=1 -f "$migration_file"
  
  # Record that the migration has been applied
  psql -v ON_ERROR_STOP=1 -c "INSERT INTO _migrations (filename) VALUES ('$filename')"
  
  echo "Successfully applied $filename"
done

echo "All migrations completed successfully!"