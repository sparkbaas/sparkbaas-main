#!/bin/sh
# SparkBaaS Automated Backup Script
# This script performs a backup of the PostgreSQL database and configuration files

set -e

# Set variables
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/backups"
BACKUP_FILE="${BACKUP_DIR}/sparkbaas_backup_${TIMESTAMP}.tar.gz"
LATEST_LINK="${BACKUP_DIR}/sparkbaas_backup_latest.tar.gz"
RETENTION_DAYS=${RETENTION_DAYS:-7}

# Log message with timestamp
log() {
  echo "[$(date -Iseconds)] $1"
}

log "Starting SparkBaaS backup..."

# Ensure backup directory exists
mkdir -p ${BACKUP_DIR}

# Create temp directory for backup
TEMP_DIR=$(mktemp -d)
log "Using temporary directory: ${TEMP_DIR}"

# Backup PostgreSQL database
log "Backing up PostgreSQL database..."
PGPASSWORD=${POSTGRES_PASSWORD} pg_dump -h postgres -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-postgres} -F c -f ${TEMP_DIR}/database.dump

# Backup Keycloak configuration if available
if [ -d "/data/keycloak" ]; then
  log "Backing up Keycloak configuration..."
  mkdir -p ${TEMP_DIR}/keycloak
  cp -r /data/keycloak/themes ${TEMP_DIR}/keycloak/ 2>/dev/null || true
  cp -r /data/keycloak/providers ${TEMP_DIR}/keycloak/ 2>/dev/null || true
fi

# Backup Kong configuration if available
if [ -d "/data/kong" ]; then
  log "Backing up Kong configuration..."
  mkdir -p ${TEMP_DIR}/kong
  cp -r /data/kong/* ${TEMP_DIR}/kong/ 2>/dev/null || true
fi

# Backup Functions
if [ -d "/data/functions" ]; then
  log "Backing up Functions..."
  mkdir -p ${TEMP_DIR}/functions
  cp -r /data/functions/* ${TEMP_DIR}/functions/ 2>/dev/null || true
fi

# Backup environment variables
if [ -f "/data/.env" ]; then
  log "Backing up environment variables..."
  cp /data/.env ${TEMP_DIR}/ 2>/dev/null || true
fi

# Create backup archive
log "Creating backup archive: ${BACKUP_FILE}"
tar -czf ${BACKUP_FILE} -C ${TEMP_DIR} .

# Create/update symlink to latest backup
log "Updating latest backup symlink..."
ln -sf ${BACKUP_FILE} ${LATEST_LINK}

# Clean up temporary directory
log "Cleaning up temporary files..."
rm -rf ${TEMP_DIR}

# Remove old backups
log "Removing backups older than ${RETENTION_DAYS} days..."
find ${BACKUP_DIR} -name "sparkbaas_backup_*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete

# Record backup in database
log "Recording backup in database..."
PGPASSWORD=${POSTGRES_PASSWORD} psql -h postgres -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-postgres} -c "
  CREATE TABLE IF NOT EXISTS sparkbaas_backups (
    id SERIAL PRIMARY KEY,
    filename TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    size_bytes BIGINT
  );
  INSERT INTO sparkbaas_backups (filename, size_bytes)
  VALUES ('$(basename ${BACKUP_FILE})', $(stat -c %s ${BACKUP_FILE}));
"

log "Backup completed successfully: ${BACKUP_FILE}"
log "Total size: $(du -h ${BACKUP_FILE} | cut -f1)"

# List recent backups
log "Recent backups:"
ls -lh ${BACKUP_DIR}/sparkbaas_backup_*.tar.gz | tail -n 5