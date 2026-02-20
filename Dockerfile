# Stage 1: Build studio web app
FROM node:20-slim AS studio-builder
WORKDIR /studio
COPY studio/ ./
RUN npm ci && npm run build

# Stage 2: Build SQLite with snapshot support (Ubuntu's packaged version lacks it)
FROM ubuntu:24.04 AS sqlite-builder
RUN apt-get update && apt-get install -y --no-install-recommends curl gcc make libc6-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /sqlite
RUN curl -fsSL --retry 3 -o sqlite.tar.gz https://sqlite.org/2024/sqlite-autoconf-3460000.tar.gz && \
    tar xzf sqlite.tar.gz && \
    cd sqlite-autoconf-3460000 && \
    CFLAGS="-DSQLITE_ENABLE_SNAPSHOT -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1 -O2" \
    ./configure --prefix=/usr/local && \
    make -j$(nproc) && make install

# Stage 3: Build engine
FROM swift:6.0-noble AS builder
COPY --from=sqlite-builder /usr/local/lib/libsqlite3* /usr/local/lib/
COPY --from=sqlite-builder /usr/local/include/sqlite3*.h /usr/local/include/
COPY --from=sqlite-builder /usr/local/lib/pkgconfig/sqlite3.pc /usr/local/lib/pkgconfig/
RUN ldconfig
WORKDIR /app
COPY Package.swift Package.resolved ./
COPY Sources/ Sources/
COPY Tests/ Tests/
RUN swift build -c release

# Stage 4: Runtime
FROM swift:6.0-noble-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=sqlite-builder /usr/local/lib/libsqlite3.so* /usr/local/lib/
RUN ldconfig

COPY --from=builder /app/.build/release/AlitiesEngine /usr/local/bin/alities-engine
COPY --from=studio-builder /studio/dist /app/public

# Data directory for SQLite
RUN mkdir -p /data
VOLUME /data

EXPOSE 9847

ENTRYPOINT ["alities-engine"]
CMD ["run", "--host", "0.0.0.0", "--port", "9847", "--db", "/data/trivia.db", "--static-dir", "/app/public"]
