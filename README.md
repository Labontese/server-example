# Hetzner Dedicated Server - Docker Compose Setup

A production-ready, single-server Docker Compose setup for hosting multiple websites and services on a Hetzner dedicated server (tested on EX44: Intel i5-13500, 64GB RAM, 2x512GB NVMe).

## What's Included

### Web Services
- **Traefik v3** - Reverse proxy with automatic Let's Encrypt SSL
- **Authelia** - SSO/2FA authentication gateway
- **Next.js app** - Server-side rendered website
- **Nginx static site** - Static HTML/SPA hosting
- **WordPress x2** - PHP 8.3 + MariaDB with Redis object cache
- **Umami** - Privacy-focused web analytics

### Databases
- **MariaDB 11** - MySQL-compatible (WordPress, Uptime Kuma)
- **PostgreSQL 17** - (Umami, n8n)
- **Redis 7** - Object cache for WordPress

### Monitoring & Observability
- **Grafana 11** - Dashboards & visualization
- **Prometheus v3** - Metrics storage (30-day retention)
- **Loki 3** - Log aggregation (30-day retention)
- **Grafana Alloy** - Unified collector (host metrics, container metrics, Docker logs, DB metrics)
- **Uptime Kuma** - Uptime monitoring & status pages

### Automation & Tools
- **n8n** - Workflow automation
- **ntfy** - Push notifications
- **Watchtower** - Automatic Docker image updates
- **Homepage** - Service dashboard

## Architecture

```
Internet
  │
  ├─ :80 ──► Traefik ──► HTTP→HTTPS redirect
  └─ :443 ─► Traefik ──┬─► app.example.com      → Next.js container
                        ├─► blog.example.com      → WordPress container
                        ├─► docs.example.com       → Nginx (static)
                        ├─► stats.example.com      → Grafana (+ Authelia 2FA)
                        ├─► auth.example.com       → Authelia
                        ├─► status.example.com     → Uptime Kuma
                        ├─► analytics.example.com  → Umami
                        ├─► auto.example.com       → n8n (+ Authelia 2FA)
                        ├─► db.example.com         → Adminer (+ Authelia 2FA)
                        └─► notify.example.com     → ntfy
```

### Network Isolation

```
┌─────────────┐     ┌──────────────┐     ┌────────────────┐
│   web       │     │   database   │     │   monitoring   │
│             │     │              │     │                │
│ Traefik     │     │ MariaDB      │     │ Prometheus     │
│ Next.js     │     │ PostgreSQL   │     │ Loki           │
│ Nginx       │     │ Redis        │     │ Alloy          │
│ WordPress   │◄───►│              │     │ Graphite       │
│ Authelia    │     │              │     │                │
│ Umami       │◄───►│              │     │                │
│ Grafana     │     │              │◄───►│                │
│ ...         │     └──────────────┘     └────────────────┘
└─────────────┘
```

Three Docker networks ensure containers only communicate with what they need:
- **web** - Public-facing services + Traefik
- **database** - Database servers + their clients only
- **monitoring** - Metrics/logs pipeline (not public-facing)

## Quick Start

### 1. Bootstrap the Server

```bash
# SSH into your fresh Ubuntu 24.04 server as root
ssh root@your-server-ip

# Download and run the bootstrap script
curl -O https://raw.githubusercontent.com/youruser/hetzner-docker-example/main/scripts/bootstrap.sh
chmod +x bootstrap.sh
./bootstrap.sh
```

The bootstrap script configures:
- System packages, timezone, locale
- Non-root `deploy` user with sudo
- SSH hardening (key-only, no root login)
- UFW firewall (ports 22, 80, 443 only)
- Fail2ban (3 attempts = 1 hour ban)
- Kernel & network tuning for high traffic
- Docker CE + Compose
- Automatic security updates
- NTP time sync, swap, misc hardening

### 2. Clone and Configure

```bash
# SSH as deploy user
ssh deploy@your-server-ip

# Clone the repo
git clone https://github.com/youruser/hetzner-docker-example.git ~/server
cd ~/server

# Create your .env
cp .env.example .env

# Generate passwords for each service
openssl rand -base64 24  # For passwords
openssl rand -hex 32     # For secrets/keys

# Edit .env with your values
nano .env
```

### 3. Setup Authelia (SSO)

```bash
make authelia-setup     # Generates secrets
make authelia-password  # Creates password hash for users.yml
```

Edit `authelia/config/users.yml` with your user and the generated hash.

### 4. Deploy

```bash
make deploy
```

This pulls images, builds custom containers, and starts everything.

### 5. Verify

```bash
make ps          # Check all containers are running
make logs        # Tail all logs
```

## Project Structure

```
.
├── docker-compose.yml            # All services defined here
├── .env.example                  # Template for environment variables
├── Makefile                      # Common operations (deploy, backup, logs...)
│
├── traefik/
│   ├── traefik.yml               # Traefik static config
│   └── config/
│       └── middlewares.yml        # Security headers, rate limiting
│
├── authelia/
│   └── config/
│       └── configuration.yml     # SSO/2FA configuration
│
├── monitoring/
│   ├── loki-config.yml           # Log aggregation config
│   ├── alloy/
│   │   └── config.alloy          # Metrics & log collector
│   ├── prometheus/
│   │   └── prometheus.yml        # Metrics scraping config
│   └── grafana/
│       ├── dashboards/           # Pre-built JSON dashboards
│       └── provisioning/         # Auto-provisioned datasources
│
├── sites/
│   ├── blog/                     # Next.js app (source deployed via CI/CD)
│   ├── static-site/
│   │   └── nginx.conf            # Static site Nginx config
│   ├── wordpress-1/
│   │   └── uploads.ini           # PHP upload limits
│   └── wordpress-2/
│       └── uploads.ini
│
├── wordpress/
│   └── Dockerfile                # WordPress + phpredis extension
│
├── scripts/
│   ├── bootstrap.sh              # Server initial setup
│   ├── deploy.sh                 # Stack deployment
│   ├── backup.sh                 # DB dumps + offsite sync
│   ├── init-wordpress-dbs.sh     # MariaDB init (multi-DB)
│   └── init-postgres-dbs.sh      # PostgreSQL init (multi-DB)
│
├── github-actions/
│   ├── deploy-nextjs-app.yml     # CI/CD: Next.js app
│   └── deploy-static-site.yml   # CI/CD: static site
│
└── ntfy/
    └── server.yml                # Push notification config
```

## Key Patterns

### Multi-Site with Shared Databases

Both MariaDB and PostgreSQL are configured to host multiple databases. Init scripts (`scripts/init-*-dbs.sh`) automatically create databases, users, and monitoring access on first startup.

### WordPress with Redis Object Cache

The custom WordPress Dockerfile installs `phpredis`. Each WordPress site uses a separate Redis database index and key prefix to avoid collisions:

```yaml
# Site 1: Redis DB 0, prefix "site1_"
# Site 2: Redis DB 1, prefix "site2_"
```

### Authelia-Protected Admin Tools

Services like Grafana, Adminer, Traefik dashboard, and n8n are protected by Authelia's ForwardAuth middleware, requiring username + TOTP 2FA:

```yaml
labels:
  - "traefik.http.routers.myservice.middlewares=authelia@docker"
```

### Monitoring Pipeline

```
Host/Container Metrics ──► Alloy ──► Prometheus ──► Grafana
Docker Logs ─────────────► Alloy ──► Loki ────────► Grafana
```

Alloy replaces the need for separate node_exporter, cAdvisor, and Promtail containers.

### Backup Strategy

`scripts/backup.sh` dumps all databases and key data, then syncs to a Hetzner Storage Box via rsync/SSH:
- Local backups: kept 7 days
- Remote backups: kept 30 days
- Runs daily at 3:00 AM via cron (`make backup-setup`)

### CI/CD Deployment

GitHub Actions workflows in `github-actions/` show the pattern:
1. Build in CI
2. Rsync source/artifacts to server
3. `docker compose up -d --build` on server

## Subdomains Overview

| Subdomain | Service | Auth |
|-----------|---------|------|
| `app.example.com` | Next.js website | Public |
| `blog.example.com` | WordPress | Public |
| `docs.example.com` | Static site (Nginx) | Public |
| `auth.example.com` | Authelia SSO | Public |
| `stats.example.com` | Grafana | Authelia 2FA |
| `status.example.com` | Uptime Kuma | Public |
| `analytics.example.com` | Umami | Public |
| `auto.example.com` | n8n | Authelia 2FA |
| `db.example.com` | Adminer | Authelia 2FA |
| `notify.example.com` | ntfy | Public |
| `traefik.example.com` | Traefik Dashboard | Authelia 2FA |
| `home.example.com` | Homepage Dashboard | Authelia 2FA |

## Server Specs

Tested on **Hetzner EX44**:
- CPU: Intel Core i5-13500 (6P+8E cores, 20 threads)
- RAM: 64 GB DDR4 ECC
- Storage: 2x 512 GB NVMe SSD
- OS: Ubuntu 24.04 LTS

This setup comfortably runs 15+ containers with plenty of headroom.

## License

MIT
