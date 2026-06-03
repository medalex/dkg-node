# DKG Local — OriginTrail v8 in Docker

Single-container local DKG network for development and research reproducibility.
Runs 5 ot-nodes (ports 8900–8904), Hardhat (8545, 9545), Blazegraph (9999), and
MySQL — all inside one `linux/amd64` container.

NestJS connects to **http://localhost:8900** only.

---

## Quick start

```bash
cd dkg-local
docker compose up --build
```

First build downloads ot-node and blazegraph.jar (~5–10 min).  
Subsequent starts use the cached image and are ready in ~3–5 min.

Wait for this line in the logs before connecting:

```
[entrypoint]  DKG local network is ready!
```

---

## Verify

```bash
curl http://localhost:8900/info
```

Expected response (structure, values may differ):

```json
{
  "nodeId": "...",
  "version": "...",
  "auto_update": false
}
```

---

## Exposed ports

| Port | What |
|---|---|
| `8900` | DKG bootstrap node HTTP API (NestJS connects here) |
| `8545` | Hardhat JSON-RPC (dkg.js SDK connects here for signing txs) |

## Connect from NestJS

Install the SDK:

```bash
npm install dkg.js
```

Minimal config pointing at the local node:

```ts
import DKG from 'dkg.js';

const dkg = new DKG({
  environment: 'development',
  endpoint:    'http://localhost',
  port:        8900,
  blockchain: {
    name:         'hardhat1:31337',
    publicKey:    '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    privateKey:   '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
    rpcEndpoints: ['http://localhost:8545'],
  },
});
```

> These are Hardhat's deterministic account #0 keys — safe for local use only.

---

## Troubleshooting

### Logs

All logs are written to `./logs/` on the host:

| File | What |
|---|---|
| `ot-node-0.log` | Bootstrap node (port 8900) |
| `ot-node-1..4.log` | Peer nodes |
| `hardhat1.log` | Hardhat + contract deploy (port 8545) |
| `hardhat2.log` | Hardhat (port 9545) |
| `blazegraph.log` | Triple store |
| `mysql-error.log` | MySQL startup errors |
| `generate-config.log` | Config generation output |

### Container exits immediately

```bash
docker compose logs otnode | tail -50
```

If you see `ERROR: X not ready after Ys` — one of the services didn't start.
Most common cause: `mem_limit: 8g` is tight. Increase it in `docker-compose.yml`
or reduce the Blazegraph heap in `entrypoint.sh` (`-Xmx2g` → `-Xmx1g`).

### Port 8900 refuses connection after startup

Check if ot-node-0 panicked:

```bash
tail -50 logs/ot-node-0.log
```

If you see `ECONNREFUSED` to MySQL or Blazegraph, the cleanup step in
`generate-config-files.js` may have failed. Delete `./logs/`, restart:

```bash
docker compose down && rm -rf logs && docker compose up
```

### sha256sum mismatch for blazegraph.jar

Get the correct hash and update `Dockerfile.otnode`:

```bash
wget -O /tmp/bg.jar \
  https://github.com/blazegraph/database/releases/download/BLAZEGRAPH_2_1_6_RC/blazegraph.jar
sha256sum /tmp/bg.jar
# paste output into ARG BLAZEGRAPH_SHA256=... in Dockerfile.otnode
```

### Mac M-series (Apple Silicon)

The image is `linux/amd64`, which runs under Rosetta on ARM Macs.
Docker Desktop must have **"Use Rosetta for x86/amd64 emulation"** enabled
(Settings → Features in development).

Startup is 2–3× slower than on native x86. This is expected.

### "Operation not permitted" on mysqld_safe

If MySQL fails to start, try adding to `docker-compose.yml`:

```yaml
    cap_add:
      - SYS_NICE
```

---

## Reproducing for a paper

### What to commit

```
dkg-local/
├── Dockerfile.otnode   # pins node:20.11.0-bookworm, OTNODE_SHA, BLAZEGRAPH_SHA256
├── entrypoint.sh
├── docker-compose.yml
├── .dockerignore
└── examples/publish-test.ts
```

Do **not** commit `logs/` or any generated `.node*_origintrail_noderc.json` files.

### Pinned versions (as of this setup)

| Component | Version / SHA |
|---|---|
| ot-node | `a8156d63` (branch `v8/develop`) |
| Base image | `node:20.11.0-bookworm` |
| Blazegraph | `2.1.6-RC` |
| Platform | `linux/amd64` |

To verify the image is deterministic:

```bash
docker build --no-cache -t dkg-local-verify -f Dockerfile.otnode .
docker run --rm dkg-local-verify node -e \
  "import('/opt/ot-node/package.json', {assert:{type:'json'}}).then(m=>console.log(m.default.version))"
```

### Freezing the exact image for reviewers

```bash
docker build -t dkg-local:paper .
docker save dkg-local:paper | gzip > dkg-local-paper.tar.gz
# include dkg-local-paper.tar.gz in supplementary material
# reviewers load it with: docker load < dkg-local-paper.tar.gz
```
