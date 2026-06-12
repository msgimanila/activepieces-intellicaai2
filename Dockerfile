FROM node:24.14.0-bullseye-slim AS base

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Layer 1: Install system binaries (Cached, only runs once)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client python3 g++ build-essential git poppler-utils \
        poppler-data procps locales unzip curl ca-certificates iptables libcap-dev && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen en_US.UTF-8

# Layer 2: Install Bun (Cached)
RUN export ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
      curl -fSL https://github.com/oven-sh/bun/releases/download/bun-v1.3.1/bun-linux-x64-baseline.zip -o bun.zip; \
    elif [ "$ARCH" = "aarch64" ]; then \
      curl -fSL https://github.com/oven-sh/bun/releases/download/bun-v1.3.1/bun-linux-aarch64.zip -o bun.zip; \
    fi && \
    unzip bun.zip && mv bun-*/bun /usr/local/bin/bun && chmod +x /usr/local/bin/bun && rm -rf bun.zip bun-*

# Layer 3: Global packages (Cached)
RUN --mount=type=cache,target=/root/.npm \
    npm install -g --no-fund --no-audit node-gyp npm@11.11.0 pm2@6.0.10

### STAGE 1: Build ###
FROM base AS build
WORKDIR /usr/src/app

# Only copy lockfiles first to preserve Bun's install cache!
COPY .npmrc package.json bun.lock bunfig.toml ./
COPY packages/web/package.json ./packages/web/
COPY packages/server/api/package.json ./packages/server/api/
COPY packages/engine/package.json ./packages/engine/

# REMOVED --no-cache. Enabling cache drops install time from minutes to seconds.
RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install --frozen-lockfile

# Now copy the code
COPY . .

# Speed up build by filtering strictly to what's needed
RUN npx turbo run build --filter=web --filter=@activepieces/engine --filter=api

RUN node -e "\
  const {getMigrations} = require('./packages/server/api/dist/src/app/database/postgres-connection');\
  const names = getMigrations().map(M => new M().name);\
  process.stdout.write(JSON.stringify(names));\
" > packages/server/api/dist/src/migration-manifest.json

### STAGE 2: Run (Ultra Lightweight) ###
FROM base AS run
WORKDIR /usr/src/app

COPY --from=build /usr/src/app/packages/server/api/src/assets/default.cf /usr/local/etc/isolate
COPY docker-entrypoint.sh .
RUN mkdir -p /usr/src/app/dist/packages/engine && chmod +x docker-entrypoint.sh

COPY --from=build /usr/src/app/package.json ./
COPY --from=build /usr/src/app/bun.lock ./
COPY --from=build /usr/src/app/packages ./packages
COPY --from=build /usr/src/app/dist/packages/engine/ ./dist/packages/engine/

# Production dependencies only, using cache
RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install --production

# Inject the compiled UI static assets
COPY --from=build /usr/src/app/dist/packages/web ./dist/packages/web/

LABEL service=activepieces
ENTRYPOINT ["./docker-entrypoint.sh"]
EXPOSE 80
