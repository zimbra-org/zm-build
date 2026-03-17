# Zimbra FOSS (Email + Calendar)

A Zimbra Collaboration Suite build focused on **email + calendar + admin console**. Based on [Zimbra FOSS](https://www.zimbra.com/), with briefcase, tasks, voicemail, portal, and other non-essential components removed.

## Quick Start (Docker)

```bash
docker compose up -d
```

Or pull and run directly:

```bash
docker run -d --name zimbra -h mail.example.com \
  -e DOMAIN=example.com -e ADMIN_PASS=changeme \
  -p 25:25 -p 80:80 -p 443:443 -p 465:465 -p 587:587 \
  -p 993:993 -p 995:995 -p 7071:7071 \
  -v ./data/zimbra:/opt/zimbra \
  william1988/cxs-zimbra:1.0.0
```

First start takes ~10 minutes (installs Zimbra, configures nginx, gets Let's Encrypt SSL cert). Subsequent restarts take ~2 minutes.

- **Webmail**: https://mail.example.com
- **Admin Console**: https://mail.example.com:7071

## Docker

### Run with Docker Compose

Edit `docker-compose.yml` to set your domain, hostname, and admin password, then:

```bash
docker compose up -d
```

### What Happens on First Start

1. Installs all Zimbra packages
2. Configures LDAP, MTA, mailbox, proxy
3. Registers nginx upstream services (`zimbra`, `zimbraAdmin`, `service`) so the proxy can discover its backends
4. Sets login upstream server (`zimbraReverseProxyUpstreamLoginServers`)
5. Creates nginx.conf symlink (`/opt/zimbra/common/conf/` → `/opt/zimbra/conf/`)
6. Sets proxy ports (443/80) and public service URL
7. Enables email + calendar, disables briefcase/tasks
8. Sets default skin to serenity (standard Zimbra)
9. Configures LMTP transport for Docker networking
10. Sets up SSH keys for mail queue monitoring
11. Adds nginx static asset caching
12. Gets Let's Encrypt SSL certificate automatically (requires port 80 open and DNS A record)

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOMAIN` | `example.com` | Mail domain |
| `ZIMBRA_HOSTNAME` | container hostname | FQDN for the mail server |
| `ADMIN_PASS` | `changeme` | Admin password and LDAP passwords |
| `ADMIN_HOSTNAME` | _(empty)_ | Optional separate hostname for admin console on port 443 |
| `DNS_RESOLVER` | `8.8.8.8` | DNS resolver for Zimbra |
| `BRAND_SKIN` | `serenity` | Default webmail skin |
| `LETSENCRYPT_EMAIL` | `admin@$DOMAIN` | Email for Let's Encrypt notifications |

### Prerequisites (before starting)

1. **DNS A record**: `mail.yourdomain.com` → your server IP
2. **DNS MX record**: `yourdomain.com` → `mail.yourdomain.com`
3. **Port 80 open**: Required for Let's Encrypt certificate issuance
4. **Ports open**: 25, 80, 443, 465, 587, 993, 995, 7071

### Ports

| Port | Service |
|------|---------|
| 25 | SMTP |
| 80 | HTTP (used by Let's Encrypt, redirects to HTTPS) |
| 443 | HTTPS (webmail) |
| 465 | SMTPS |
| 587 | Submission |
| 993 | IMAPS |
| 995 | POP3S |
| 7071 | Admin console (HTTPS) |

### Data Persistence

All Zimbra data is stored on the host under `./data/zimbra/` via a bind mount.

```yaml
# In docker-compose.yml:
volumes:
  - ./data/zimbra:/opt/zimbra
```

Key directories inside `./data/zimbra/`:
- `store/` — Mailbox message store
- `data/ldap/` — OpenLDAP database
- `db/` — MySQL/MariaDB data
- `conf/` — Config, certs, keys
- `log/` — Zimbra logs
- `index/`, `redolog/`, `backup/` — Search indexes, redo logs, backups

### Clean Redeploy (reset everything)

```bash
docker compose down
rm -rf ./data/zimbra/* ./data/zimbra/.*
docker compose up -d
```

**Important**: You must include `./data/zimbra/.*` to remove the hidden `.docker_installed` marker file, otherwise the container will skip installation on next start.

### Container Commands

```bash
# Check service status
docker exec cxs-zimbra docker-entrypoint.sh status

# Open a shell inside the container
docker exec -it cxs-zimbra bash

# Stop Zimbra services
docker exec cxs-zimbra docker-entrypoint.sh stop

# Manually renew/setup SSL certificate
docker exec cxs-zimbra docker-entrypoint.sh setup-ssl

# View logs
docker exec cxs-zimbra tail -f /opt/zimbra/log/mailbox.log

# Set admin password
docker exec cxs-zimbra su - zimbra -c "zmprov sp admin@yourdomain.com YOUR_PASSWORD"
```

### Build the Docker Image

Requires a pre-built `.tgz` installer (see [Building from Source](#building-from-source) below):

```bash
# Copy the latest build
cp ~/workspace/zimbra-org/BUILDS/*/zcs-*.tgz ./zcs-installer.tgz

# Build the image
docker build -t william1988/cxs-zimbra:1.0.0 .

# Push to Docker Hub
docker login
docker push william1988/cxs-zimbra:1.0.0
```

### Troubleshooting (Docker)

| Problem | Solution |
|---------|----------|
| SSL certificate warning in browser | Port 80 was blocked during first start, so Let's Encrypt failed. Run `docker exec cxs-zimbra docker-entrypoint.sh setup-ssl` |
| Port 443 not listening | Upstream services not registered. Reset: `docker compose down && rm -rf ./data/zimbra/* ./data/zimbra/.* && docker compose up -d` |
| 502 Bad Gateway | Login upstream not set or mailbox still starting. Wait 2 minutes, then check `docker exec cxs-zimbra su - zimbra -c "zmcontrol status"` |
| Container starts but services don't run | Data dir corrupted. Reset: `docker compose down && rm -rf ./data/zimbra/* ./data/zimbra/.* && docker compose up -d` |
| Change password link goes to port 8443 | `zimbraPublicService*` not set. Run: `docker exec cxs-zimbra su - zimbra -c "zmprov md yourdomain.com zimbraPublicServiceHostname mail.yourdomain.com zimbraPublicServicePort 443 zimbraPublicServiceProtocol https"` |
| Slow first start | Normal — first run downloads packages, installs Zimbra, configures services, and gets SSL cert (~10 minutes) |

## Building from Source

### Prerequisites

Ubuntu 20.04:

```bash
sudo apt-get install openjdk-8-jdk ant ant-optional maven ruby debhelper rpm build-essential git
```

Or use the helper script:

```bash
./build-and-deploy.sh --install-prereqs
```

### Build

```bash
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
./build-and-deploy.sh --build-only
```

The `.tgz` installer will be in `~/workspace/zimbra-org/BUILDS/`.

### Build & Deploy (bare metal)

```bash
./build-and-deploy.sh                          # Build + deploy (interactive)
./build-and-deploy.sh --build-only             # Build only
./build-and-deploy.sh --deploy-only /path.tgz  # Deploy a built package
./build-and-deploy.sh --post-deploy            # Run post-deploy fixes only
./build-and-deploy.sh --setup-ssl              # Renew/setup SSL cert only
./build-and-deploy.sh --install-prereqs        # Install build prerequisites
```

### Advanced: build.pl Options

```bash
perl build.pl \
  --ant-options=-DskipTests=true \
  --build-type=FOSS \
  --build-release=LIBERTY \
  --build-release-no=10.1.0 \
  --build-release-candidate=GA \
  --build-thirdparty-server=files.zimbra.com \
  --git-default-branch=cxs-development,develop,master \
  --no-interactive
```

### Key Build Environment Variables

| Variable | Description |
|----------|-------------|
| `ENV_CACHE_CLEAR_FLAG=true` | Clear `~/.zcs-deps` and `~/.ivy2/cache` before build |
| `ENV_RESUME_FLAG=true` | Resume from last incomplete build |
| `ENV_SKIP_CLEAN_FLAG=1` | Skip clean step in build stages |
| `ENV_BUILD_INCLUDE=<pattern>` | Only build stages matching pattern |

## Architecture

### What's Included

- Email (webmail client)
- Calendar + group calendar
- Contacts / address book
- Admin console
- LDAP directory
- MTA (Postfix)
- Proxy (nginx)
- IMAP/POP3
- Anti-virus/anti-spam (Amavis)
- SNMP monitoring

### What's Removed (vs stock Zimbra)

- Spell checker (zimbra-apache, zimbra-spell)
- Briefcase/Notebook features
- Tasks
- Voicemail
- Portal/Portlets
- Docs editor

### Build System

- `build.pl` — Main build orchestrator (Perl)
- `instructions/FOSS_repo_list.pl` — Git repositories to clone
- `instructions/FOSS_staging_list.pl` — Build stages
- `instructions/FOSS_package_list.pl` — Packages to create
- `instructions/bundling-scripts/` — Package bundling scripts

### Build Flow

1. **Init** — Parse options, detect OS, validate prerequisites
2. **Prepare** — Create dirs, download third-party JARs
3. **Checkout** — Clone/update repositories
4. **Build** — Execute build stages (ant/mvn/make), bundle packages
5. **Deploy** — Create package repository, generate installer `.tgz`
