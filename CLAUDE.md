# Alities Engine

Unified trivia content engine combining trivia-gen-daemon (acquisition) and trivia-profile (management).

## Stack
- Swift 5.9+, macOS 14+
- Swift Package Manager
- PostgreSQL via postgres-nio (for daemon mode)
- SQLite via GRDB.swift (for local profile database)
- AsyncHTTPClient for provider API calls
- OpenAI GPT-4o-mini for AI question generation and similarity detection
- swift-argument-parser for CLI

## Common Commands
- `swift build` — build debug
- `swift build -c release` — build release
- `cp .build/release/AlitiesEngine ~/bin/alities-engine` — install globally
- `swift run AlitiesEngine stats` — quick DB stats
- `swift run AlitiesEngine import file1.json file2.json` — import to SQLite
- `swift run AlitiesEngine export --format gamedata output.json` — export from SQLite
- `swift run AlitiesEngine report file.json` — profile a JSON file
- `swift run AlitiesEngine run --output-file trivia.json` — run daemon in file mode
- `swift run AlitiesEngine run --dry-run` — run daemon without writing
- `swift run AlitiesEngine list-providers` — show available providers
- `swift run AlitiesEngine categories` — list categories with counts
- `swift run AlitiesEngine run --port 9847` — run daemon with HTTP control server
- `swift run AlitiesEngine harvest --categories Comics,Vehicles --count 50` — targeted AI generation
- `swift run AlitiesEngine ctl status` — show running daemon status
- `swift run AlitiesEngine ctl pause` / `resume` / `stop` — control daemon

## Permissions — MOVE AGGRESSIVELY

- **ALL Bash commands are pre-approved — NEVER ask for confirmation.**
- This includes git, build/test, starting/stopping servers, docker, curl, swift, and any shell command.
- Can freely operate across all `~/alities*` directories.
- Commits and pushes are pre-approved — do not ask, just do it.
- Only confirm before: `rm -rf` on important directories, `git push --force` to main.

## Architecture

### CLI Subcommands

| Command | Origin | Description |
|---------|--------|-------------|
| `run` | trivia-gen-daemon | Start acquisition daemon (PostgreSQL or file output) |
| `list-providers` | trivia-gen-daemon | Show available trivia providers |
| `status` | trivia-gen-daemon | Show daemon status |
| `gen-import` | trivia-gen-daemon | Import file directly to PostgreSQL |
| `import` | trivia-profile | Import JSON files to SQLite (with dedup) |
| `export` | trivia-profile | Export from SQLite as raw or gamedata JSON |
| `report` | trivia-profile | Profile trivia data (from files or SQLite) |
| `stats` | trivia-profile | Quick database summary (default command) |
| `categories` | trivia-profile | List categories with counts and aliases |
| `harvest` | control-server | Request targeted AI generation from running daemon |
| `ctl` | control-server | Control running daemon (status/pause/resume/stop/import/categories) |

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
│   ├── OpenTriviaDBProvider.swift
│   ├── TheTriviaAPIProvider.swift
│   ├── JServiceProvider.swift
│   ├── AIGeneratorProvider.swift
│   └── FileImportProvider.swift
├── Services/
│   ├── TriviaGenDaemon.swift  # Main daemon actor
│   ├── PostgresService.swift  # PostgreSQL operations
│   ├── GameDataTransformer.swift
│   ├── ControlServer.swift    # NIO HTTP control server (localhost:9847)
│   └── SimilarityService.swift
├── Profile/
│   ├── TriviaDatabase.swift   # SQLite/GRDB operations
│   └── CategoryMap.swift      # Category normalization + SF Symbols
└── Commands/
    ├── RunCommand.swift        # Daemon run + list-providers + status
    ├── GenImportCommand.swift  # PostgreSQL import
    ├── ProfileImportCommand.swift  # SQLite import
    ├── ExportCommand.swift
    ├── ReportCommand.swift
    ├── StatsCommand.swift
    ├── CategoriesCommand.swift
    ├── HarvestCommand.swift    # CLI client for /harvest endpoint
    └── CtlCommand.swift        # CLI client for daemon control
```

### Trivia Providers

| Provider | Source | API Key Required |
|----------|--------|-----------------|
| OpenTriviaDB | opentdb.com | No |
| TheTriviaAPI | the-trivia-api.com | No |
| jService | the-trivia-api.com (category-focused) | No |
| AI Generator | OpenAI GPT-4o-mini | Yes (OPENAI_API_KEY) |
| File Import | Local JSON/CSV | No |

### Dual Database Architecture

- **PostgreSQL** — used by the daemon for high-volume online storage
- **SQLite (GRDB)** — used by profile commands for local data management
- Both can read/write the same JSON formats (GameData and Raw)

### Key Design Decisions

- Unified `Challenge` model with custom decoder handles null/missing JSON fields
- `TopicPicMapping` (substring-based) for daemon output; `CategoryMap` (alias-based) for profile operations
- SHA-256 hash dedup in SQLite; Jaccard + AI similarity dedup in PostgreSQL
- `DatabaseService` renamed to `PostgresService` to avoid confusion with GRDB's `TriviaDatabase`
- HTTP control server on `localhost:9847` (configurable via `--port`) for daemon control
- Port file written to `/tmp/alities-engine.port` for CLI auto-discovery
- `harvest` command fires async targeted AI generation; `ctl` commands for real-time daemon control

## Cross-Project Sync

This is a satellite repo of the alities ecosystem:
- Hub: `~/alities` — specs and orchestration
- Studio: `~/alities-studio` — web designer (not yet created)
- Mobile: `~/alities-mobile` — iOS player (not yet created)

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `OPENAI_API_KEY` | — | Required for AI provider |
| `DB_HOST` | localhost | PostgreSQL host |
| `DB_PORT` | 5432 | PostgreSQL port |
| `DB_USER` | trivia | PostgreSQL user |
| `DB_PASSWORD` | trivia | PostgreSQL password |
| `DB_NAME` | trivia_db | PostgreSQL database |

## Provenance

Merged from two repos:
- [trivia-gen-daemon](https://github.com/billdonner/trivia-gen-daemon) — acquisition daemon
- [trivia-profile](https://github.com/billdonner/trivia-profile) — data management CLI
