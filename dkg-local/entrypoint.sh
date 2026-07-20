#!/usr/bin/env bash
set -euo pipefail

OTNODE=/opt/ot-node
LOG=/var/log/ot-node
HUB_CONTRACT=0x5FbDB2315678afecb367f032d93F642f64180aa3

# ─── Helpers ─────────────────────────────────────────────────────────────────

wait_port() {
    local name=$1 port=$2 timeout=${3:-120} logfile=${4:-""}
    local elapsed=0
    echo "[entrypoint] Waiting for $name on :$port ..."
    until nc -z localhost "$port" 2>/dev/null; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [[ $elapsed -ge $timeout ]]; then
            echo "[entrypoint] ERROR: $name not ready after ${timeout}s" >&2
            if [[ -n "$logfile" && -f "$logfile" ]]; then
                echo "[entrypoint] Last 40 lines of $logfile:" >&2
                tail -40 "$logfile" >&2
            fi
            exit 1
        fi
    done
    echo "[entrypoint] $name up on :$port"
}

wait_log() {
    local name=$1 logfile=$2 pattern=$3 timeout=${4:-300}
    local elapsed=0
    echo "[entrypoint] Waiting for $name ..."
    until grep -q "$pattern" "$logfile" 2>/dev/null; do
        sleep 2
        elapsed=$((elapsed + 2))
        if [[ $elapsed -ge $timeout ]]; then
            echo "[entrypoint] ERROR: $name not ready after ${timeout}s" >&2
            echo "[entrypoint] Last 30 lines of $logfile:" >&2
            tail -30 "$logfile" >&2
            exit 1
        fi
    done
    echo "[entrypoint] $name ready"
}

# ─── 1. MySQL ─────────────────────────────────────────────────────────────────
# Strategy: start with --skip-grant-tables so we can change root's auth plugin,
# then restart normally. After this root@localhost accepts empty password over TCP.
# This is more reliable than GRANT/ALTER which don't override unix_socket plugin
# in MariaDB 10.11 when the user already exists.
echo "[entrypoint] Starting MySQL (init pass)..."
mkdir -p /var/run/mysqld
chown -R mysql:mysql /var/run/mysqld /var/lib/mysql

mysqld_safe --skip-grant-tables --user=mysql \
    --log-error="$LOG/mysql-error.log" > "$LOG/mysql.log" 2>&1 &
wait_port "MySQL init" 3306 60

mysql -u root <<'SQL'
UPDATE mysql.global_priv
SET priv = JSON_SET(priv,
    '$.plugin', 'mysql_native_password',
    '$.authentication_string', '')
WHERE user = 'root';
FLUSH PRIVILEGES;
SQL

echo "[entrypoint] Restarting MySQL normally..."
mysqladmin -u root shutdown 2>/dev/null || kill "$(cat /var/run/mysqld/mysqld.pid 2>/dev/null)" 2>/dev/null || true
sleep 5

mysqld_safe --user=mysql \
    --log-error="$LOG/mysql-error.log" > "$LOG/mysql.log" 2>&1 &
wait_port "MySQL" 3306 60

echo "[entrypoint] MySQL ready (root@localhost, empty password)"

# ─── 2. Redis ─────────────────────────────────────────────────────────────────
echo "[entrypoint] Starting Redis..."
redis-server --daemonize yes --logfile "$LOG/redis.log"
wait_port "Redis" 6379 30

# ─── 4. Blazegraph ────────────────────────────────────────────────────────────
echo "[entrypoint] Starting Blazegraph..."
cd /opt/blazegraph-data
nohup java -server -Xmx2g -jar /opt/blazegraph.jar \
    > "$LOG/blazegraph.log" 2>&1 &
cd "$OTNODE"

wait_port "Blazegraph" 9999 120

# ─── 3. Hardhat 1 (port 8545) ─────────────────────────────────────────────────
echo "[entrypoint] Starting Hardhat 1 + contract deploy (takes 2-5 min on Rosetta) ..."
cd "$OTNODE"
nohup node "$OTNODE/tools/local-network-setup/run-local-blockchain.js" 8545 \
    > "$LOG/hardhat1.log" 2>&1 &

wait_port "Hardhat1" 8545 600 "$LOG/hardhat1.log"
wait_log "Hardhat1 contracts" "$LOG/hardhat1.log" \
    "Contracts deployed and ready on port 8545" 900

# ─── 4. Hardhat 2 (port 9545) ─────────────────────────────────────────────────
echo "[entrypoint] Starting Hardhat 2 + contract deploy ..."
cd "$OTNODE"
nohup node "$OTNODE/tools/local-network-setup/run-local-blockchain.js" 9545 \
    > "$LOG/hardhat2.log" 2>&1 &

wait_port "Hardhat2" 9545 600 "$LOG/hardhat2.log"
wait_log "Hardhat2 contracts" "$LOG/hardhat2.log" \
    "Contracts deployed and ready on port 9545" 900

# ─── 5. Generate ot-node configs ──────────────────────────────────────────────
echo "[entrypoint] Generating configs for 5 ot-nodes..."
cd "$OTNODE"

cat > "$OTNODE/.env" <<EOF
RPC_ENDPOINT=http://localhost:8545
RPC_ENDPOINT_BC1=http://localhost:8545
RPC_ENDPOINT_BC2=http://localhost:9545
REPOSITORY_PASSWORD=
LOG_LEVEL=warn
ACCESS_KEY=http://localhost:8545
EOF

export RPC_ENDPOINT=http://localhost:8545
export RPC_ENDPOINT_BC1=http://localhost:8545
export RPC_ENDPOINT_BC2=http://localhost:9545
export REPOSITORY_PASSWORD=
export ACCESS_KEY=http://localhost:8545

node tools/local-network-setup/generate-config-files.js \
    5 hardhat1:31337 ot-blazegraph "$HUB_CONTRACT" \
    > "$LOG/generate-config.log" 2>&1 || {
    echo "[entrypoint] WARNING: generate-config-files.js exited non-zero — checking if configs exist..."
    cat "$LOG/generate-config.log"
}

for i in 0 1 2 3 4; do
    cfg="$OTNODE/tools/local-network-setup/.node${i}_origintrail_noderc.json"
    if [[ ! -f "$cfg" ]]; then
        echo "[entrypoint] ERROR: config not created: $cfg" >&2
        exit 1
    fi
done
echo "[entrypoint] All 5 configs generated"

# ─── 6. Patch node configs ────────────────────────────────────────────────────
# Inject full DB credentials so ot-node doesn't fall back to Sequelize defaults.
# Open IP whitelist so NestJS on Docker bridge can connect to port 8900.
# Fix bootstrap address: 0.0.0.0 is a listen address, not dialable — use 127.0.0.1.
echo "[entrypoint] Patching node configs..."
for i in 0 1 2 3 4; do
    cfg="$OTNODE/tools/local-network-setup/.node${i}_origintrail_noderc.json"
    jq '.modules.repository.implementation["sequelize-repository"].config += {
            "user":     "root",
            "password": "",
            "host":     "localhost",
            "port":     "3306",
            "dialect":  "mysql",
            "logging":  false
        } |
        .auth.ipBasedAuthEnabled    = false |
        .auth.tokenBasedAuthEnabled = false' \
        "$cfg" > "${cfg}.tmp" && mv "${cfg}.tmp" "$cfg"
    sed -i 's|/ip4/0\.0\.0\.0/tcp/9100|/ip4/127.0.0.1/tcp/9100|g' "$cfg"
done

# ─── 7. Start 5 ot-nodes ──────────────────────────────────────────────────────
echo "[entrypoint] Starting 5 ot-nodes (ports 8900-8904)..."
for i in 0 1 2 3 4; do
    port=$((8900 + i))
    echo "[entrypoint]   node-$i → :$port"
    nohup node "$OTNODE/index.js" \
        "$OTNODE/tools/local-network-setup/.node${i}_origintrail_noderc.json" \
        > "$LOG/ot-node-$i.log" 2>&1 &
    sleep 2
done

# ─── 8. Wait for bootstrap node (node-0) ──────────────────────────────────────
# Bootstrap ot-node init (MySQL schema + blockchain sync + libp2p) can exceed 5 min
# on this host; a timeout here `exit 1`s the whole entrypoint (set -e) and the
# container restarts from scratch (re-deploying both chains), so keep it generous.
wait_port "ot-node-0 (bootstrap)" 8900 "${BOOTSTRAP_TIMEOUT:-900}"

echo ""
echo "[entrypoint] ══════════════════════════════════════════════════"
echo "[entrypoint]  DKG local network is ready!"
echo "[entrypoint]  Bootstrap node → http://localhost:8900"
echo "[entrypoint]  NestJS config:  endpoint=http://localhost:8900"
echo "[entrypoint] ══════════════════════════════════════════════════"
echo ""

# ─── 9. Keep container alive — stream all logs to stdout ──────────────────────
tail -f \
    "$LOG/ot-node-0.log" \
    "$LOG/ot-node-1.log" \
    "$LOG/ot-node-2.log" \
    "$LOG/ot-node-3.log" \
    "$LOG/ot-node-4.log" \
    "$LOG/blazegraph.log" \
    "$LOG/hardhat1.log" \
    "$LOG/hardhat2.log" \
    "$LOG/redis.log"
