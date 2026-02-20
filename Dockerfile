# Stage 1: Build studio web app
FROM node:20-slim AS studio-builder
WORKDIR /studio
COPY studio/ ./
RUN npm ci && npm run build

# Stage 2: Build SQLite with snapshot support (Ubuntu's default build lacks it)
FROM ubuntu:24.04 AS sqlite-builder
RUN apt-get update && apt-get install -y --no-install-recommends build-essential wget ca-certificates && rm -rf /var/lib/apt/lists/*
RUN wget -q https://www.sqlite.org/2024/sqlite-autoconf-3450100.tar.gz && \
    tar xzf sqlite-autoconf-3450100.tar.gz && \
    cd sqlite-autoconf-3450100 && \
    CFLAGS="-DSQLITE_ENABLE_SNAPSHOT -O2" ./configure --prefix=/usr/local && \
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
RUN PKG_CONFIG_PATH=/usr/local/lib/pkgconfig swift build -c release

# Stage 4: Runtime
FROM ubuntu:24.04
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
