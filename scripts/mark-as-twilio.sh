#!/usr/bin/env bash
# One-off demo helper. Flips the controller's `connectors.author` column to
# 'twilio' for the row whose name matches this shim's tunnel.name.
#
# Why this exists: connectors auto-register on first connect (mints a row
# keyed by tunnel.name with `author` NULL → tools surface as customer.*).
# A Twilio-authored connector should surface as twilio.*, which requires
# author='twilio'. Pre-shipping a UI/API for that flip isn't worth it for
# a demo, so this script just patches the SQLite row directly.
#
# Usage:
#   1. Boot the controller (pnpm dev) once so the row gets created.
#   2. Boot this shim once so it auto-registers (./scripts/start.sh).
#   3. Stop the controller (the running process caches the record in memory;
#      restarting picks up the new author).
#   4. Run this script.
#   5. Restart the controller.
#
# Override the controller's DB path via CONTROLLER_DB_PATH if your repo
# layout differs from the assumed sibling folders.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONNECTOR_NAME="twilio-platform"
DB_PATH="${CONTROLLER_DB_PATH:-$ROOT/../AgenticProcedure/server/data.db}"

if [ ! -f "$DB_PATH" ]; then
  echo "[mark-as-twilio] controller DB not found at $DB_PATH" >&2
  echo "                 Override with CONTROLLER_DB_PATH=/path/to/data.db" >&2
  exit 1
fi

if pgrep -f 'tsx watch src/server.ts' >/dev/null 2>&1; then
  echo "[mark-as-twilio] WARNING: controller appears to be running." >&2
  echo "                 The in-memory record won't pick up the flip until restart." >&2
  echo "                 Stop pnpm dev, run this script, then start it again." >&2
  echo
fi

echo "[mark-as-twilio] db: $DB_PATH"
echo "[mark-as-twilio] target connector name: $CONNECTOR_NAME"

CURRENT="$(sqlite3 "$DB_PATH" "SELECT IFNULL(author, '<null>') FROM connectors WHERE name = '$CONNECTOR_NAME';")"
if [ -z "$CURRENT" ]; then
  echo "[mark-as-twilio] no row with name='$CONNECTOR_NAME'." >&2
  echo "                 Boot the shim once (./scripts/start.sh) so it auto-registers, then re-run." >&2
  exit 1
fi
echo "[mark-as-twilio] current author: $CURRENT"

if [ "$CURRENT" = "twilio" ]; then
  echo "[mark-as-twilio] already 'twilio' — nothing to do."
  exit 0
fi

sqlite3 "$DB_PATH" "UPDATE connectors SET author = 'twilio' WHERE name = '$CONNECTOR_NAME';"
echo "[mark-as-twilio] flipped author → 'twilio'."
echo "[mark-as-twilio] restart the controller for tools to surface as twilio.*"
