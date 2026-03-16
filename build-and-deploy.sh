#!/bin/bash
# CXS Zimbra Lightweight - Build, Deploy & Configure
# Usage:
#   ./build-and-deploy.sh                          # Build + deploy (interactive)
#   ./build-and-deploy.sh --build-only             # Build only
#   ./build-and-deploy.sh --deploy-only /path.tgz  # Deploy a built package
#   ./build-and-deploy.sh --post-deploy            # Run post-deploy fixes only
#   ./build-and-deploy.sh --setup-ssl              # Renew/setup SSL cert only
#   ./build-and-deploy.sh --install-prereqs        # Install build prerequisites
set -e

# --- Configuration (edit these) ---
DOMAIN="cloudxspace.com"
HOSTNAME="mail.${DOMAIN}"
ADMIN_EMAIL="admin@${DOMAIN}"
BUILD_RELEASE_NO="10.1.0"
BUILD_RELEASE="LIBERTY"
GIT_BRANCH="cxs-development,develop,master"
JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64

# Branding (substituted into .properties files at build time)
BRAND_NAME="CXS"
BRAND_DOMAIN="cloudxspace.com"
BRAND_COMPANY="CloudX Space"
BRAND_MAIL_URL="https://mail.${DOMAIN}"
BRAND_ADMIN_URL="https://admin.${DOMAIN}"
BRAND_SKIN="cxs"
# ----------------------------------

export JAVA_HOME
export PATH=$JAVA_HOME/bin:$PATH

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
cd "$SCRIPT_DIR"

BRANDING_FILES=()

customize_branding() {
    echo "=== Applying branding: ${BRAND_NAME} / ${BRAND_DOMAIN} ==="
    local WC="$WORKSPACE_DIR/zm-web-client"
    local AC="$WORKSPACE_DIR/zm-admin-console"

    BRANDING_FILES=(
        "$WC/WebRoot/messages/ZmMsg.properties"
        "$WC/WebRoot/public/login.jsp"
        "$WC/WebRoot/skins/cxs/skin.properties"
        "$AC/WebRoot/messages/ZabMsg.properties"
        "$AC/WebRoot/admin_skins/_base/base/skin.properties"
        "$AC/WebRoot/admin_skins/carbon/skin.properties"
        "$AC/WebRoot/admin_skins/serenity/skin.properties"
        "$AC/WebRoot/admin_skins/cxs/skin.properties"
    )

    for f in "${BRANDING_FILES[@]}"; do
        if [ -f "$f" ]; then
            sed -i \
                -e "s|@@BRAND_NAME@@|${BRAND_NAME}|g" \
                -e "s|@@BRAND_DOMAIN@@|${BRAND_DOMAIN}|g" \
                -e "s|@@BRAND_COMPANY@@|${BRAND_COMPANY}|g" \
                -e "s|@@BRAND_MAIL_URL@@|${BRAND_MAIL_URL}|g" \
                -e "s|@@BRAND_ADMIN_URL@@|${BRAND_ADMIN_URL}|g" \
                "$f"
        fi
    done
    echo "Branding applied to ${#BRANDING_FILES[@]} files"
}

restore_branding() {
    echo "=== Restoring branding placeholders ==="
    for f in "${BRANDING_FILES[@]}"; do
        if [ -f "$f" ]; then
            local repo_dir
            repo_dir=$(cd "$(dirname "$f")" && git rev-parse --show-toplevel 2>/dev/null) || continue
            local rel_path="${f#$repo_dir/}"
            (cd "$repo_dir" && git checkout -- "$rel_path" 2>/dev/null) || true
        fi
    done
}

install_prereqs() {
    echo "=== Installing build prerequisites ==="
    apt-get update -qq
    apt-get install -y openjdk-8-jdk ant ant-optional maven ruby debhelper rpm build-essential git
    update-alternatives --set java /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java
    update-alternatives --set javac /usr/lib/jvm/java-8-openjdk-amd64/bin/javac
    echo "=== Prerequisites installed ==="
    java -version 2>&1 | head -1
}

build() {
    echo "=== Starting CXS Zimbra Build ==="
    echo "Using JAVA_HOME=$JAVA_HOME"
    java -version 2>&1 | head -1

    for cmd in ant mvn make ruby javac; do
        if ! command -v $cmd &>/dev/null; then
            echo "ERROR: $cmd not found. Run: $0 --install-prereqs"
            exit 1
        fi
    done

    customize_branding
    trap 'restore_branding' EXIT

    perl build.pl \
        --ant-options=-DskipTests=true \
        --build-type=FOSS \
        --build-release=$BUILD_RELEASE \
        --build-release-no=$BUILD_RELEASE_NO \
        --build-release-candidate=GA \
        --build-thirdparty-server=files.zimbra.com \
        --git-default-branch=$GIT_BRANCH \
        --no-interactive

    TGZ=$(ls -t ~/workspace/zimbra-org/BUILDS/*/zcs-*.tgz 2>/dev/null | head -1)
    if [ -z "$TGZ" ]; then
        echo "ERROR: Build completed but no .tgz found"
        exit 1
    fi
    echo ""
    echo "=== Build successful ==="
    echo "Installer: $TGZ"
    echo ""
    echo "To deploy: $0 --deploy-only $TGZ"
}

setup_ssl() {
    echo "=== Setting up SSL certificate ==="

    if ! command -v certbot &>/dev/null; then
        apt-get install -y certbot
    fi

    # Stop proxy to free port 80
    su - zimbra -c "zmproxyctl stop" 2>/dev/null || true
    service nginx stop 2>/dev/null || true
    sleep 1

    # Get Let's Encrypt cert
    certbot certonly --standalone -d "$HOSTNAME" \
        --non-interactive --agree-tos --email "$ADMIN_EMAIL" \
        --cert-name "$HOSTNAME"

    # Find the cert directory
    local CERT_DIR="/etc/letsencrypt/live/${HOSTNAME}"
    if [ ! -d "$CERT_DIR" ]; then
        # Try with suffix if renewed
        CERT_DIR=$(ls -d /etc/letsencrypt/live/${HOSTNAME}* 2>/dev/null | tail -1)
    fi

    if [ ! -f "$CERT_DIR/privkey.pem" ]; then
        echo "ERROR: Certificate not found in $CERT_DIR"
        exit 1
    fi

    # Deploy to Zimbra
    cp "$CERT_DIR/privkey.pem" /opt/zimbra/ssl/zimbra/commercial/commercial.key
    cp "$CERT_DIR/cert.pem" /opt/zimbra/ssl/zimbra/commercial/commercial.crt

    wget -q https://letsencrypt.org/certs/isrgrootx1.pem -O /tmp/isrg-root.pem
    cat "$CERT_DIR/chain.pem" /tmp/isrg-root.pem > /opt/zimbra/ssl/zimbra/commercial/commercial_ca.crt
    rm -f /tmp/isrg-root.pem

    chown zimbra:zimbra /opt/zimbra/ssl/zimbra/commercial/*

    su - zimbra -c "zmcertmgr verifycrt comm"
    su - zimbra -c "zmcertmgr deploycrt comm \
        /opt/zimbra/ssl/zimbra/commercial/commercial.crt \
        /opt/zimbra/ssl/zimbra/commercial/commercial_ca.crt"

    echo "=== SSL certificate deployed ==="
}

post_deploy() {
    echo "=== Running post-deploy fixes ==="

    local ZM_HOST
    ZM_HOST=$(su - zimbra -c "zmhostname" 2>/dev/null)

    # 1. Register required services for nginx upstream discovery
    #    Zimbra's zmproxyconfgen uses these LDAP service names (not the obvious ones):
    #      "zimbra"      -> webclient upstream servers (SERVICE_WEBCLIENT)
    #      "zimbraAdmin"  -> admin console upstream servers (SERVICE_ADMINCLIENT)
    #      "service"      -> mailstore upstream servers (SERVICE_MAILCLIENT)
    echo "Registering proxy upstream services..."
    su - zimbra -c "zmprov ms ${ZM_HOST} \
        +zimbraServiceEnabled zimbra \
        +zimbraServiceEnabled zimbraAdmin \
        +zimbraServiceEnabled service \
        +zimbraReverseProxyUpstreamLoginServers ${ZM_HOST} \
        zimbraReverseProxyAdminEnabled TRUE"

    # 2. Fix proxy ports (nginx must listen on 443)
    local CURRENT_PORT=$(su - zimbra -c "zmprov gs ${ZM_HOST} zimbraMailSSLProxyPort" 2>/dev/null | grep zimbraMailSSLProxyPort | awk '{print $2}')
    if [ "$CURRENT_PORT" != "443" ]; then
        echo "Fixing proxy ports (was $CURRENT_PORT, setting to 443)..."
        su - zimbra -c "zmprov ms ${ZM_HOST} zimbraMailSSLProxyPort 443 zimbraMailProxyPort 80"
    else
        echo "Proxy ports OK (443)"
    fi

    # 3. Exclude snap mounts from disk monitoring
    echo "Setting disk monitor to ignore snap mounts..."
    su - zimbra -c "zmlocalconfig -e zmdisklog_exclude_pattern='/snap'"
    su - zimbra -c "zmstatctl restart"

    # 4. Create nginx.conf symlink (nginx expects it at common/conf/)
    if [ ! -e /opt/zimbra/common/conf/nginx.conf ]; then
        echo "Creating nginx.conf symlink..."
        ln -sf /opt/zimbra/conf/nginx.conf /opt/zimbra/common/conf/nginx.conf
    fi

    # 5. Regenerate proxy config and restart
    echo "Regenerating proxy config..."
    su - zimbra -c "/opt/zimbra/libexec/zmproxyconfgen"
    su - zimbra -c "zmproxyctl stop" 2>/dev/null || true
    su - zimbra -c "zmproxyctl start"

    # 4. Set skin as default (COS, domain, and web.xml templates)
    echo "Setting ${BRAND_SKIN} skin as default..."
    su - zimbra -c "zmprov mc default zimbraPrefSkin ${BRAND_SKIN}" 2>/dev/null || true
    su - zimbra -c "zmprov mc default zimbraFeatureSkinChangeEnabled FALSE" 2>/dev/null || true
    su - zimbra -c "zmprov md ${DOMAIN} zimbraPrefSkin ${BRAND_SKIN}" 2>/dev/null || true
    su - zimbra -c "zmprov md ${DOMAIN} zimbraSkinLogoURL ${BRAND_MAIL_URL}" 2>/dev/null || true
    # Fix web.xml.in templates (Zimbra regenerates web.xml from these on each restart)
    sed -i "/<param-name>zimbraDefaultSkin<\/param-name>/{n;s|<param-value>[^<]*</param-value>|<param-value>${BRAND_SKIN}</param-value>|}" \
        /opt/zimbra/jetty_base/etc/zimbra.web.xml.in \
        /opt/zimbra/jetty_base/etc/zimbraAdmin.web.xml.in 2>/dev/null || true
    sed -i "/<param-name>zimbraDefaultAdminSkin<\/param-name>/{n;s|<param-value>[^<]*</param-value>|<param-value>${BRAND_SKIN}</param-value>|}" \
        /opt/zimbra/jetty_base/etc/zimbraAdmin.web.xml.in 2>/dev/null || true

    # 5. Verify services
    echo ""
    echo "=== Service status ==="
    su - zimbra -c "zmcontrol status"

    # 6. Verify ports
    echo ""
    echo "=== Port check ==="
    ss -tlnp | grep -E ':443 |:7071 ' && echo "OK: HTTPS (443) and Admin (7071) listening" || echo "WARNING: ports not listening"

    echo ""
    echo "=== Post-deploy complete ==="
    echo "Webmail:  https://${HOSTNAME}"
    echo "Admin:    https://${HOSTNAME}:7071"
    echo ""
    echo "To set admin password:"
    echo "  su - zimbra -c 'zmprov sp admin@${DOMAIN} YOUR_PASSWORD'"
}

deploy() {
    local TGZ="$1"
    if [ ! -f "$TGZ" ]; then
        echo "ERROR: File not found: $TGZ"
        exit 1
    fi

    echo "=== Deploying $TGZ ==="
    local TMPDIR=$(mktemp -d)
    tar xzf "$TGZ" -C "$TMPDIR"
    local INSTALLER_DIR=$(ls -d "$TMPDIR"/zcs-* | head -1)

    echo "Stopping Zimbra..."
    su - zimbra -c "zmcontrol stop" || true

    echo "Running installer..."
    cd "$INSTALLER_DIR"
    ./install.sh --platform-override --skip-upgrade-check

    echo "Starting Zimbra..."
    su - zimbra -c "zmcontrol start"

    # Run all post-deploy fixes
    post_deploy

    # Setup SSL if cert is expired or missing
    local CERT_EXPIRY=$(su - zimbra -c "zmcertmgr viewdeployedcrt" 2>/dev/null | grep notAfter | head -1 | sed 's/notAfter=//')
    if [ -n "$CERT_EXPIRY" ]; then
        local EXPIRY_EPOCH=$(date -d "$CERT_EXPIRY" +%s 2>/dev/null || echo 0)
        local NOW_EPOCH=$(date +%s)
        if [ "$EXPIRY_EPOCH" -lt "$NOW_EPOCH" ]; then
            echo "SSL certificate expired, renewing..."
            setup_ssl
            su - zimbra -c "zmcontrol restart"
        fi
    fi

    rm -rf "$TMPDIR"
    echo ""
    echo "========================================="
    echo "  DEPLOY COMPLETE"
    echo "========================================="
    echo "Webmail:  https://${HOSTNAME}"
    echo "Admin:    https://${HOSTNAME}:7071"
    echo ""
    echo "Set admin password:"
    echo "  su - zimbra -c 'zmprov sp admin@${DOMAIN} YOUR_PASSWORD'"
    echo "========================================="
}

case "${1:-}" in
    --install-prereqs)
        install_prereqs
        ;;
    --build-only)
        build
        ;;
    --deploy-only)
        if [ -z "$2" ]; then echo "Usage: $0 --deploy-only /path/to/zcs-*.tgz"; exit 1; fi
        deploy "$2"
        ;;
    --post-deploy)
        post_deploy
        ;;
    --setup-ssl)
        setup_ssl
        su - zimbra -c "zmcontrol restart"
        ;;
    *)
        build
        TGZ=$(ls -t ~/workspace/zimbra-org/BUILDS/*/zcs-*.tgz 2>/dev/null | head -1)
        read -p "Deploy $TGZ now? [y/N] " yn
        if [[ "$yn" =~ ^[Yy] ]]; then
            deploy "$TGZ"
        fi
        ;;
esac
