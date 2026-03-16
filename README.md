# CXS Zimbra Lightweight

A stripped-down Zimbra Collaboration Suite build focused on **webmail + admin console only**. Based on [Zimbra FOSS](https://www.zimbra.com/), with calendar, tasks, briefcase, spell-check, and other non-essential components removed.

## Quick Start (Docker)

```bash
docker run -d --name zimbra -h mail.example.com \
  -e DOMAIN=example.com -e ADMIN_PASS=changeme \
  -p 25:25 -p 80:80 -p 443:443 -p 465:465 -p 587:587 \
  -p 993:993 -p 995:995 -p 7071:7071 \
  -v ./data/zimbra:/opt/zimbra \
  william1988/cxs-zimbra:1.0.0
```

First start takes ~10 minutes (installs Zimbra, configures nginx, gets Let's Encrypt SSL cert). Subsequent restarts are fast (~2 minutes).

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
3. **Registers nginx upstream services** (`zimbra`, `zimbraAdmin`, `service`) so the proxy can discover its backends
4. **Sets login upstream server** (`zimbraReverseProxyUpstreamLoginServers`) so the webmail login page routes correctly
5. **Creates nginx.conf symlink** (`/opt/zimbra/common/conf/` -> `/opt/zimbra/conf/`)
6. **Gets Let's Encrypt SSL certificate** automatically via certbot (requires port 80 open and DNS A record pointing to the server)
7. Deploys SSL cert to all Zimbra services (proxy, mailbox, MTA, LDAP)
8. Sets default skin, configures LMTP transport for Docker networking

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOMAIN` | `example.com` | Mail domain |
| `ZIMBRA_HOSTNAME` | container hostname | FQDN for the mail server |
| `ADMIN_PASS` | `changeme` | Admin password and LDAP passwords |
| `ADMIN_HOSTNAME` | _(empty)_ | Optional separate hostname for admin console on port 443 |
| `DNS_RESOLVER` | `8.8.8.8` | DNS resolver for Zimbra |
| `BRAND_SKIN` | `cxs` | Default webmail skin |
| `LETSENCRYPT_EMAIL` | `admin@$DOMAIN` | Email for Let's Encrypt notifications |

### Prerequisites (before starting)

1. **DNS A record**: `mail.yourdomain.com` -> your server IP
2. **DNS MX record**: `yourdomain.com` -> `mail.yourdomain.com`
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

All Zimbra data is stored on the host under `./data/zimbra/` via a bind mount. This keeps everything out of Docker and makes backup/migration easy.

```yaml
# In docker-compose.yml:
volumes:
  - ./data/zimbra:/opt/zimbra
```

Key directories inside `./data/zimbra/`:
- `store/` — Mailbox message store
- `data/ldap/` — OpenLDAP database
- `db/` — MySQL/MariaDB data
- `conf/` — Config, certs, keys (localconfig.xml, slapd.crt, etc.)
- `log/` — Zimbra logs
- `index/`, `redolog/`, `backup/` — Search indexes, redo logs, backups

To reset: stop the container and `rm -rf ./data/`.

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
| Port 443 not listening | Upstream services not registered. Check `docker logs cxs-zimbra` for "no upstream" errors. Restart container: `docker compose down && rm -rf ./data && docker compose up -d` |
| 502 Bad Gateway | Login upstream not set or mailbox still starting. Wait 2 minutes, then check `docker exec cxs-zimbra su - zimbra -c "zmcontrol status"` |
| Container starts but services don't run | Check `docker logs cxs-zimbra`. If "user zimbra does not exist", the data dir is corrupted. Reset: `docker compose down && rm -rf ./data && docker compose up -d` |
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

The `build-and-deploy.sh` script handles the full lifecycle:

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

You can also set options in a `config.build` file:

```
BUILD_RELEASE               = LIBERTY
BUILD_RELEASE_NO            = 10.1.0
BUILD_RELEASE_CANDIDATE     = GA
BUILD_TYPE                  = FOSS
BUILD_THIRDPARTY_SERVER     = files.zimbra.com
INTERACTIVE                 = 0
```

Then just run `./build.pl`.

### Key Environment Variables

| Variable | Description |
|----------|-------------|
| `ENV_CACHE_CLEAR_FLAG=true` | Clear `~/.zcs-deps` and `~/.ivy2/cache` before build |
| `ENV_RESUME_FLAG=true` | Resume from last incomplete build |
| `ENV_SKIP_CLEAN_FLAG=1` | Skip clean step in build stages |
| `ENV_BUILD_INCLUDE=<pattern>` | Only build stages matching pattern |

## Architecture

### What's Included

- Webmail client (zm-web-client)
- Admin console (zm-admin-console)
- LDAP directory
- MTA (Postfix)
- Proxy (nginx)
- IMAP/POP3
- Anti-virus/anti-spam (Amavis)
- SNMP monitoring

### What's Removed (vs stock Zimbra)

- Spell checker (zimbra-apache, zimbra-spell)
- Calendar/Tasks features
- Briefcase/Notebook features
- Chat
- 17 unnecessary repositories

### Build System

- `build.pl` - Main build orchestrator (Perl)
- `instructions/FOSS_repo_list.pl` - 42 git repositories to clone
- `instructions/FOSS_staging_list.pl` - 36 build stages
- `instructions/FOSS_package_list.pl` - 9 packages
- `instructions/bundling-scripts/` - Package bundling scripts

### Build Flow

1. **Init** - Parse options, detect OS, validate prerequisites
2. **Prepare** - Create dirs, download third-party JARs
3. **Checkout** - Clone/update 42 repositories
4. **Build** - Execute 36 build stages (ant/mvn/make), bundle 9 packages
5. **Deploy** - Create package repository, generate installer `.tgz`

## Deployment Guide (Bare Metal)

This section covers deploying CXS Zimbra on a bare-metal Ubuntu 20.04 server step by step.

### 1. Server Requirements

- Ubuntu 20.04 LTS (64-bit)
- Minimum 8 GB RAM, 4 CPU cores
- Valid FQDN pointing to the server (e.g. `mail.yourdomain.com`)
- Ports open: 25, 80, 443, 465, 587, 993, 995, 7071
- DNS records configured:
  - **A record**: `mail.yourdomain.com` → your server IP
  - **MX record**: `yourdomain.com` → `mail.yourdomain.com`
  - **SPF**: `v=spf1 mx ~all`

### 2. Install Build Prerequisites

```bash
./build-and-deploy.sh --install-prereqs
```

This installs: `openjdk-8-jdk`, `ant`, `ant-optional`, `maven`, `ruby`, `debhelper`, `rpm`, `build-essential`, `git`.

### 3. Build the Installer

```bash
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
./build-and-deploy.sh --build-only
```

This takes 30-60 minutes. The `.tgz` installer will be in `~/workspace/zimbra-org/BUILDS/`.

### 4. Deploy the Installer

```bash
./build-and-deploy.sh --deploy-only /path/to/zcs-*.tgz
```

The installer will launch an interactive menu. Configure these settings:

| Setting | Recommended Value |
|---------|-------------------|
| Common Configuration > Hostname | `mail.yourdomain.com` |
| Common Configuration > LDAP master host | `mail.yourdomain.com` |
| zimbra-store > Admin user | `admin@yourdomain.com` |
| zimbra-store > Admin password | Set a strong password |

When done, press **`a`** to apply the configuration.

### 5. Fix: "Installing mailboxd SSL certificates...failed"

If setup fails at "Installing mailboxd SSL certificates", this is because LDAP wasn't fully ready when `zmprov` tried to save the certificate. The cert files themselves are already deployed. Fix it with:

```bash
# 1. Make sure LDAP is running
su - zimbra -c "ldap status"
su - zimbra -c "ldap start"    # if not running

# 2. Re-deploy the self-signed certificate
su - zimbra -c "/opt/zimbra/bin/zmcertmgr deploycrt self"

# 3. Re-run setup to continue from where it stopped
/opt/zimbra/libexec/zmsetup.pl
```

If `zmprov` still fails, check the server is registered in LDAP:

```bash
su - zimbra -c "zmprov gs $(hostname -f) zimbraServiceHostname"
```

### 6. Post-Deploy Fixes

After the installer finishes:

```bash
./build-and-deploy.sh --post-deploy
```

This does:
- **Registers nginx upstream services** — Zimbra uses non-obvious LDAP service names for proxy discovery: `zimbra` (webclient), `zimbraAdmin` (admin console), `service` (mailstore). Without these, nginx has no upstream servers and port 443 won't work.
- Sets `zimbraReverseProxyUpstreamLoginServers` so the login page routes correctly (without this, nginx returns 502 trying to resolve `zimbra_login_ssl`)
- Enables admin console via reverse proxy (`zimbraReverseProxyAdminEnabled TRUE`)
- Creates the `nginx.conf` symlink (`/opt/zimbra/common/conf/` -> `/opt/zimbra/conf/`)
- Sets nginx proxy ports to 443/80
- Excludes snap mounts from disk monitoring
- Regenerates proxy config
- Sets default skin to `cxs`
- Verifies all services are running

### 7. Setup SSL (Let's Encrypt)

Replace the self-signed certificate with a real one:

```bash
./build-and-deploy.sh --setup-ssl
```

This uses `certbot` in standalone mode (stops proxy briefly to free port 80), gets a Let's Encrypt certificate, and deploys it to Zimbra.

### 8. Verify Deployment

```bash
# Check all services
su - zimbra -c "zmcontrol status"

# Check ports
ss -tlnp | grep -E ':443 |:7071 '

# Test webmail
curl -k https://mail.yourdomain.com

# Test admin console
curl -k https://mail.yourdomain.com:7071
```

### 9. Set Admin Password

```bash
su - zimbra -c "zmprov sp admin@yourdomain.com YOUR_PASSWORD"
```

### 10. Access

- **Webmail**: `https://mail.yourdomain.com`
- **Admin Console**: `https://mail.yourdomain.com:7071`

### Troubleshooting

| Problem | Solution |
|---------|----------|
| SSL cert install failed | See Step 5 above — re-deploy cert after LDAP is running |
| Port 443 not listening / nginx "no servers are inside upstream" | Upstream services not registered. Run `./build-and-deploy.sh --post-deploy` — it registers the required LDAP services (`zimbra`, `zimbraAdmin`, `service`) that nginx needs to discover upstream servers |
| Blank page on webmail | Skin not deployed. Run `./build-and-deploy.sh --post-deploy` to set default skin |
| Port 7071 not listening | Run `su - zimbra -c "zmmailboxdctl start"` |
| LDAP won't start | Check `/opt/zimbra/log/slapd.log` and ensure hostname resolves correctly |
| Services fail after reboot | Run `su - zimbra -c "zmcontrol start"` (no auto-start by default) |
| Setup log location | `/tmp/zmsetup.*.log` |
| "Notification failed" at end of setup | Harmless — Zimbra's tracking server was unreachable. Setup completed successfully, ignore this. |

## Development

### zm-mailbox Build Order

Build order for zm-mailbox subdirectories (dependencies via ivy.xml):

1. `native`
2. `common`
3. `soap`
4. `client`
5. `store`

From each subdirectory:

```bash
ant -Dzimbra.buildinfo.version=8.7.6_GA clean compile publish-local deploy
```

`publish-local` adds artifacts to `~/.zcs-deps`; `deploy` installs to runtime location and restarts services.
