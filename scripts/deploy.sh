#!/usr/bin/env bash
# ============================================================
# Deploy / Update the server stack
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Check .env exists
if [ ! -f .env ]; then
  echo "ERROR: .env file not found. Copy .env.example to .env and configure it."
  exit 1
fi

# Source env for validation
source .env

echo "=== Deploying stack ==="

# Pull latest images
docker compose pull

# Build custom images
docker compose build --pull

# Start/update services (recreate only changed containers)
docker compose up -d --remove-orphans

# Prune unused images
docker image prune -f

echo ""
echo "=== Deployment complete ==="
docker compose ps
