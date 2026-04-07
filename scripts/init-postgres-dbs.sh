#!/bin/bash
# This script runs on first PostgreSQL startup only.
# It creates application databases and monitoring user.

set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Umami analytics database
    CREATE USER ${UMAMI_DB_USER:-umami} WITH PASSWORD '${UMAMI_DB_PASSWORD}';
    CREATE DATABASE ${UMAMI_DB_NAME:-umami} OWNER ${UMAMI_DB_USER:-umami};
    GRANT ALL PRIVILEGES ON DATABASE ${UMAMI_DB_NAME:-umami} TO ${UMAMI_DB_USER:-umami};

    -- n8n workflow automation database
    CREATE USER ${N8N_DB_USER:-n8n} WITH PASSWORD '${N8N_DB_PASSWORD}';
    CREATE DATABASE ${N8N_DB_NAME:-n8n} OWNER ${N8N_DB_USER:-n8n};
    GRANT ALL PRIVILEGES ON DATABASE ${N8N_DB_NAME:-n8n} TO ${N8N_DB_USER:-n8n};

    -- Monitoring user (read-only, for Alloy/Prometheus)
    CREATE USER ${POSTGRES_MONITORING_USER:-alloy} WITH PASSWORD '${POSTGRES_MONITORING_PASSWORD}';
    GRANT pg_monitor TO ${POSTGRES_MONITORING_USER:-alloy};
EOSQL
