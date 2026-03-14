#!/bin/bash
# Don't use set -e — many Zimbra commands return non-zero on warnings

DOMAIN="${DOMAIN:-example.com}"
ZIMBRA_HOST="${ZIMBRA_HOSTNAME:-$(hostname -f)}"
ADMIN_PASS="${ADMIN_PASS:-changeme}"
DNS_RESOLVER="${DNS_RESOLVER:-8.8.8.8}"
ADMIN_HOSTNAME="${ADMIN_HOSTNAME:-}"
BRAND_SKIN="${BRAND_SKIN:-cxs}"
BRAND_MAIL_URL="${BRAND_MAIL_URL:-https://$ZIMBRA_HOST}"

ZIMBRA_INSTALLED_MARKER="/opt/zimbra/.docker_installed"

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
    su - zimbra -c "/opt/zimbra/libexec/zmproxyconfgen" || true

    # Fix LMTP transport — inside Docker, the hostname resolves to the
    # external IP which can't route back to the container. Use 127.0.0.1.
    su - zimbra -c "zmprov ms $ZIMBRA_HOST zimbraMtaSmtpdVirtualTransport 'lmtp:[127.0.0.1]:7025'" || true
    for acct in $(su - zimbra -c "zmprov -l gaa $DOMAIN" 2>/dev/null); do
        su - zimbra -c "zmprov ma $acct zimbraMailTransport 'lmtp:[127.0.0.1]:7025'" 2>/dev/null || true
    done

    # Set skin as default (COS, domain, and web.xml templates)
    su - zimbra -c "zmprov mc default zimbraPrefSkin $BRAND_SKIN" || true
    su - zimbra -c "zmprov mc default zimbraFeatureSkinChangeEnabled FALSE" || true
    su - zimbra -c "zmprov md $DOMAIN zimbraPrefSkin $BRAND_SKIN" || true
    su - zimbra -c "zmprov md $DOMAIN zimbraSkinLogoURL $BRAND_MAIL_URL" || true
    # Fix web.xml.in templates (Zimbra regenerates web.xml from these on each restart)
    sed -i "/<param-name>zimbraDefaultSkin<\/param-name>/{n;s|<param-value>[^<]*</param-value>|<param-value>$BRAND_SKIN</param-value>|}" \
        /opt/zimbra/jetty_base/etc/zimbra.web.xml.in \
        /opt/zimbra/jetty_base/etc/zimbraAdmin.web.xml.in 2>/dev/null || true
    sed -i "/<param-name>zimbraDefaultAdminSkin<\/param-name>/{n;s|<param-value>[^<]*</param-value>|<param-value>$BRAND_SKIN</param-value>|}" \
        /opt/zimbra/jetty_base/etc/zimbraAdmin.web.xml.in 2>/dev/null || true

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
        local ADMIN_CONF="/opt/zimbra/conf/nginx/includes/nginx.conf.web.admin.cxs"
        cat > "$ADMIN_CONF" <<'ADMINEOF'
# CXS: Admin console via admin.* subdomain on port 443
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
        if ! grep -q "admin.cxs" "$MAIN_CONF" 2>/dev/null; then
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
    verify_extensions
    install_crontab

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
}

stop_zimbra() {
    echo "Stopping Zimbra services..."
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

    shell)
        exec /bin/bash
        ;;

    *)
        exec "$@"
        ;;
esac
