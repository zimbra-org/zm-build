#!/bin/bash
# Don't use set -e — many Zimbra commands return non-zero on warnings

DOMAIN="${DOMAIN:-example.com}"
ZIMBRA_HOST="${ZIMBRA_HOSTNAME:-$(hostname -f)}"
ADMIN_PASS="${ADMIN_PASS:-changeme}"
DNS_RESOLVER="${DNS_RESOLVER:-8.8.8.8}"

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

start_zimbra() {
    echo "Starting Zimbra services..."

    # Start rsyslog (needed by Zimbra logger)
    rsyslogd 2>/dev/null || true

    # Start cron (needed for zmstatuslog, log pruning, etc.)
    cron 2>/dev/null || true

    setup_hosts
    verify_extensions
    install_crontab

    su - zimbra -c "zmcontrol start"

    # Run zmstatuslog once so admin console shows status immediately
    su - zimbra -c "/opt/zimbra/libexec/zmstatuslog" 2>/dev/null || true

    echo ""
    echo "============================================"
    echo "  Zimbra is running"
    echo "  Webmail: https://$ZIMBRA_HOST"
    echo "  Admin:   https://$ZIMBRA_HOST:7071"
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
