#!/usr/bin/env bash
# ===================================================================
# Berry Router Engine - Git Patch & Hotfix Updater
# Automatically pulls hotfixes, rebuilds .deb, and restarts daemons
# ===================================================================

set -e

REPO_DIR="/usr/local/src/berry-router-engine"
GIT_REMOTE="origin"
GIT_BRANCH="main"

echo "==================================================================="
echo "🔄 Checking for Berry Router updates & security patches..."
echo "==================================================================="

# Ensure script is executed as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Please run the patch updater as root."
  exit 1
fi

# Clone repository locally if missing
if [ ! -d "$REPO_DIR" ]; then
    echo "📥 First-time setup: Cloning repository to $REPO_DIR..."
    mkdir -p /usr/local/src
    git clone https://github.com/azrin619/pi2-multinet-router.git "$REPO_DIR"
fi

cd "$REPO_DIR"

# Fetch upstream changes
git fetch "$GIT_REMOTE" "$GIT_BRANCH"

LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse "$GIT_REMOTE/$GIT_BRANCH")

if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
    echo "✅ Berry Router is already running the latest version ($LOCAL_HASH)."
    exit 0
fi

echo "🚨 New updates/security patches found!"
echo "   Local commit:  $LOCAL_HASH"
echo "   Remote commit: $REMOTE_HASH"

echo "📥 Pulling latest code updates..."
git reset --hard "$GIT_REMOTE/$GIT_BRANCH"

echo "🔨 Rebuilding Debian package..."
bash make_deb.sh

echo "📦 Applying package hotfix..."
dpkg -i berry-router-engine_1.2.0_all.deb || apt-get install -f -y

echo "🔄 Reloading systemd services..."
systemctl daemon-reload
systemctl restart berry-eth0-bootstrap.service
systemctl restart berry-wifi-auto.service
systemctl restart berry-driver-loader.service
systemctl restart router-engine.service

echo "==================================================================="
echo "🎉 SUCCESS! Berry Router successfully patched to version: $REMOTE_HASH"
echo "==================================================================="
