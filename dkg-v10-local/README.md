# DKG V10 Local — OriginTrail DKG V10 in Docker (mock chain)

Single local OriginTrail DKG V10 node (`@origintrail-official/dkg@10.0.27`) for development of
the MFSSIA migration from DKG v8. It runs without a blockchain: the chain is mocked, so
Working Memory (context graphs, knowledge assets, SPARQL) works, but publishing to
Verifiable Memory does not.

The v8 network in `../dkg-local` is unchanged and can run next to it (ports 8900/8545 there,
9200 here).

---

## Quick start

```bash
cd dkg-v10-local
docker compose up --build -d
```

On the first start the entrypoint runs
`dkg init --network testnet --store oxigraph --role edge` with default answers, then writes
the local settings into `config.json` (on every start):

```json
"chain": {"type": "mock", "chainId": "mock:31337", "mockIdentityId": 1},
"relay": "none",
"autoUpdate": {"enabled": false, "source": "npm"},
"apiHost": "0.0.0.0",
"apiPort": 9200,
"telemetry": {"enabled": false},
"rateLimit": {"requestsPerMinute": 6000}
```

Requests reach the node from the Docker gateway rather than loopback, so the node's per-IP
API limit (default 120 requests/min) applies to MFSSIA, which sends several SPARQL queries per
evidence lookup; at the default a pilot smoke run already gets HTTP 429.

`dkg init` itself also asks the public testnet faucet for tokens for the generated wallets.
They are not used in mock mode.

The node home (`config.json`, `auth.token`, keys, oxigraph store) is `./data`, mounted
into the container as `/data/dkg`. It is git-ignored. To start from scratch:

```bash
docker compose down && rm -rf data
```

---

## Verify

```bash
curl http://localhost:9200/api/status
```

---

## API

Base URL `http://localhost:9200`, header `Authorization: Bearer <token>`:

```bash
# auth.token starts with a "# ..." comment line; the token is the last line
TOKEN=$(grep -v "^#" data/auth.token | tr -d "[:space:]")
curl -H "Authorization: Bearer $TOKEN" http://localhost:9200/api/status
```

| Method | Path | Body |
|---|---|---|
| `POST` | `/api/context-graph/create` | `{id, name, description}` |
| `POST` | `/api/knowledge-assets` | `{contextGraphId, name, quads, finalize: false}` |
| `GET` | `/api/knowledge-assets/{name}?contextGraphId=...` | — |
| `POST` | `/api/query` | `{sparql, contextGraphId, view: "working-memory"}` |
| `GET` | `/api/status` | — |

## Exposed ports

| Port | What |
|---|---|
| `9200` | DKG V10 node HTTP API |
