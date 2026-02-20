# Stage 1: Build studio web app
FROM node:20-slim AS studio-builder
WORKDIR /studio
COPY studio/ ./
RUN npm ci && npm run build

# Stage 2: Build engine
FROM swift:6.0-noble AS builder
WORKDIR /app
COPY Package.swift Package.resolved ./
COPY Sources/ Sources/
COPY Tests/ Tests/
RUN swift build -c release

# Stage 3: Runtime
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/.build/release/AlitiesEngine /usr/local/bin/alities-engine
COPY --from=studio-builder /studio/dist /app/public

EXPOSE 9847

ENTRYPOINT ["alities-engine"]
CMD ["run", "--host", "0.0.0.0", "--port", "9847", "--static-dir", "/app/public"]
