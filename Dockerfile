# ================================================================
#  Solar Soil IoT Dashboard — Production Docker Image
#  Stage: Single-stage Node.js 20 slim production image
#
#  Before building, ensure you have compiled the Flutter web app:
#    puro flutter build web --release
#  (from inside the frontend/ directory)
# ================================================================

# Use the official Node.js 20 LTS slim image as the base
FROM node:20-slim

# Metadata labels
LABEL maintainer="solarsoil-iot"
LABEL description="Solar Soil IoT Dashboard — Express gateway + Flutter Web"
LABEL version="1.0.0"

# Set working directory for the backend
WORKDIR /app/backend

# ----------------------------------------------------------------
# Copy and install production Node.js dependencies first.
# This layer is cached as long as package*.json doesn't change,
# making subsequent builds significantly faster.
# ----------------------------------------------------------------
COPY backend/package*.json ./
RUN npm ci --omit=dev

# ----------------------------------------------------------------
# Copy backend source files (server, services, auth, configs)
# users.db.json is included so the auth service has its database.
# ----------------------------------------------------------------
COPY backend/server.js ./
COPY backend/authService.js ./
COPY backend/influxService.js ./
COPY backend/aiService.js ./
COPY backend/users.db.json ./
COPY backend/ai_config.json ./
COPY backend/garden_config.json ./

# ----------------------------------------------------------------
# Copy root static assets (login page, Tailwind CSS, styles)
# server.js serves these from: ../ via express.static
# ----------------------------------------------------------------
COPY index.html /app/index.html
COPY style.css /app/style.css
COPY tailwind-built.css /app/tailwind-built.css

# ----------------------------------------------------------------
# Copy pre-compiled Flutter web static assets.
# server.js serves these from: ../frontend/build/web
# (.dockerignore is configured to include frontend/build/web/)
# ----------------------------------------------------------------
COPY frontend/build/web /app/frontend/build/web

# ----------------------------------------------------------------
# Expose the application port
# ----------------------------------------------------------------
EXPOSE 5000

# ----------------------------------------------------------------
# Production environment defaults (override at runtime via .env
# or docker run -e / Compose environment: section)
# ----------------------------------------------------------------
ENV NODE_ENV=production
ENV PORT=5000

# ----------------------------------------------------------------
# Health check — Docker will restart the container if unhealthy
# ----------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD node -e "require('http').get('http://localhost:5000/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

# ----------------------------------------------------------------
# Start the backend gateway server
# ----------------------------------------------------------------
CMD ["node", "server.js"]
