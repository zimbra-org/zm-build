# CXS Zimbra Lightweight

A stripped-down Zimbra Collaboration Suite build focused on **webmail + admin console only**. Based on [Zimbra FOSS](https://www.zimbra.com/), with calendar, tasks, briefcase, spell-check, and other non-essential components removed.

## Quick Start (Docker)

```bash
docker run -d --name zimbra -h mail.example.com \
  -e DOMAIN=example.com -e ADMIN_PASS=changeme \
  -p 25:25 -p 80:80 -p 443:443 -p 465:465 -p 587:587 \
  -p 993:993 -p 995:995 -p 7071:7071 \
  -v zimbra-data:/opt/zimbra \
  william1988/cxs-zimbra:1.0.0
```

First start takes a few minutes (runs Zimbra installer). Subsequent restarts are fast.

- **Webmail**: https://mail.example.com
- **Admin Console**: https://mail.example.com:7071

## Docker

### Run with Docker Compose

Edit `docker-compose.yml` to set your domain, hostname, and admin password, then:

```bash
docker compose up -d
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOMAIN` | `example.com` | Mail domain |
| `ZIMBRA_HOSTNAME` | container hostname | FQDN for the mail server |
| `ADMIN_PASS` | `changeme` | Admin password and LDAP passwords |
| `DNS_RESOLVER` | `8.8.8.8` | DNS resolver for Zimbra |

### Ports

| Port | Service |
|------|---------|
| 25 | SMTP |
| 80 | HTTP (redirects to HTTPS) |
| 443 | HTTPS (webmail) |
| 465 | SMTPS |
| 587 | Submission |
| 993 | IMAPS |
| 995 | POP3S |
| 7071 | Admin console (HTTPS) |

### Data Persistence

All data is stored on the host under `./data/` via bind mounts (not Docker volumes). This makes backup, migration, and inspection easy.

```
./data/
├── ldap/            # OpenLDAP database
├── db/              # MySQL/MariaDB data
├── logger-db/       # Logger database
├── store/           # Mailbox message store
├── index/           # Search indexes
├── redolog/         # Transaction redo logs
├── backup/          # Backups
├── conf/            # Zimbra config (localconfig.xml, certs, keys)
├── ssl/             # SSL certificates
├── log/             # Zimbra logs
├── mailboxd-logs/   # Jetty/mailbox logs
├── amavisd/         # Anti-virus/spam data
├── clamav/          # ClamAV virus definitions
├── postfix/         # Postfix mail queue
└── opendkim/        # DKIM signing keys
```

Directories are created automatically on first start. To reset, stop the container and `rm -rf ./data/`.

### Container Commands

```bash
# Check service status
docker exec zimbra docker-entrypoint.sh status

# Open a shell inside the container
docker exec -it zimbra bash

# Stop Zimbra services
docker exec zimbra docker-entrypoint.sh stop

# View logs
docker exec zimbra tail -f /opt/zimbra/log/mailbox.log
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
