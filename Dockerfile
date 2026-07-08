# OpenWA - Dockerfile
# Multi-stage build for production-ready image

# ===== Stage 1: Builder =====
FROM node:22-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy package files
COPY package*.json ./

# Install all dependencies (including devDependencies for build)
RUN npm ci

# Copy source code
COPY . .

# Build the application
RUN npm run build

# ===== Stage 2: Production =====
FROM node:22-slim AS production

# Install Chrome/Chromium and required dependencies
RUN apt-get update && apt-get install -y \
    chromium \
    fonts-liberation \
    libappindicator3-1 \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    xdg-utils \
    dumb-init \
    && rm -rf /var/lib/apt/lists/*

# Skip puppeteer's browser download during npm ci; we install the matching
# Chrome for Testing explicitly below (modern var name is PUPPETEER_SKIP_DOWNLOAD)
ENV PUPPETEER_SKIP_DOWNLOAD=true
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true

# Create app user for security
RUN groupadd -r openwa && useradd -r -g openwa openwa

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install production dependencies only
RUN npm ci --omit=dev && npm cache clean --force

# Install the Chrome for Testing build that matches the installed puppeteer
# version. Debian's chromium package tracks the latest Chromium (often far
# ahead of what puppeteer supports) and breaks WhatsApp Web ready detection.
ENV PUPPETEER_CACHE_DIR=/app/.chrome
RUN npx puppeteer browsers install chrome \
    && ln -sf "$(find /app/.chrome -type f -name chrome -path '*chrome-linux64/*' | head -1)" /usr/local/bin/chrome-for-testing \
    && /usr/local/bin/chrome-for-testing --version

# Point the app at the matched Chrome instead of Debian's chromium
ENV PUPPETEER_EXECUTABLE_PATH=/usr/local/bin/chrome-for-testing

# Copy built application from builder stage
COPY --from=builder /app/dist ./dist

# Create data directories with proper permissions
RUN mkdir -p ./data/sessions ./data/media && \
    chown -R openwa:openwa /app

# Note: Running as root to allow Docker socket access for orchestration
# For production with stricter security, consider using a Docker socket proxy
# USER openwa

# Expose port
EXPOSE 2785

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD node -e "require('http').get('http://localhost:2785/api/health', (r) => process.exit(r.statusCode === 200 ? 0 : 1))"

# Start with dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/main"]
