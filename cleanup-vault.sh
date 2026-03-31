#!/bin/bash
# cleanup.sh -- Complete Docker cleanup for Vault
#
# Usage:
#   ./cleanup.sh         # Interactive - shows what will be deleted
#   ./cleanup.sh --force # Force cleanup without confirmation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-interactive}"

header() {
  echo
  echo "=========================================="
  echo "$@"
  echo "=========================================="
  echo
}

header "Vault Docker Cleanup"

# ────────────────────────────────────────────────────────────────────────────
# Show what will be deleted
# ────────────────────────────────────────────────────────────────────────────

echo "This will:"
echo "  • Stop all Vault containers"
echo "  • Remove the vault container"
echo "  • Remove all Vault volumes"
echo "  • Remove vault-init.json"
echo "  • KEEP your .env configuration"
echo

if [ "$MODE" = "interactive" ]; then
  read -r -p "Continue? (yes/no) " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
  fi
  echo
fi

# ────────────────────────────────────────────────────────────────────────────
# Stop and remove containers
# ────────────────────────────────────────────────────────────────────────────

echo "Step 1: Stopping containers..."

# Stop via docker compose
cd "$SCRIPT_DIR"
docker compose down 2>/dev/null || true

# Kill any remaining vault container
docker kill vault 2>/dev/null || true

# Remove the container
docker rm -f vault 2>/dev/null || true

echo "  ✓ Containers stopped"

# ────────────────────────────────────────────────────────────────────────────
# Remove volumes
# ────────────────────────────────────────────────────────────────────────────

echo
echo "Step 2: Removing volumes..."

PROJECT_NAME=$(basename "$SCRIPT_DIR")

# Try direct removal
docker volume rm "${PROJECT_NAME}_vault-data" 2>/dev/null && echo "  ✓ Removed ${PROJECT_NAME}_vault-data" || echo "  ⚠ Could not remove ${PROJECT_NAME}_vault-data"
docker volume rm "${PROJECT_NAME}_vault-logs" 2>/dev/null && echo "  ✓ Removed ${PROJECT_NAME}_vault-logs" || echo "  ⚠ Could not remove ${PROJECT_NAME}_vault-logs"

# If volumes still exist, try prune
if docker volume ls | grep -q "${PROJECT_NAME}_vault"; then
  echo
  echo "  Volumes still exist. Attempting aggressive cleanup..."
  docker volume prune -f 2>/dev/null || true

  # Check again
  if docker volume ls | grep -q "${PROJECT_NAME}_vault"; then
    echo
    echo "  WARNING: Could not remove all volumes"
    echo "  Try this command manually:"
    echo
    echo "    docker volume ls | grep vault"
    echo "    docker volume rm <volume-name>"
    echo
  else
    echo "  ✓ Volumes removed with prune"
  fi
fi

# ────────────────────────────────────────────────────────────────────────────
# Remove init file
# ────────────────────────────────────────────────────────────────────────────

echo
echo "Step 3: Removing vault-init.json..."

INIT_FILE="${SCRIPT_DIR}/server/init/vault-init.json"
rm -f "$INIT_FILE"
echo "  ✓ Removed init file"

# ────────────────────────────────────────────────────────────────────────────
# Verify cleanup
# ────────────────────────────────────────────────────────────────────────────

echo
echo "Step 4: Verifying cleanup..."

VAULT_CONTAINER=$(docker ps -a --filter "name=vault" --quiet)
VAULT_VOLUMES=$(docker volume ls | grep -c "${PROJECT_NAME}_vault" || true)

if [ -z "$VAULT_CONTAINER" ]; then
  echo "  ✓ No vault container found"
else
  echo "  ⚠ vault container still exists (ID: $VAULT_CONTAINER)"
fi

if [ "$VAULT_VOLUMES" -eq 0 ]; then
  echo "  ✓ No vault volumes found"
else
  echo "  ⚠ $VAULT_VOLUMES vault volumes still exist"
  echo
  echo "  Force remove them:"
  docker volume ls | grep "${PROJECT_NAME}_vault" | awk '{print $2}' | while read vol; do
    echo "    docker volume rm -f $vol"
  done
fi

if [ ! -f "$INIT_FILE" ]; then
  echo "  ✓ vault-init.json removed"
else
  echo "  ⚠ vault-init.json still exists"
fi

# ────────────────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────────────────

echo
header "Cleanup Complete"

echo "Next: start fresh"
echo "  ./start-vault.sh"
echo
