#!/bin/bash
# This script runs on first MariaDB startup only.
# It creates additional databases, users, and monitoring access.
# The first database (WP1) is created automatically via MARIADB_DATABASE env var.

mysql -u root -p"${MARIADB_ROOT_PASSWORD}" <<-EOSQL
    -- Second WordPress database
    CREATE DATABASE IF NOT EXISTS \`${WP2_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS '${WP2_DB_USER}'@'%' IDENTIFIED BY '${WP2_DB_PASSWORD}';
    GRANT ALL PRIVILEGES ON \`${WP2_DB_NAME}\`.* TO '${WP2_DB_USER}'@'%';

    -- Uptime Kuma database
    CREATE DATABASE IF NOT EXISTS \`${UPTIME_KUMA_DB_NAME:-uptime_kuma}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS '${UPTIME_KUMA_DB_USER:-uptime_kuma}'@'%' IDENTIFIED BY '${UPTIME_KUMA_DB_PASSWORD}';
    GRANT ALL PRIVILEGES ON \`${UPTIME_KUMA_DB_NAME:-uptime_kuma}\`.* TO '${UPTIME_KUMA_DB_USER:-uptime_kuma}'@'%';

    -- Monitoring user (read-only, for Alloy/Prometheus)
    CREATE USER IF NOT EXISTS '${MARIADB_MONITORING_USER:-alloy}'@'%' IDENTIFIED BY '${MARIADB_MONITORING_PASSWORD}';
    GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO '${MARIADB_MONITORING_USER:-alloy}'@'%';

    FLUSH PRIVILEGES;
EOSQL
