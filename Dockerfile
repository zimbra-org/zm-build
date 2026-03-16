##############################################################################
# CXS Zimbra Lightweight - Docker Runtime Image
#
# Uses a pre-built .tgz installer (from build-and-deploy.sh --build-only)
#
# Build:
#   cp ~/workspace/zimbra-org/BUILDS/*/zcs-*.tgz ./zcs-installer.tgz
#   docker build -t william1988/cxs-zimbra:1.0.0 .
#
# Run:
#   docker run -d --name zimbra -h mail.cloudxspace.com \
#     -e DOMAIN=cloudxspace.com -e ADMIN_PASS=changeme \
#     -p 25:25 -p 80:80 -p 443:443 -p 465:465 -p 587:587 \
#     -p 993:993 -p 995:995 -p 7071:7071 \
#     -v zimbra-data:/opt/zimbra \
#     william1988/cxs-zimbra:1.0.0
##############################################################################

FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# Runtime dependencies needed by Zimbra installer and services
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        perl sysstat sqlite3 dnsmasq lsb-release \
        netcat-openbsd sudo wget curl rsyslog \
        net-tools iproute2 iputils-ping dnsutils \
        libperl5.30 libaio1 libgmp10 libstdc++6 \
        coreutils procps psmisc \
        gnupg apt-transport-https ca-certificates \
        openssh-client openssh-server cron certbot && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Pre-configure resolvconf to avoid /etc/resolv.conf symlink issue in Docker
# The Zimbra zimbra-os-requirements package pulls in resolvconf, which tries
# to symlink /etc/resolv.conf — but Docker bind-mounts that file.
RUN mkdir -p /run/resolvconf && \
    echo "nameserver 8.8.8.8" > /run/resolvconf/resolv.conf && \
    echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections && \
    apt-get update -qq && \
    apt-get install -y resolvconf || true && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Prepare sshd (Zimbra mail queue monitoring requires SSH to localhost)
RUN mkdir -p /run/sshd && \
    ssh-keygen -A

# Copy pre-built installer
COPY zcs-installer.tgz /tmp/zcs-installer.tgz

# Copy entrypoint and install config template
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY docker-install.conf /tmp/docker-install.conf
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Extract installer (actual install runs on first start via entrypoint)
RUN mkdir -p /tmp/zcs-installer && \
    tar xzf /tmp/zcs-installer.tgz -C /tmp/zcs-installer --strip-components=1 && \
    rm /tmp/zcs-installer.tgz

# Zimbra ports
# SMTP(25), HTTP(80), HTTPS(443), SMTPS(465), Submission(587)
# IMAPS(993), POP3S(995), Admin(7071)
EXPOSE 25 80 443 465 587 993 995 7071

VOLUME ["/opt/zimbra"]

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["start"]
