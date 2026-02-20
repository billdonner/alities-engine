# Stage 1: Build studio web app
FROM node:20-slim AS studio-builder
WORKDIR /studio
COPY studio/ ./
RUN npm ci && npm run build

# Stage 2: Build engine
FROM swift:6.0-noble AS builder
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Package.swift Package.resolved ./
COPY Sources/ Sources/
COPY Tests/ Tests/
RUN swift build -c release

# Stage 3: Runtime (use Swift image for runtime libraries)
FROM swift:6.0-noble-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-0 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/.build/release/AlitiesEngine /usr/local/bin/alities-engine
COPY --from=studio-builder /studio/dist /app/public

# Data directory for SQLite
RUN mkdir -p /data
VOLUME /data

EXPOSE 9847

ENTRYPOINT ["alities-engine"]
CMD ["run", "--host", "0.0.0.0", "--port", "9847", "--db", "/data/trivia.db", "--static-dir", "/app/public"]
