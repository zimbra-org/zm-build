#!/bin/bash
# Don't use set -e — many Zimbra commands return non-zero on warnings

DOMAIN="${DOMAIN:-example.com}"
ZIMBRA_HOST="${ZIMBRA_HOSTNAME:-$(hostname -f)}"
ADMIN_PASS="${ADMIN_PASS:-changeme}"
DNS_RESOLVER="${DNS_RESOLVER:-8.8.8.8}"
ADMIN_HOSTNAME="${ADMIN_HOSTNAME:-}"
BRAND_SKIN="${BRAND_SKIN:-serenity}"
BRAND_MAIL_URL="${BRAND_MAIL_URL:-https://$ZIMBRA_HOST}"

LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@$DOMAIN}"
ZIMBRA_INSTALLED_MARKER="/opt/zimbra/.docker_installed"

ensure_system_users() {
    # When a container is recreated (e.g. port change in docker-compose),
    # /opt/zimbra persists via volume but ALL system users/groups are lost
    # (/etc/passwd, /etc/group, /etc/sudoers.d/ are in the container layer).
    # This function recreates everything Zimbra needs to run.

    if id zimbra &>/dev/null && getent group postfix &>/dev/null; then
        return 0
    fi

    echo "Recreating system users/groups (lost on container recreate)..."

    # Detect zimbra UID/GID from home directory files (not binaries — those are root-owned)
    local ZIM_UID ZIM_GID
    ZIM_UID=$(stat -c '%u' /opt/zimbra/.bashrc 2>/dev/null || echo 999)
    ZIM_GID=$(stat -c '%g' /opt/zimbra/.bashrc 2>/dev/null || echo 999)

    # Skip if UID is 0 (root) — means files haven't been chowned yet
    [ "$ZIM_UID" = "0" ] && ZIM_UID=999
    [ "$ZIM_GID" = "0" ] && ZIM_GID=999

    # Zimbra user/group
    groupadd -g "$ZIM_GID" zimbra 2>/dev/null || true
    useradd -u "$ZIM_UID" -g "$ZIM_GID" -d /opt/zimbra -s /bin/bash -M zimbra 2>/dev/null || true
    usermod -aG adm,tty zimbra 2>/dev/null || true

    # Postfix user/group (required by MTA)
    # Detect postfix UID/GID from its spool directory
    local PF_UID PF_GID PD_GID
    PF_UID=$(stat -c '%u' /opt/zimbra/data/postfix/spool 2>/dev/null || echo 1001)
    PF_GID=$(stat -c '%g' /opt/zimbra/data/postfix/spool 2>/dev/null || echo 1001)
    PD_GID=$(stat -c '%g' /opt/zimbra/data/postfix/spool/maildrop 2>/dev/null || echo 1002)
    [ "$PF_UID" = "0" ] && PF_UID=1001
    [ "$PF_GID" = "0" ] && PF_GID=1001
    [ "$PD_GID" = "0" ] && PD_GID=1002

    groupadd -g "$PF_GID" postfix 2>/dev/null || true
    groupadd -g "$PD_GID" postdrop 2>/dev/null || true
    useradd -u "$PF_UID" -g "$PF_GID" -s /usr/sbin/nologin -M -d /opt/zimbra/data/postfix postfix 2>/dev/null || true
    usermod -aG postdrop zimbra 2>/dev/null || true

    # Zimbra passwordless sudo (many services use sudo internally)
    if [ ! -f /etc/sudoers.d/zimbra ]; then
        echo "zimbra ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/zimbra
        chmod 440 /etc/sudoers.d/zimbra
    fi

    if id zimbra &>/dev/null; then
        echo "System users restored: zimbra(uid=$ZIM_UID) postfix(uid=$PF_UID) postdrop(gid=$PD_GID)"
    else
        echo "ERROR: Failed to recreate system users"
        return 1
    fi
}

# Backward compat alias
ensure_zimbra_user() { ensure_system_users; }

setup_hosts() {
    local IP
    IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -n "$IP" ] && ! grep -q "$ZIMBRA_HOST" /etc/hosts 2>/dev/null; then
        echo "$IP $ZIMBRA_HOST $(echo $ZIMBRA_HOST | cut -d. -f1)" >> /etc/hosts
    fi
}

install_zimbra() {
    echo "============================================"
    echo "  Installing Zimbra (first run)"
    echo "  Domain:   $DOMAIN"
    echo "  Hostname: $ZIMBRA_HOST"
    echo "============================================"

    setup_hosts

    # DNS resolver for Zimbra
    mkdir -p /run/resolvconf
    echo "nameserver $DNS_RESOLVER" > /run/resolvconf/resolv.conf
    echo "nameserver $DNS_RESOLVER" > /etc/resolv.conf 2>/dev/null || true

    # Generate install config from template
    sed \
        -e "s/__DOMAIN__/$DOMAIN/g" \
        -e "s/__HOSTNAME__/$ZIMBRA_HOST/g" \
        -e "s/__ADMIN_PASS__/$ADMIN_PASS/g" \
        -e "s/__DNS_RESOLVER__/$DNS_RESOLVER/g" \
        /tmp/docker-install.conf > /tmp/install.conf

    # Run Zimbra installer (pass config as positional arg for AUTOINSTALL mode)
    cd /tmp/zcs-installer
    ./install.sh --platform-override --skip-upgrade-check /tmp/install.conf

    # Post-install tweaks

    # Fix LDAP master config — standalone server must be master
    su - zimbra -c "zmlocalconfig -e ldap_is_master=true" || true

    # Start LDAP and wait for it
    su - zimbra -c "ldap start" || true
    for i in $(seq 1 30); do
        su - zimbra -c "ldap status" &>/dev/null && break
        sleep 2
    done

    su - zimbra -c "zmprov ms $ZIMBRA_HOST zimbraMailSSLProxyPort 443 zimbraMailProxyPort 80" || true

    # Register nginx upstream services — Zimbra uses non-obvious LDAP service names:
    #   "zimbra"      = webclient upstream (SERVICE_WEBCLIENT in ProxyConfGen.java)
    #   "zimbraAdmin" = admin console upstream (SERVICE_ADMINCLIENT)
    #   "service"     = mailstore upstream (SERVICE_MAILCLIENT)
    # Without these, zmproxyconfgen finds no upstream servers and nginx won't serve port 443.
    su - zimbra -c "zmprov ms $ZIMBRA_HOST \
        +zimbraServiceEnabled zimbra \
        +zimbraServiceEnabled zimbraAdmin \
        +zimbraServiceEnabled service \
        +zimbraReverseProxyUpstreamLoginServers $ZIMBRA_HOST \
        zimbraReverseProxyAdminEnabled TRUE" || true

    # Create nginx.conf symlink (nginx expects it at common/conf/)
    ln -sf /opt/zimbra/conf/nginx.conf /opt/zimbra/common/conf/nginx.conf 2>/dev/null || true

    su - zimbra -c "/opt/zimbra/libexec/zmproxyconfgen" || true

    # Fix LMTP transport — inside Docker, the hostname resolves to the
    # external IP which can't route back to the container. Use 127.0.0.1.
    su - zimbra -c "zmprov ms $ZIMBRA_HOST zimbraMtaSmtpdVirtualTransport 'lmtp:[127.0.0.1]:7025'" || true
    for acct in $(su - zimbra -c "zmprov -l gaa $DOMAIN" 2>/dev/null); do
        su - zimbra -c "zmprov ma $acct zimbraMailTransport 'lmtp:[127.0.0.1]:7025'" 2>/dev/null || true
    done

    # Set default skin
    su - zimbra -c "zmprov mc default zimbraPrefSkin $BRAND_SKIN" || true
    su - zimbra -c "zmprov md $DOMAIN zimbraPrefSkin $BRAND_SKIN" || true

    # Enable calendar, disable briefcase/tasks
    su - zimbra -c "zmprov mc default zimbraFeatureCalendarEnabled TRUE" || true
    su - zimbra -c "zmprov mc default zimbraFeatureGroupCalendarEnabled TRUE" || true
    su - zimbra -c "zmprov mc default zimbraFeatureBriefcasesEnabled FALSE" || true
    su - zimbra -c "zmprov mc default zimbraFeatureTasksEnabled FALSE" || true

    # Set public service URL so links (change password, etc.) use proxy port 443
    su - zimbra -c "zmprov md $DOMAIN zimbraPublicServiceHostname $ZIMBRA_HOST" || true
    su - zimbra -c "zmprov md $DOMAIN zimbraPublicServicePort 443" || true
    su - zimbra -c "zmprov md $DOMAIN zimbraPublicServiceProtocol https" || true

    # SSH setup for remote management (mail queue monitoring, etc.)
    # Zimbra's GetMailQueueInfoRequest SSHs to the MTA host to run postqueue.
    if [ ! -f /opt/zimbra/.ssh/zimbra_identity ]; then
        su - zimbra -c "mkdir -p /opt/zimbra/.ssh && chmod 700 /opt/zimbra/.ssh" || true
        su - zimbra -c "ssh-keygen -t rsa -f /opt/zimbra/.ssh/zimbra_identity -N ''" || true
        su - zimbra -c "cat /opt/zimbra/.ssh/zimbra_identity.pub >> /opt/zimbra/.ssh/authorized_keys" || true
        su - zimbra -c "chmod 600 /opt/zimbra/.ssh/zimbra_identity /opt/zimbra/.ssh/authorized_keys" || true
    fi
    # Ensure SSH config uses the right identity and skips host key prompts
    if [ ! -f /opt/zimbra/.ssh/config ]; then
        cat > /opt/zimbra/.ssh/config <<'SSHEOF'
Host *
    StrictHostKeyChecking no
    IdentityFile /opt/zimbra/.ssh/zimbra_identity
SSHEOF
        chown zimbra:zimbra /opt/zimbra/.ssh/config
        chmod 600 /opt/zimbra/.ssh/config
    fi

    touch "$ZIMBRA_INSTALLED_MARKER"
    echo "============================================"
    echo "  Zimbra installation complete"
    echo "============================================"
}

verify_extensions() {
    # The nginx-lookup extension is critical for proxy routing.
    # With bind-mounted /opt/zimbra, dpkg installs may not persist it.
    local EXT_DIR="/opt/zimbra/lib/ext/nginx-lookup"
    if [ ! -f "$EXT_DIR/nginx-lookup.jar" ]; then
        echo "Restoring missing nginx-lookup extension..."
        mkdir -p "$EXT_DIR"
        # Extract from the installed zimbra-store deb in the installer
        if [ -d /tmp/zcs-installer/packages ]; then
            local DEB=$(ls /tmp/zcs-installer/packages/zimbra-store_*.deb 2>/dev/null | head -1)
            if [ -n "$DEB" ]; then
                dpkg-deb -x "$DEB" /tmp/store-extract
                cp /tmp/store-extract/opt/zimbra/lib/ext/nginx-lookup/nginx-lookup.jar "$EXT_DIR/"
                rm -rf /tmp/store-extract
                echo "nginx-lookup.jar restored"
            fi
        fi
    fi
}

install_crontab() {
    # Zimbra needs cron for zmstatuslog (service status monitoring),
    # log pruning, and other periodic tasks
    local CRON_DIR="/opt/zimbra/conf/crontabs"
    if [ -d "$CRON_DIR" ]; then
        cat "$CRON_DIR/crontab" \
            "$CRON_DIR/crontab.store" \
            "$CRON_DIR/crontab.ldap" \
            "$CRON_DIR/crontab.logger" \
            "$CRON_DIR/crontab.mta" \
            2>/dev/null | crontab -u zimbra - 2>/dev/null
        echo "Zimbra crontab installed"
    fi
}

setup_ssl() {
    echo "=== Setting up Let's Encrypt SSL certificate ==="

    # Stop proxy to free port 80 for certbot
    su - zimbra -c "zmproxyctl stop" 2>/dev/null || true
    sleep 2

    # Get Let's Encrypt cert
    local CERT_DOMAINS="-d $ZIMBRA_HOST"
    if [ -n "$ADMIN_HOSTNAME" ] && [ "$ADMIN_HOSTNAME" != "$ZIMBRA_HOST" ]; then
        CERT_DOMAINS="$CERT_DOMAINS -d $ADMIN_HOSTNAME"
    fi

    certbot certonly --standalone $CERT_DOMAINS \
        --non-interactive --agree-tos --email "$LETSENCRYPT_EMAIL" \
        --cert-name "$ZIMBRA_HOST"

    local CERT_DIR="/etc/letsencrypt/live/${ZIMBRA_HOST}"
    if [ ! -f "$CERT_DIR/privkey.pem" ]; then
        echo "WARNING: Let's Encrypt certificate not obtained, keeping self-signed cert"
        su - zimbra -c "zmproxyctl start" 2>/dev/null || true
        return 1
    fi

    # Deploy to Zimbra
    cp "$CERT_DIR/privkey.pem" /opt/zimbra/ssl/zimbra/commercial/commercial.key
    cp "$CERT_DIR/cert.pem" /opt/zimbra/ssl/zimbra/commercial/commercial.crt

    # Build CA chain
    wget -q https://letsencrypt.org/certs/isrgrootx1.pem -O /tmp/isrg-root.pem 2>/dev/null || true
    if [ -f /tmp/isrg-root.pem ]; then
        cat "$CERT_DIR/chain.pem" /tmp/isrg-root.pem > /opt/zimbra/ssl/zimbra/commercial/commercial_ca.crt
        rm -f /tmp/isrg-root.pem
    else
        cp "$CERT_DIR/chain.pem" /opt/zimbra/ssl/zimbra/commercial/commercial_ca.crt
    fi

    chown zimbra:zimbra /opt/zimbra/ssl/zimbra/commercial/*

    su - zimbra -c "zmcertmgr verifycrt comm" || true
    su - zimbra -c "zmcertmgr deploycrt comm \
        /opt/zimbra/ssl/zimbra/commercial/commercial.crt \
        /opt/zimbra/ssl/zimbra/commercial/commercial_ca.crt"

    # Restart all services to use new cert
    su - zimbra -c "zmcontrol restart"

    echo "=== SSL certificate deployed ==="
}

customize_nginx() {
    local CONF="/opt/zimbra/conf/nginx/includes/nginx.conf.web.https.default"
    local TMPL="/opt/zimbra/conf/nginx/templates/nginx.conf.web.https.default.template"

    # 1. Add static asset caching to the template (survives zmproxyctl restart)
    if ! grep -q "Static asset caching" "$TMPL" 2>/dev/null; then
        python3 -c "
f = '$TMPL'
with open(f) as fh:
    content = fh.read()

cache_block = '''    # Static asset caching - reduce round-trips on high-latency connections
    location ~* \.(js|css|zgz|jpg|jpeg|png|gif|ico|svg|woff|woff2|ttf|eot)\$ {
        proxy_pass          https://zimbra_ssl;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        set \$virtual_host \$http_host;
        if (\$virtual_host = '') {
            set \$virtual_host \$server_addr:\$server_port;
        }
        proxy_set_header Host \$virtual_host;
        proxy_redirect http://\$http_host/ https://\$http_host/;
        expires 30d;
        add_header Cache-Control \"public, immutable\";
    }

'''

target = '    location /\n    {'
if target in content:
    content = content.replace(target, cache_block + target, 1)
    with open(f, 'w') as fh:
        fh.write(content)
    print('Nginx caching added to template')
" 2>/dev/null
    fi

    # 2. Add admin.* server block for admin console on port 443
    if [ -n "$ADMIN_HOSTNAME" ]; then
        local ADMIN_CONF="/opt/zimbra/conf/nginx/includes/nginx.conf.web.admin.custom"
        cat > "$ADMIN_CONF" <<'ADMINEOF'
# Admin console via admin.* subdomain on port 443
server {
    listen 443 ssl http2;
    server_name ADMIN_HOST_PLACEHOLDER;
    client_max_body_size 0;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_certificate /opt/zimbra/conf/nginx.crt;
    ssl_certificate_key /opt/zimbra/conf/nginx.key;
    ssl_dhparam /opt/zimbra/conf/dhparam.pem;

    location / {
        proxy_pass https://zimbra_admin;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        set $relhost $host;
        if ($host = '') {
            set $relhost $server_addr;
        }
        proxy_set_header Host $relhost:7071;
        proxy_redirect https://$relhost:7071/ https://$host/;
    }

    location ^~ /service {
        proxy_pass https://zimbra_admin;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        set $relhost $host;
        if ($host = '') {
            set $relhost $server_addr;
        }
        proxy_set_header Host $relhost:7071;
        proxy_redirect https://$relhost:7071/ https://$host/;
    }
}
ADMINEOF
        sed -i "s/ADMIN_HOST_PLACEHOLDER/$ADMIN_HOSTNAME/g" "$ADMIN_CONF"

        # Include this config from the main nginx.conf if not already included
        local MAIN_CONF="/opt/zimbra/conf/nginx/includes/nginx.conf.web"
        if ! grep -q "admin.custom" "$MAIN_CONF" 2>/dev/null; then
            echo "include $ADMIN_CONF;" >> "$MAIN_CONF"
        fi
        echo "Admin console configured at https://$ADMIN_HOSTNAME"
    fi

    # Regenerate nginx config and restart proxy
    su - zimbra -c "/opt/zimbra/libexec/zmproxyconfgen" 2>/dev/null || true
    su - zimbra -c "zmproxyctl restart" 2>/dev/null || true
}

start_zimbra() {
    echo "Starting Zimbra services..."

    # Start rsyslog (needed by Zimbra logger)
    rsyslogd 2>/dev/null || true

    # Start cron (needed for zmstatuslog, log pruning, etc.)
    cron 2>/dev/null || true

    # Start sshd (needed for mail queue monitoring — mailbox SSHs to MTA)
    /usr/sbin/sshd 2>/dev/null || true

    setup_hosts

    # Recreate zimbra user if missing (happens when container is recreated
    # but /opt/zimbra volume persists)
    ensure_zimbra_user

    verify_extensions
    install_crontab

    # Ensure nginx.conf symlink exists (may not persist across container restarts)
    ln -sf /opt/zimbra/conf/nginx.conf /opt/zimbra/common/conf/nginx.conf 2>/dev/null || true

    su - zimbra -c "zmcontrol start"

    # Apply nginx customizations (caching, admin subdomain) after Zimbra starts
    customize_nginx

    # Run zmstatuslog once so admin console shows status immediately
    su - zimbra -c "/opt/zimbra/libexec/zmstatuslog" 2>/dev/null || true

    echo ""
    echo "============================================"
    echo "  Zimbra is running"
    echo "  Webmail: https://$ZIMBRA_HOST"
    if [ -n "$ADMIN_HOSTNAME" ]; then
    echo "  Admin:   https://$ADMIN_HOSTNAME"
    else
    echo "  Admin:   https://$ZIMBRA_HOST:7071"
    fi
    echo "============================================"
    echo ""

    su - zimbra -c "zmcontrol status"

    # Setup Let's Encrypt SSL (if certbot is available and no valid commercial cert exists)
    if command -v certbot &>/dev/null; then
        local CERT_TYPE=$(su - zimbra -c "zmcertmgr viewdeployedcrt" 2>/dev/null | grep "issuer=" | head -1)
        if echo "$CERT_TYPE" | grep -qi "let's encrypt\|R3\|R10\|R11\|E5\|E6"; then
            echo "Let's Encrypt cert already deployed, checking renewal..."
            certbot renew --quiet 2>/dev/null || true
        elif echo "$CERT_TYPE" | grep -qi "zimbra"; then
            echo "Self-signed cert detected, getting Let's Encrypt cert..."
            setup_ssl
        fi
    fi
}

stop_zimbra() {
    echo "Stopping Zimbra services..."
    ensure_zimbra_user
    su - zimbra -c "zmcontrol stop" 2>/dev/null || true
}

case "${1:-start}" in
    start)
        # Install on first run
        if [ ! -f "$ZIMBRA_INSTALLED_MARKER" ]; then
            install_zimbra
        fi

        start_zimbra

        # Trap signals for clean shutdown
        trap stop_zimbra SIGTERM SIGINT

        # Keep container running — follow logs
        LOGFILE=""
        for f in /opt/zimbra/log/mailbox.log /var/log/syslog /var/log/mail.log; do
            if [ -f "$f" ]; then LOGFILE="$f"; break; fi
        done

        if [ -n "$LOGFILE" ]; then
            tail -f "$LOGFILE" &
        else
            while true; do sleep 3600; done &
        fi
        wait
        ;;

    stop)
        stop_zimbra
        ;;

    install)
        install_zimbra
        ;;

    status)
        su - zimbra -c "zmcontrol status"
        ;;

    setup-ssl)
        setup_ssl
        ;;

    shell)
        exec /bin/bash
        ;;

    *)
        exec "$@"
        ;;
esac
