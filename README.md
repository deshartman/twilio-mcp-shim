# twilio-mcp-shim

A **Twilio-authored** MCP shim. It runs the Twilio MCP server (`send_sms`,
`lookup_phone_number`, `list_recent`) and dials the AgenticProcedure
controller via the `@mcp-shim/connector` binary.

This is the deployment shape Twilio runs in production. The customer's
connector — which advertises customer-authored MCPs — runs separately, in
the customer's environment, from the [`mcp-shim`](../mcp-shim/) project.

The two registered connectors show up on the controller distinguished by
the hidden `author` flag: this one has `author: 'twilio'`, so its tools
land as `twilio.send_sms` etc.; the customer connector has `author`
absent, so its tools land as `customer.*`.

## Layout

```
package.json              depends on @mcp-shim/connector + twilio + zod
connector.yaml.example    one mcp_server entry pointing at mcp/twilio-mcp-server
.env.example              CONTROLLER_URL, TUNNEL_AUTH_TOKEN, INSPECTOR_PORT=9091
scripts/start.sh          boots the connector binary against this project's yaml
mcp/twilio-mcp-server/    the actual Twilio MCP server (server.ts + tools/)
  server.ts
  twilio-client.ts
  tools/{send-sms,lookup-phone-number,list-recent}.ts
  .env.example            TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, etc.
```

## Quick start (dev — alongside a sibling `mcp-shim` checkout)

```bash
# 1. Build the connector once.
cd ../mcp-shim
npm install
npm run build

# 2. Install this shim. The "@mcp-shim/connector": "file:..." dependency
#    creates a symlink into ../mcp-shim/packages/connector — edits to the
#    connector source flow through (after rebuild) without re-installing.
cd ../twilio-mcp-shim
npm install

# 3. Configure.
cp connector.yaml.example connector.yaml
cp .env.example .env
# edit .env: CONTROLLER_URL, TUNNEL_AUTH_TOKEN
cp mcp/twilio-mcp-server/.env.example mcp/twilio-mcp-server/.env
# edit: TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN

# 4. Run.
./scripts/start.sh
```

Inspector at <http://localhost:9091/> (the customer connector defaults
to 9090). Tools appear as `twilio.send_sms` etc. on the controller.

## Marking the connector as Twilio-authored

Connectors auto-register on first connect (no UI step, no curl). The row
the controller mints has `author` NULL, so tools surface as `customer.*`.
For this demo we want `twilio.*`, which requires flipping `author='twilio'`
on the connector row.

There's no production UI for that flip yet — `scripts/mark-as-twilio.sh`
patches the controller's SQLite directly. Demo-only, one-shot:

```bash
# 1. Boot the controller (sibling AgenticProcedure project — pnpm dev).
# 2. Boot this shim once so it auto-registers.
./scripts/start.sh                       # let it register, then Ctrl-C

# 3. Stop the controller (the running process caches the record in memory).
# 4. Flip the flag.
./scripts/mark-as-twilio.sh

# 5. Restart the controller. Then start this shim again.
./scripts/start.sh
```

After the restart, the connector's tools surface as `twilio.send_sms`,
`twilio.lookup_phone_number`, `twilio.list_recent` on the controller.

If your repo layout puts the controller's `data.db` somewhere other than
`../AgenticProcedure/server/data.db`, override:

```bash
CONTROLLER_DB_PATH=/path/to/data.db ./scripts/mark-as-twilio.sh
```

In production this flip would be a Twilio-operator-only UI/API; for the
pre-ship demo, the SQL update is enough.

## Future: published-on-npm posture

Today, `@mcp-shim/connector` is consumed via a `file:` dependency pointing
at the sibling `mcp-shim` checkout. When the connector ships to npm, this
project switches to a registry version pin — a one-line edit:

```diff
 "dependencies": {
-  "@mcp-shim/connector": "file:../mcp-shim/packages/connector",
+  "@mcp-shim/connector": "^0.1.0",
   "twilio": "^5.3.0",
   "zod": "^3.23.8"
 }
```

The import path inside the Twilio MCP code
(`import { createMcpHttpServer } from "@mcp-shim/connector/sdk"`) is
identical in both postures — it resolves through the connector package's
`exports` map either way.

## Why a separate project at all

The connector binary has zero awareness of `author`. Identity is purely
`tunnel.name` plus the controller-issued `registrationToken` (persisted in
`.connector-state.json`). So "Twilio-authored connector" vs
"customer-authored connector" is just two processes with different config
talking to the same controller — the productized story is two separately
deployed projects. This shim is the Twilio side.
