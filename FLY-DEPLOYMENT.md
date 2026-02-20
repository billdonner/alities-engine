# Fly.io Deployment Guide — Alities Engine

## Infrastructure Overview

| App | URL | Purpose | Machines | Region |
|-----|-----|---------|----------|--------|
| `bd-alities-engine` | `bd-alities-engine.fly.dev` | Swift daemon + studio web app | 1 | ewr |
| `bd-nagzerver` | `bd-nagzerver.fly.dev` | Python API server (nagz) | 2 (1 standby) | ewr |
| `bd-obo-server` | `bd-obo-server.fly.dev` | Python API server (OBO) | 2 (1 standby) | ewr |
| `bd-server-monitor` | `bd-server-monitor.fly.dev` | Dashboard (FastAPI) | 2 (1 standby) | ewr |
| `bd-postgres` | internal only | Shared PostgreSQL | 1 | ewr |

## flyctl Location

```bash
# flyctl is NOT in the default PATH
~/.fly/bin/flyctl

# Add to PATH in ~/.zshrc if desired:
export PATH="$HOME/.fly/bin:$PATH"
```

## Quick Reference

```bash
# Deploy (from project root with fly.toml)
~/.fly/bin/flyctl deploy --remote-only

# Check status
~/.fly/bin/flyctl status -a bd-alities-engine

# View logs
~/.fly/bin/flyctl logs -a bd-alities-engine

# SSH into running machine
~/.fly/bin/flyctl ssh console -a bd-alities-engine

# List all apps
~/.fly/bin/flyctl apps list

# Set secrets (restarts machines)
~/.fly/bin/flyctl secrets set KEY=value -a bd-alities-engine

# List secrets
~/.fly/bin/flyctl secrets list -a bd-alities-engine
```

## Shared PostgreSQL (`bd-postgres`)

Single Postgres instance shared by all apps via Fly internal networking.

- **Internal hostname**: `bd-postgres.internal`
- **Port**: 5432
- **Volume**: `vol_4y5l623125kl9ejr` (1GB, encrypted, ewr)

### Databases & Users

| Database | User | Used By |
|----------|------|---------|
| `alities` | `alities_user` | bd-alities-engine |
| `nagz_db` | *(check secrets)* | bd-nagzerver |
| `obo_db` | *(check secrets)* | bd-obo-server |

### Connecting via psql

```bash
# SSH into the postgres machine
~/.fly/bin/flyctl ssh console -a bd-postgres

# Then inside the machine:
psql -U postgres

# Or connect from another Fly app (internal network):
psql postgresql://alities_user:PASSWORD@bd-postgres.internal:5432/alities
```

### Alities Schema

```sql
CREATE TYPE source_type AS ENUM ('ai_generated', 'imported', 'api');
CREATE TYPE difficulty AS ENUM ('easy', 'medium', 'hard');

CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE question_sources (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    source_type source_type NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE questions (
    id SERIAL PRIMARY KEY,
    question TEXT NOT NULL,
    correct_answer TEXT NOT NULL,
    incorrect_answers TEXT[] NOT NULL,
    category_id INT REFERENCES categories(id),
    difficulty difficulty NOT NULL DEFAULT 'medium',
    hint TEXT,
    source_id INT REFERENCES question_sources(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

## Alities Engine Deployment

### Environment Variables (Fly Secrets)

| Secret | Value | Purpose |
|--------|-------|---------|
| `DB_HOST` | `bd-postgres.internal` | Postgres on Fly internal network |
| `DB_PORT` | `5432` | Postgres port |
| `DB_USER` | `alities_user` | Postgres user |
| `DB_PASSWORD` | *(set via secrets)* | Postgres password |
| `DB_NAME` | `alities` | Postgres database |

### Docker Build (3-stage)

1. **`node:20-slim`** — Builds alities-studio (`npm ci && npm run build`)
2. **`swift:6.0-noble`** — Builds Swift engine (`swift build -c release --static-swift-stdlib`)
3. **`ubuntu:24.04`** — Runtime with `ca-certificates` + `libcurl4`

### fly.toml

```toml
app = "bd-alities-engine"
primary_region = "ewr"

[build]

[env]
  PORT = "9847"

[http_service]
  internal_port = 9847
  force_https = true
  auto_stop_machines = false
  auto_start_machines = true
  min_machines_running = 1

[[http_service.checks]]
  grace_period = "30s"
  interval = "30s"
  method = "GET"
  timeout = "5s"
  path = "/health"
```

### Deploy Steps

```bash
cd ~/alities-engine

# 1. Copy studio source into engine build context
cp -r ~/alities-studio studio/

# 2. Deploy (builds on Fly.io remote builder)
~/.fly/bin/flyctl deploy --remote-only

# 3. Verify
curl https://bd-alities-engine.fly.dev/health
# → {"ok":true}

curl https://bd-alities-engine.fly.dev/status
# → daemon status JSON

# Studio UI at root:
open https://bd-alities-engine.fly.dev
```

### IPs

| Version | IP | Type |
|---------|-----|------|
| v4 | `66.241.125.146` | Public (shared) |
| v6 | `2a09:8280:1::d6:9c56:0` | Public (dedicated) |

## Lessons Learned (Operational Gotchas)

### 1. `--static-swift-stdlib` still needs `libcurl4`

`swift build -c release --static-swift-stdlib` statically links the Swift stdlib, but Foundation on Linux dynamically links libcurl. The runtime image must include:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*
```

Without `libcurl4`, the binary crashes at startup:
```
alities-engine: error while loading shared libraries: libcurl.so.4: cannot open shared object file
```

### 2. Volume mismatch blocks deploys

If `fly.toml` previously had `[mounts]` and you remove it, existing machines with attached volumes will fail to deploy. The error says "yes flag must be specified" but `--yes` doesn't help.

**Fix:**
```bash
# 1. Destroy the machine (force if lease is held)
~/.fly/bin/flyctl machines destroy MACHINE_ID --force -a APP_NAME

# 2. Destroy the orphaned volume
~/.fly/bin/flyctl volumes destroy VOL_ID -a APP_NAME

# 3. Deploy fresh (creates new machine without volume)
~/.fly/bin/flyctl deploy --remote-only
```

### 3. Machine lease conflicts

Multiple failed deploys can leave active leases on machines, blocking subsequent operations ("lease already held").

**Fix:**
```bash
~/.fly/bin/flyctl machines leases clear MACHINE_ID -a APP_NAME
```

### 4. Why some apps have 2 machines

Fly.io creates a **standby machine** by default for high availability. One machine is `started`, the other is `stopped`. The standby auto-starts if the primary fails. For hobby projects, scale down:

```bash
~/.fly/bin/flyctl scale count 1 --yes -a APP_NAME
```

The alities-engine is scaled to 1. Others (nagzerver, obo-server, server-monitor) still have 2 each.

### 5. Secrets are "staged" until deploy

`flyctl secrets set` stages secrets immediately but they only take effect when machines restart. If no machines exist yet, the secrets deploy with the first `flyctl deploy`.

### 6. DNS propagation delay

After first deploy, `<app>.fly.dev` may not resolve immediately via local DNS. Test with:

```bash
curl --resolve bd-alities-engine.fly.dev:443:66.241.125.146 \
  https://bd-alities-engine.fly.dev/health
```

DNS usually resolves within 5-10 minutes.

### 7. Graceful DB failure is essential

The engine starts even if PostgreSQL is unreachable. This is critical because:
- Health checks must pass for Fly to consider the machine healthy
- `/health` returns `{"ok": true}` regardless of DB state
- Static file serving (studio) works without DB
- DB connects asynchronously; the app logs a warning and continues

### 8. Internal networking for Postgres

Fly apps on the same org can reach each other via `<app-name>.internal`. Postgres at `bd-postgres.internal:5432` — no public exposure needed. This only works from within Fly machines, not from your local dev machine.

### 9. Docker layer caching

Separate `swift package resolve` before `COPY Sources/` for better caching:

```dockerfile
COPY Package.swift Package.resolved ./
RUN swift package resolve        # cached unless Package.swift changes
COPY Sources/ Sources/
COPY Tests/ Tests/
RUN swift build -c release --static-swift-stdlib
```

### 10. Swift builds are slow on Fly builders

A clean Swift build on Fly's remote builder takes 5-10 minutes. The `swift package resolve` caching helps on subsequent deploys where only source files changed.

## Scaling & Cost

- **Free tier**: 3 shared-cpu-1x machines (256MB RAM each)
- Current usage: 5 apps, ~6 machines total (could reduce to 5 with scale-down)
- Postgres volume: 1GB (plenty for trivia data)
- Remote builder: `fly-builder-lingering-violet-3261` (auto-suspended when idle)

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `flyctl: command not found` | Not in PATH | Use `~/.fly/bin/flyctl` |
| Deploy hangs on "Waiting for lease" | Stale lease from failed deploy | `flyctl machines leases clear ID` |
| "yes flag must be specified" | Volume mismatch | Destroy machine + volume, redeploy |
| `libcurl.so.4: cannot open` | Missing runtime dependency | Add `libcurl4` to Dockerfile |
| Health check failing | App crashing at startup | Check `flyctl logs`; ensure graceful DB failure |
| Can't reach `.fly.dev` | DNS propagation | Wait or use `--resolve` flag |
| Secrets not taking effect | Staged but not deployed | Redeploy or `flyctl secrets deploy` |
