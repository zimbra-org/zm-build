#!/bin/bash
set -e

DOMAIN="${DOMAIN:-example.com}"
HOSTNAME="${ZIMBRA_HOSTNAME:-$(hostname -f)}"
ADMIN_PASS="${ADMIN_PASS:-changeme}"
DNS_RESOLVER="${DNS_RESOLVER:-8.8.8.8}"

ZIMBRA_INSTALLED_MARKER="/opt/zimbra/.docker_installed"

# Ensure bind-mounted directories exist with correct ownership
prepare_data_dirs() {
    local DIRS=(
        /opt/zimbra/data/ldap
        /opt/zimbra/db
        /opt/zimbra/logger/db
        /opt/zimbra/store
        /opt/zimbra/index
        /opt/zimbra/redolog
        /opt/zimbra/backup
        /opt/zimbra/conf
        /opt/zimbra/ssl
        /opt/zimbra/log
        /opt/zimbra/mailboxd/logs
        /opt/zimbra/data/amavisd
        /opt/zimbra/data/clamav
        /opt/zimbra/data/postfix
        /opt/zimbra/data/opendkim
    )
    for d in "${DIRS[@]}"; do
        mkdir -p "$d"
    done

    # Fix ownership if zimbra user exists (after install)
    if id zimbra &>/dev/null; then
        for d in "${DIRS[@]}"; do
            chown -R zimbra:zimbra "$d" 2>/dev/null || true
        done
    fi
}

install_zimbra() {
    echo "============================================"
    echo "  Installing Zimbra (first run)"
    echo "  Domain:   $DOMAIN"
    echo "  Hostname: $HOSTNAME"
    echo "============================================"

    # Set hostname properly
    echo "$HOSTNAME" > /etc/hostname
    hostname "$HOSTNAME"

    # Ensure hostname resolves
    local IP
    IP=$(hostname -I | awk '{print $1}')
    if ! grep -q "$HOSTNAME" /etc/hosts 2>/dev/null; then
        echo "$IP $HOSTNAME $(echo $HOSTNAME | cut -d. -f1)" >> /etc/hosts
    fi

    # DNS resolver for Zimbra
    echo "nameserver $DNS_RESOLVER" > /etc/resolv.conf

    # Generate install config from template
    sed \
        -e "s/__DOMAIN__/$DOMAIN/g" \
        -e "s/__HOSTNAME__/$HOSTNAME/g" \
        -e "s/__ADMIN_PASS__/$ADMIN_PASS/g" \
        -e "s/__DNS_RESOLVER__/$DNS_RESOLVER/g" \
        /tmp/docker-install.conf > /tmp/install.conf

    # Prepare data directories before install
    prepare_data_dirs

    # Run Zimbra installer
    cd /tmp/zcs-installer
    ./install.sh --platform-override --skip-upgrade-check < /tmp/install.conf

    # Fix ownership on bind-mounted dirs after install
    prepare_data_dirs

    # Post-install tweaks
    su - zimbra -c "zmprov ms $HOSTNAME zimbraMailSSLProxyPort 443 zimbraMailProxyPort 80" || true
    su - zimbra -c "/opt/zimbra/libexec/zmproxyconfgen" || true

    touch "$ZIMBRA_INSTALLED_MARKER"
    echo "============================================"
    echo "  Zimbra installation complete"
    echo "============================================"
}

start_zimbra() {
    echo "Starting Zimbra services..."

    # Start rsyslog (needed by Zimbra)
    rsyslogd 2>/dev/null || true

    # Ensure hostname is set correctly on container restart
    if [ -n "$HOSTNAME" ]; then
        hostname "$HOSTNAME" 2>/dev/null || true
        local IP
        IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        if [ -n "$IP" ] && ! grep -q "$HOSTNAME" /etc/hosts 2>/dev/null; then
            echo "$IP $HOSTNAME $(echo $HOSTNAME | cut -d. -f1)" >> /etc/hosts
        fi
    fi

    su - zimbra -c "zmcontrol start"

    echo ""
    echo "============================================"
    echo "  Zimbra is running"
    echo "  Webmail: https://$HOSTNAME"
    echo "  Admin:   https://$HOSTNAME:7071"
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
        # Prepare data dirs (fix ownership on restart)
        prepare_data_dirs

        # Install on first run
        if [ ! -f "$ZIMBRA_INSTALLED_MARKER" ]; then
            install_zimbra
        fi

        start_zimbra

        # Trap signals for clean shutdown
        trap stop_zimbra SIGTERM SIGINT

        # Keep container running — follow mailbox log
        if [ -f /opt/zimbra/log/mailbox.log ]; then
            tail -f /opt/zimbra/log/mailbox.log &
        else
            tail -f /var/log/syslog &
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
