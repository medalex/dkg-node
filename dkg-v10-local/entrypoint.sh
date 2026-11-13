#!/usr/bin/env bash
# Initializes the node on first start, then (on every start) forces the local settings
# into config.json and runs the daemon in the foreground.
set -euo pipefail

CONFIG="$DKG_HOME/config.json"
mkdir -p "$DKG_HOME"

if [ ! -f "$CONFIG" ]; then
  echo "[entrypoint] first start: dkg init"
  # init asks a few more questions (name, ...); an empty answer takes the default.
  yes "" | dkg init --network testnet --store oxigraph --role edge
fi

echo "[entrypoint] applying local settings to $CONFIG"
node -e '
const fs = require("fs");
const path = process.argv[1];
const config = JSON.parse(fs.readFileSync(path, "utf8"));
Object.assign(config, {
  chain: { type: "mock", chainId: "mock:31337", mockIdentityId: 1 },
  relay: "none",
  autoUpdate: { ...(config.autoUpdate ?? {}), enabled: false, source: "npm" },
  apiHost: "0.0.0.0", // inside the container; the host only sees the published port
  apiPort: 9200,
  telemetry: { ...(config.telemetry ?? {}), enabled: false },
});
fs.writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
' "$CONFIG"

echo "[entrypoint] starting dkg $(dkg --version 2>/dev/null || true)"
exec dkg start --foreground
