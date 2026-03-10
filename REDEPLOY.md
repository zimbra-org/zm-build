# CXS Zimbra Lightweight Build - Redeploy Guide

## Prerequisites (one-time setup)

```bash
# Install build tools
apt-get install -y openjdk-8-jdk ant ant-optional maven ruby debhelper

# Set Java 8 as default (Zimbra requires JDK 8, NOT 17)
update-alternatives --set java /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java
update-alternatives --set javac /usr/lib/jvm/java-8-openjdk-amd64/bin/javac

# Verify
java -version   # must show 1.8.x
javac -version  # must show 1.8.x
```

## Quick Redeploy (use the script)

```bash
cd /root/workspace/zimbra-org/zm-build
git checkout cxs-development
git pull

# Build only (~25 min)
./build-and-deploy.sh --build-only

# Deploy a built package
./build-and-deploy.sh --deploy-only ~/workspace/zimbra-org/BUILDS/*/zcs-*.tgz

# Or build + deploy in one go
./build-and-deploy.sh
```

## Manual Redeploy (step by step)

### Step 1: Clone zm-build

```bash
mkdir -p /root/workspace/zimbra-org && cd /root/workspace/zimbra-org
git clone -b cxs-development https://github.com/zimbra-org/zm-build.git
cd zm-build
```

### Step 2: Build

```bash
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64

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

Build output will be at:
```
~/workspace/zimbra-org/BUILDS/UBUNTU*-LIBERTY-*/zcs-10.1.0_GA_*.tgz
```

### Step 3: Deploy

```bash
# Extract installer
cd /tmp
tar xzf ~/workspace/zimbra-org/BUILDS/UBUNTU*-LIBERTY-*/zcs-*.tgz

# Stop Zimbra
su - zimbra -c "zmcontrol stop"

# Run installer
cd /tmp/zcs-10.1.0_GA_*
./install.sh --platform-override --skip-upgrade-check

# Start Zimbra
su - zimbra -c "zmcontrol start"
```

### Step 4: Post-deploy fixes

```bash
# Fix proxy ports (nginx must listen on 443, not internal 10443)
su - zimbra -c 'zmprov ms $(zmhostname) zimbraMailSSLProxyPort 443 zimbraMailProxyPort 80'
su - zimbra -c '/opt/zimbra/libexec/zmproxyconfgen'
su - zimbra -c 'zmproxyctl restart'

# Verify port 443 is listening
ss -tlnp | grep ':443 '
```

### Step 5: SSL Certificate (if expired)

```bash
# Stop proxy to free port 80
su - zimbra -c "zmproxyctl stop"
service nginx stop 2>/dev/null

# Get Let's Encrypt cert
certbot certonly --standalone -d mail.cloudxspace.com --non-interactive --agree-tos --email admin@cloudxspace.com

# Deploy to Zimbra
cp /etc/letsencrypt/live/mail.cloudxspace.com*/privkey.pem /opt/zimbra/ssl/zimbra/commercial/commercial.key
cp /etc/letsencrypt/live/mail.cloudxspace.com*/cert.pem /opt/zimbra/ssl/zimbra/commercial/commercial.crt
wget -q https://letsencrypt.org/certs/isrgrootx1.pem -O /tmp/isrg-root.pem
cat /etc/letsencrypt/live/mail.cloudxspace.com*/chain.pem /tmp/isrg-root.pem > /opt/zimbra/ssl/zimbra/commercial/commercial_ca.crt
chown zimbra:zimbra /opt/zimbra/ssl/zimbra/commercial/*

# Verify and deploy
su - zimbra -c "zmcertmgr verifycrt comm"
su - zimbra -c "zmcertmgr deploycrt comm /opt/zimbra/ssl/zimbra/commercial/commercial.crt /opt/zimbra/ssl/zimbra/commercial/commercial_ca.crt"

# Restart all services
su - zimbra -c "zmcontrol restart"
```

### Step 6: Set admin password

```bash
su - zimbra -c 'zmprov sp admin@cloudxspace.com "YOUR_PASSWORD_HERE"'
```

## Access URLs

| Page | URL |
|------|-----|
| Webmail | https://mail.cloudxspace.com |
| Admin Console | https://mail.cloudxspace.com:7071 |

## Resume a failed build

```bash
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64

ENV_RESUME_FLAG=true perl build.pl \
  --ant-options=-DskipTests=true \
  --build-type=FOSS \
  --build-release=LIBERTY \
  --build-release-no=10.1.0 \
  --build-release-candidate=GA \
  --build-thirdparty-server=files.zimbra.com \
  --git-default-branch=cxs-development,develop,master \
  --no-interactive
```

## What was stripped (Phase 1)

Removed repos: zm-aspell, zm-bulkprovision-admin-zimlet, zm-bulkprovision-store, zm-certificate-manager-admin-zimlet, zm-certificate-manager-store, zm-clam-scanner-store, zm-downloads, zm-helptooltip-zimlet, zm-nginx-lookup-store, zm-proxy-config-admin-zimlet, zm-versioncheck-admin-zimlet, zm-versioncheck-store, zm-versioncheck-utilities, zm-viewmail-admin-zimlet, zm-webclient-portal-example, zm-oauth-social, zm-gql

Removed packages: zimbra-apache, zimbra-spell

Disabled features: calendar, group calendar, tasks, briefcase, notebook
