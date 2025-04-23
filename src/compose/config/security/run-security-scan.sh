#!/bin/sh
# SparkBaaS Security Scanner
# Performs automated security scanning of the SparkBaaS environment

set -e

# Timestamp for logs and reports
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_DIR="/results"
REPORT_FILE="${RESULTS_DIR}/scan_report_${TIMESTAMP}.json"
LATEST_LINK="${RESULTS_DIR}/latest_report.json"
SERVICES="postgres keycloak kong postgrest functions admin"

# Log with timestamp
log() {
  echo "[$(date -Iseconds)] $1"
}

# Initialize scan report
init_report() {
  local hostname=$(hostname)
  cat > $REPORT_FILE << EOF
{
  "scan_id": "${TIMESTAMP}",
  "timestamp": "$(date -Iseconds)",
  "hostname": "${hostname}",
  "version": "0.1.0",
  "summary": {
    "status": "in_progress",
    "services_scanned": 0,
    "vulnerabilities": {
      "critical": 0,
      "high": 0,
      "medium": 0,
      "low": 0,
      "info": 0
    }
  },
  "services": {},
  "network": {},
  "recommendations": []
}
EOF
  log "Initialized scan report: $REPORT_FILE"
}

# Add or update a field in the JSON report using jq
update_report() {
  local field="$1"
  local value="$2"
  
  # Use a temporary file for the update
  local temp_file=$(mktemp)
  jq "$field = $value" $REPORT_FILE > $temp_file && mv $temp_file $REPORT_FILE
}

# Add a vulnerability to the report
add_vulnerability() {
  local service="$1"
  local level="$2" # critical, high, medium, low, info
  local title="$3"
  local description="$4"
  local recommendation="$5"
  
  # Create vulnerability JSON
  local vuln=$(cat << EOF
{
  "level": "$level",
  "title": "$title",
  "description": "$description",
  "recommendation": "$recommendation",
  "detected_at": "$(date -Iseconds)"
}
EOF
)

  # Add to report using jq
  local temp_file=$(mktemp)
  jq ".services.\"$service\".vulnerabilities += [$vuln] | .summary.vulnerabilities.\"$level\" += 1" $REPORT_FILE > $temp_file && mv $temp_file $REPORT_FILE
}

# Scan network and open ports
scan_network() {
  log "Starting network scan..."
  
  # Initialize network section in report
  update_report ".network" '{}'
  
  # Ping sweep to discover hosts in network
  log "Discovering hosts in network..."
  local network_hosts=$(nmap -sn sparkbaas_network -oG - | grep "Status: Up" | wc -l)
  update_report ".network.hosts_discovered" "$network_hosts"
  
  # Scan for open ports on key services
  log "Scanning for open ports..."
  
  for service in $SERVICES; do
    log "Scanning service: $service"
    
    # Initialize service in report if it doesn't exist
    update_report ".services.\"$service\"" '{}'
    
    # Perform port scan
    local port_scan=$(nmap -T4 -A sparkbaas_$service 2>/dev/null || echo "scan failed")
    
    # Extract open ports
    local open_ports=$(echo "$port_scan" | grep "^[0-9]" | grep "open" | cut -d "/" -f 1 | tr '\n' ',' | sed 's/,$//')
    
    # Add to report
    update_report ".services.\"$service\".open_ports" "\"$open_ports\""
    update_report ".services.\"$service\".scan_status" "\"completed\""
    
    # Check for specific security issues based on the service
    case $service in
      postgres)
        # Check if PostgreSQL is accessible without password
        if echo "$port_scan" | grep -q "5432/tcp open postgresql"; then
          log "Testing PostgreSQL security..."
          if PGPASSWORD="" psql -h sparkbaas_postgres -U postgres -c '\l' &>/dev/null; then
            add_vulnerability "postgres" "critical" "PostgreSQL accessible without password" \
              "The PostgreSQL server allows connections without password authentication" \
              "Ensure password authentication is enforced for all PostgreSQL users"
          fi
        fi
        ;;
      keycloak)
        # Check for default Keycloak credentials
        if curl -s http://sparkbaas_keycloak:8080/ | grep -q "Welcome to Keycloak"; then
          log "Testing Keycloak security..."
          if curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" \
             -d "username=admin&password=admin" \
             "http://sparkbaas_keycloak:8080/auth/realms/master/protocol/openid-connect/token" \
             | grep -q "access_token"; then
            add_vulnerability "keycloak" "critical" "Default Keycloak admin credentials" \
              "Keycloak is using default admin/admin credentials" \
              "Change the default admin password for Keycloak immediately"
          fi
        fi
        ;;
    esac
  done
  
  log "Network scan completed"
}

# Check security headers
check_security_headers() {
  log "Checking security headers..."
  
  # List of services with HTTP endpoints
  local http_services="keycloak kong postgrest functions admin"
  
  for service in $http_services; do
    log "Checking headers for: $service"
    
    # Get headers
    local headers=$(curl -s -I "http://sparkbaas_$service:8080" 2>/dev/null || echo "failed")
    
    # Check for important security headers
    local missing_headers=""
    
    if ! echo "$headers" | grep -q "Strict-Transport-Security"; then
      missing_headers="$missing_headers HSTS,"
    fi
    
    if ! echo "$headers" | grep -q "X-Content-Type-Options"; then
      missing_headers="$missing_headers X-Content-Type-Options,"
    fi
    
    if ! echo "$headers" | grep -q "X-Frame-Options"; then
      missing_headers="$missing_headers X-Frame-Options,"
    fi
    
    if ! echo "$headers" | grep -q "Content-Security-Policy"; then
      missing_headers="$missing_headers CSP,"
    fi
    
    # Report missing headers if any
    if [ -n "$missing_headers" ]; then
      missing_headers=$(echo $missing_headers | sed 's/,$//')
      add_vulnerability "$service" "medium" "Missing security headers" \
        "The service is missing important security headers: $missing_headers" \
        "Configure the service to include all recommended security headers"
    fi
  done
  
  log "Security headers check completed"
}

# Check TLS configurations
check_tls_configuration() {
  log "Checking TLS configurations..."
  
  # Check Traefik TLS configuration
  local tls_result=$(curl -s -k -v https://traefik.localhost 2>&1 || echo "failed")
  
  # Check for weak protocols
  if echo "$tls_result" | grep -q "TLSv1.0\|TLSv1.1\|SSLv3"; then
    add_vulnerability "traefik" "high" "Weak TLS protocol version" \
      "The system is using outdated TLS protocol versions (TLSv1.0, TLSv1.1, or SSLv3)" \
      "Configure Traefik to use only TLSv1.2 or TLSv1.3"
  fi
  
  # Check for weak ciphers
  if echo "$tls_result" | grep -q "RC4\|DES\|3DES\|MD5\|NULL"; then
    add_vulnerability "traefik" "high" "Weak TLS cipher suites" \
      "The system is using weak cipher suites that are considered insecure" \
      "Configure Traefik to use only strong cipher suites"
  fi
  
  log "TLS configuration check completed"
}

# Main execution
main() {
  log "Starting SparkBaaS security scan..."
  
  # Ensure results directory exists
  mkdir -p $RESULTS_DIR
  
  # Initialize scan report
  init_report
  
  # Wait for network to be ready
  sleep 5
  
  # Run scans
  scan_network
  check_security_headers
  check_tls_configuration
  
  # Update summary status
  update_report ".summary.status" "\"completed\""
  update_report ".summary.services_scanned" "$(echo $SERVICES | wc -w)"
  update_report ".summary.scan_duration_seconds" "$(( $(date +%s) - $(date -d "$(jq -r .timestamp $REPORT_FILE)" +%s) ))"
  
  # Create recommendations based on vulnerabilities
  log "Generating recommendations..."
  local crit_count=$(jq '.summary.vulnerabilities.critical' $REPORT_FILE)
  local high_count=$(jq '.summary.vulnerabilities.high' $REPORT_FILE)
  
  if [ "$crit_count" -gt 0 ]; then
    update_report ".recommendations" '["Address all critical vulnerabilities immediately", "Schedule a full security review", "Consider temporarily restricting network access until critical issues are resolved"]'
  elif [ "$high_count" -gt 0 ]; then
    update_report ".recommendations" '["Address all high severity vulnerabilities within 7 days", "Schedule a follow-up scan after remediation", "Review security configurations"]'
  else
    update_report ".recommendations" '["Continue regular security scanning", "Consider penetration testing to find deeper issues", "Maintain current security posture"]'
  fi
  
  # Create/update link to latest report
  ln -sf $REPORT_FILE $LATEST_LINK
  
  # Record scan in database
  log "Recording scan in database..."
  PGPASSWORD=${POSTGRES_PASSWORD} psql -h sparkbaas_postgres -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-postgres} -c "
    CREATE TABLE IF NOT EXISTS sparkbaas_security_scans (
      id SERIAL PRIMARY KEY,
      scan_id TEXT NOT NULL,
      timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      critical_count INT,
      high_count INT,
      medium_count INT,
      low_count INT,
      info_count INT,
      report_file TEXT
    );
    
    INSERT INTO sparkbaas_security_scans (
      scan_id, critical_count, high_count, medium_count, low_count, info_count, report_file
    ) VALUES (
      '${TIMESTAMP}',
      ${crit_count},
      ${high_count},
      $(jq '.summary.vulnerabilities.medium' $REPORT_FILE),
      $(jq '.summary.vulnerabilities.low' $REPORT_FILE),
      $(jq '.summary.vulnerabilities.info' $REPORT_FILE),
      '$(basename ${REPORT_FILE})'
    );
  " 2>/dev/null || log "Warning: Could not record scan in database"
  
  log "Security scan completed: $REPORT_FILE"
  
  # Final summary
  echo "==============================================="
  echo "SECURITY SCAN SUMMARY"
  echo "==============================================="
  echo "Total vulnerabilities discovered:"
  echo "- Critical: $crit_count"
  echo "- High:     $high_count"
  echo "- Medium:   $(jq '.summary.vulnerabilities.medium' $REPORT_FILE)"
  echo "- Low:      $(jq '.summary.vulnerabilities.low' $REPORT_FILE)"
  echo "- Info:     $(jq '.summary.vulnerabilities.info' $REPORT_FILE)"
  echo "==============================================="
  echo "Report saved to: $REPORT_FILE"
  echo "==============================================="
}

# Run main function
main "$@"