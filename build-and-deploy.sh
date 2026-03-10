#!/bin/bash
# Quick build & deploy script for CXS lightweight Zimbra
# Usage: ./build-and-deploy.sh [--build-only | --deploy-only /path/to/tgz]
set -e

JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export JAVA_HOME
export PATH=$JAVA_HOME/bin:$PATH

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# --- Configuration ---
BUILD_RELEASE_NO="10.1.0"
BUILD_RELEASE="LIBERTY"
GIT_BRANCH="cxs-development,develop,master"
# ---------------------

build() {
    echo "=== Starting CXS Zimbra Build ==="
    echo "Using JAVA_HOME=$JAVA_HOME"
    java -version 2>&1 | head -1

    # Prerequisites check
    for cmd in ant mvn make ruby javac; do
        if ! command -v $cmd &>/dev/null; then
            echo "ERROR: $cmd not found. Install with:"
            echo "  apt-get install -y openjdk-8-jdk ant ant-optional maven ruby debhelper"
            exit 1
        fi
    done

    perl build.pl \
        --ant-options=-DskipTests=true \
        --build-type=FOSS \
        --build-release=$BUILD_RELEASE \
        --build-release-no=$BUILD_RELEASE_NO \
        --build-release-candidate=GA \
        --build-thirdparty-server=files.zimbra.com \
        --git-default-branch=$GIT_BRANCH \
        --no-interactive

    # Find the built tgz
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

    # Fix proxy ports if needed
    su - zimbra -c "zmprov gs \$(zmhostname) zimbraMailSSLProxyPort" | grep -q "443" || {
        echo "Fixing proxy ports..."
        su - zimbra -c "zmprov ms \$(zmhostname) zimbraMailSSLProxyPort 443 zimbraMailProxyPort 80"
        su - zimbra -c "/opt/zimbra/libexec/zmproxyconfgen"
        su - zimbra -c "zmproxyctl restart"
    }

    rm -rf "$TMPDIR"
    echo ""
    echo "=== Deploy complete ==="
    su - zimbra -c "zmcontrol status"
}

case "${1:-}" in
    --build-only)
        build
        ;;
    --deploy-only)
        if [ -z "$2" ]; then echo "Usage: $0 --deploy-only /path/to/zcs-*.tgz"; exit 1; fi
        deploy "$2"
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
