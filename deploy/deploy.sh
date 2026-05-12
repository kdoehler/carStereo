#!/bin/bash
# deploy.sh — Push CarStereo files to the Rock 5B via SCP + SSH
#
# Usage:
#   ./deploy/deploy.sh              # deploy everything
#   ./deploy/deploy.sh gps          # deploy single service
#   ./deploy/deploy.sh --dry-run    # show what would be deployed

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load config
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    echo "ERROR: .env file not found. Copy .env.example to .env and configure."
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no"
if [ -f "$PROJECT_DIR/$ROCK_KEY" ]; then
    SSH_OPTS="$SSH_OPTS -i $PROJECT_DIR/$ROCK_KEY"
fi

DRY_RUN=false
SERVICE=""

for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        *) SERVICE="$arg" ;;
    esac
done

ssh_cmd() {
    if $DRY_RUN; then
        echo "[DRY] ssh $ROCK_USER@$ROCK_HOST: $1"
    else
        ssh $SSH_OPTS "$ROCK_USER@$ROCK_HOST" "$1"
    fi
}

scp_cmd() {
    if $DRY_RUN; then
        echo "[DRY] scp $1 → $ROCK_USER@$ROCK_HOST:$2"
    else
        scp $SSH_OPTS -r "$1" "$ROCK_USER@$ROCK_HOST:$2"
    fi
}

echo "=== CarStereo Deploy ==="
echo "Target: $ROCK_USER@$ROCK_HOST:$ROCK_DEST"
echo ""

# Ensure target directory exists
ssh_cmd "sudo mkdir -p $ROCK_DEST && sudo chown $ROCK_USER:$ROCK_USER $ROCK_DEST"

if [ -n "$SERVICE" ]; then
    # Deploy single service
    echo "Deploying service: $SERVICE"
    if [ ! -d "$PROJECT_DIR/services/$SERVICE" ]; then
        echo "ERROR: Service directory services/$SERVICE not found"
        exit 1
    fi
    scp_cmd "$PROJECT_DIR/services/$SERVICE" "$ROCK_DEST/services/"
    ssh_cmd "sudo $ROCK_DEST/deploy/install.sh $SERVICE"
else
    # Deploy everything
    echo "Deploying all files..."

    # Services
    scp_cmd "$PROJECT_DIR/services" "$ROCK_DEST/"

    # System configs
    scp_cmd "$PROJECT_DIR/system" "$ROCK_DEST/"

    # Deploy scripts
    scp_cmd "$PROJECT_DIR/deploy" "$ROCK_DEST/"

    # Utility scripts
    scp_cmd "$PROJECT_DIR/scripts" "$ROCK_DEST/"

    # Make scripts executable
    ssh_cmd "find $ROCK_DEST -name '*.sh' -exec chmod +x {} +"
    ssh_cmd "find $ROCK_DEST -name '*.py' -exec chmod +x {} +"

    # Run installer
    ssh_cmd "sudo $ROCK_DEST/deploy/install.sh"
fi

echo ""
echo "=== Deploy complete ==="
