# Alities Engine

Trivia content engine — daemon with HTTP API, PostgreSQL storage, and embedded studio web app.

## Stack
- Swift 6.0, macOS 14+
- Swift Package Manager
- PostgreSQL via postgres-nio
- AsyncHTTPClient for provider API calls
- OpenAI GPT-4o-mini for AI question generation and similarity detection
- swift-argument-parser for CLI
- Swift NIO HTTP server for control/API endpoints

## Common Commands
- `swift build` — build debug
- `swift build -c release` — build release
- `cp .build/release/AlitiesEngine ~/bin/alities-engine` — install globally
- `swift run AlitiesEngine run --dry-run` — run daemon without writing
- `swift run AlitiesEngine run --port 9847` — run daemon with HTTP control server
- `swift run AlitiesEngine run --static-dir ~/alities-studio/dist` — serve studio web app from engine
- `swift run AlitiesEngine list-providers` — show available providers
- `swift run AlitiesEngine harvest --categories Comics,Vehicles --count 50` — targeted AI generation
- `swift run AlitiesEngine ctl status` — show running daemon status
- `swift run AlitiesEngine ctl pause` / `resume` / `stop` — control daemon

## Architecture

### CLI Subcommands

| Command | Description |
|---------|-------------|
| `run` | Start daemon with HTTP API and optional studio web app |
| `list-providers` | Show available trivia providers |
| `status` | Show daemon status |
| `harvest` | Request targeted AI generation from running daemon |
| `ctl` | Control running daemon (status/pause/resume/stop/import/categories) |

### Source Layout

```
Sources/AlitiesEngine/
├── AlitiesEngineCLI.swift     # @main entry point
├── Models/
│   ├── TriviaQuestion.swift   # Core question model
│   ├── GameData.swift         # Unified GameDataOutput + Challenge + TopicPicMapping
│   ├── ProfileModels.swift    # RawQuestion, ProfiledQuestion, DataLoader
│   └── Report.swift           # Report generation and rendering
├── Providers/
│   ├── TriviaProvider.swift   # Protocol + errors
│   └── AIGeneratorProvider.swift
├── Services/
│   ├── TriviaGenDaemon.swift  # Main daemon actor
│   ├── PostgresService.swift  # PostgreSQL operations (all data access)
│   ├── GameDataTransformer.swift
│   ├── ControlServer.swift    # NIO HTTP server + static file serving
│   └── SimilarityService.swift
├── Profile/
│   └── CategoryMap.swift      # Category normalization + SF Symbols
└── Commands/
    ├── RunCommand.swift        # Daemon run + list-providers + status
    ├── HarvestCommand.swift    # CLI client for /harvest endpoint
    └── CtlCommand.swift        # CLI client for daemon control
```

### Key Design Decisions

- PostgreSQL is the single data store (no SQLite/GRDB dependency)
- All HTTP API endpoints read/write via PostgresService
- Unified `Challenge` model with custom decoder handles null/missing JSON fields
- `TopicPicMapping` (substring-based) for daemon output; `CategoryMap` (alias-based) for API responses
- Jaccard + AI similarity dedup in PostgreSQL
- HTTP control server on `localhost:9847` (configurable via `--port` and `--host`)
- `--static-dir` serves alities-studio production build as static files (SPA fallback to index.html for extensionless paths)
- Port file written to `/tmp/alities-engine.port` for CLI auto-discovery
- Bearer token auth on destructive POST endpoints via `CONTROL_API_KEY` env var
- CORS headers on all responses for studio web app compatibility
- Daemon supports dual-write mode: `--output-file` with Postgres; falls back to file-only if Postgres unavailable

## Cross-Project Sync

This is a satellite repo of the alities ecosystem:
- Hub: `~/alities` — specs and orchestration
- Studio: `~/alities-studio` — React/TypeScript web app (calls `/status`, `/categories`)
- Mobile: `~/alities-mobile` — SwiftUI iOS game player (calls `/status`, `/categories`, `/gamedata`)

## HTTP API Endpoints

| Endpoint | Auth | Description |
|----------|------|-------------|
| `GET /health` | None | Health check (returns `{"ok": true}`) |
| `GET /status` | None | Daemon status and stats |
| `GET /categories` | None | List categories with counts |
| `GET /gamedata` | None | Full GameDataOutput JSON (challenges for mobile app) |
| `GET /metrics` | None | Quick stats (questions, categories, sources) |
| `POST /harvest` | Bearer | Targeted AI question generation |
| `POST /pause` | Bearer | Pause daemon |
| `POST /resume` | Bearer | Resume daemon |
| `POST /stop` | Bearer | Stop daemon |
| `POST /import` | Bearer | Import JSON questions to PostgreSQL |

## Docker & Deployment

- `Dockerfile` — 3-stage build: `node:20-slim` (studio) → `swift:6.0-noble` (engine) → `ubuntu:24.04` runtime
- Studio static files served from `/app/public` via `--static-dir`
- Before `docker build`, copy studio source: `cp -r ~/alities-studio studio/`
- `fly.toml` — Fly.io deployment config (auto-TLS, persistent volumes)
- Deploy: `flyctl deploy` (requires `flyctl auth login` first)
- Health check: `curl https://bd-alities-engine.fly.dev/health`

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `OPENAI_API_KEY` | — | Required for AI provider |
| `CONTROL_API_KEY` | — | Bearer token for POST endpoints (optional) |
| `DB_HOST` | localhost | PostgreSQL host |
| `DB_PORT` | 5432 | PostgreSQL port |
| `DB_USER` | trivia | PostgreSQL user |
| `DB_PASSWORD` | trivia | PostgreSQL password |
| `DB_NAME` | trivia_db | PostgreSQL database |
