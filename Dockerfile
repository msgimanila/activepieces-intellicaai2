FROM node:24.14.0-bullseye-slim AS base

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        python3 \
        g++ \
        build-essential \
        git \
        poppler-utils \
        poppler-data \
        procps \
        locales \
        unzip \
        curl \
        ca-certificates \
        iptables \
        libcap-dev && \
    yarn config set python /usr/bin/python3 && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen en_US.UTF-8

RUN export ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
      curl -fSL https://github.com/oven-sh/bun/releases/download/bun-v1.3.1/bun-linux-x64-baseline.zip -o bun.zip; \
    elif [ "$ARCH" = "aarch64" ]; then \
      curl -fSL https://github.com/oven-sh/bun/releases/download/bun-v1.3.1/bun-linux-aarch64.zip -o bun.zip; \
    fi

RUN unzip bun.zip \
    && mv bun-*/bun /usr/local/bin/bun \
    && chmod +x /usr/local/bin/bun \
    && rm -rf bun.zip bun-*

RUN bun --version

RUN --mount=type=cache,target=/root/.npm \
    npm install -g --no-fund --no-audit \
    node-gyp \
    npm@11.11.0 \
    pm2@6.0.10 \
    typescript@4.9.4 \
    esbuild@0.25.0

# ✅ FIXED: Removed the standalone cache layer for isolated-vm. 
# It will be installed cleanly inside the monorepo context.

### STAGE 1: Build ###
FROM base AS build

WORKDIR /usr/src/app

COPY .npmrc package.json bun.lock bunfig.toml ./
COPY packages/ ./packages/

# ✅ FIXED: Added --no-cache flag to break the corrupted cache loop for this run
RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install --frozen-lockfile --no-cache

COPY . .



RUN node -e "\
  const {getMigrations} = require('./packages/server/api/dist/src/app/database/postgres-connection');\
  const names = getMigrations().map(M => new M().name);\
  process.stdout.write(JSON.stringify(names));\
" > packages/server/api/dist/src/migration-manifest.json

RUN rm -rf packages/pieces/core packages/pieces/custom && \
    find packages/pieces/community -mindepth 1 -maxdepth 1 -type d \
      ! -name slack \
      ! -name square \
      ! -name facebook-leads \
      ! -name intercom \
      -exec rm -rf {} + && \
    rm -f bun.lock && bun install --no-cache

### STAGE 2: Run ###
FROM base AS run

WORKDIR /usr/src/app

COPY --from=build /usr/src/app/packages/server/api/src/assets/default.cf /usr/local/etc/isolate
COPY docker-entrypoint.sh .

RUN mkdir -p \
    /usr/src/app/dist/packages/engine && \
    chmod +x docker-entrypoint.sh

COPY --from=build /usr/src/app/package.json ./
COPY --from=build /usr/src/app/.npmrc ./
COPY --from=build /usr/src/app/bun.lock ./
COPY --from=build /usr/src/app/bunfig.toml ./
COPY --from=build /usr/src/app/LICENSE .

COPY --from=build /usr/src/app/packages ./packages
COPY --from=build /usr/src/app/dist/packages/engine/ ./dist/packages/engine/

RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install --production --no-cache

COPY --from=build /usr/src/app/dist/packages/web ./dist/packages/web/

LABEL service=activepieces

ENTRYPOINT ["./docker-entrypoint.sh"]
EXPOSE 80
