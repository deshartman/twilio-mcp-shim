#!/usr/bin/env bash
# Boots the Twilio MCP shim. Same connector binary as @mcp-shim/connector,
# pointed at this project's connector.yaml. Identity (tunnel.name) and the
# persisted registrationToken bind this process to its own controller-side
# connector row — separate from any customer connector running alongside.
#
# To run alongside the customer connector, set INSPECTOR_PORT (e.g. 9091)
# and optionally MCP_BASE_PORT (e.g. 7200) in .env.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

cleanup() {
  echo
  echo "[start] shutting down..."
  kill 0 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Kill any prior runs of THIS script. Match the script's filename to avoid
# touching unrelated node processes.
echo "[start] cleaning up any prior runs of this script..."
SELF_PID=$$
for pid in $(pgrep -f 'twilio-mcp-shim/scripts/start\.sh' 2>/dev/null); do
  [ "$pid" = "$SELF_PID" ] && continue
  echo "  killing prior run pid $pid"
  kill -TERM "$pid" 2>/dev/null || true
done
sleep 1

CONNECTOR_BIN="$ROOT/node_modules/@mcp-shim/connector/dist/index.js"
ENV_FILE="$ROOT/.env"
YAML_FILE="$ROOT/connector.yaml"

if [ ! -f "$CONNECTOR_BIN" ]; then
  echo "[start] @mcp-shim/connector not installed or not built." >&2
  echo "        Run: (cd ../mcp-shim && npm install && npm run build) && npm install" >&2
  exit 1
fi
if [ ! -f "$ENV_FILE" ]; then
  echo "[start] no $ENV_FILE — copy .env.example and edit" >&2
  exit 1
fi
if [ ! -f "$YAML_FILE" ]; then
  echo "[start] no $YAML_FILE — copy connector.yaml.example and edit" >&2
  exit 1
fi

# Source .env so CONTROLLER_URL / TUNNEL_AUTH_TOKEN are visible to yaml
# interpolation. Per-MCP creds (TWILIO_*) are loaded by the connector itself
# from mcp/twilio-mcp-server/.env into that child's process only.
echo "[start] sourcing $ENV_FILE"
set -a; source "$ENV_FILE"; set +a

# Persist the connector state file in this project's root, not the
# upstream connector package's directory (which doesn't exist here).
export CONNECTOR_STATE_PATH="$ROOT/.connector-state.json"

echo "[start] starting connector with CONNECTOR_CONFIG=$YAML_FILE"
CONNECTOR_CONFIG="$YAML_FILE" node "$CONNECTOR_BIN" start &

echo
echo "[start] running. Ctrl-C to stop."
wait
