# Frontend Dockerfile
FROM node:20-alpine AS builder

# Build-time defaults; can be overridden via build args
ARG VITE_API_URL=
ARG VITE_AUTH_ENABLED=true
ARG VITE_OIDC_AUTHORITY=https://localhost:3000/realms/testrealm
ARG VITE_OIDC_CLIENT_ID=frontend-client
ARG VITE_OIDC_REDIRECT_URI=https://localhost:3000/callback

ENV VITE_API_URL=${VITE_API_URL}
ENV VITE_AUTH_ENABLED=${VITE_AUTH_ENABLED}
ENV VITE_OIDC_AUTHORITY=${VITE_OIDC_AUTHORITY}
ENV VITE_OIDC_CLIENT_ID=${VITE_OIDC_CLIENT_ID}
ENV VITE_OIDC_REDIRECT_URI=${VITE_OIDC_REDIRECT_URI}

# Debug: Print environment variables
RUN echo "======================================" && \
    echo "Build-time environment variables:" && \
    echo "VITE_API_URL=${VITE_API_URL}" && \
    echo "VITE_AUTH_ENABLED=${VITE_AUTH_ENABLED}" && \
    echo "VITE_OIDC_AUTHORITY=${VITE_OIDC_AUTHORITY}" && \
    echo "VITE_OIDC_CLIENT_ID=${VITE_OIDC_CLIENT_ID}" && \
    echo "VITE_OIDC_REDIRECT_URI=${VITE_OIDC_REDIRECT_URI}" && \
    echo "======================================"

WORKDIR /app
COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Debug: Check built files for embedded URLs
RUN echo "======================================" && \
    echo "Checking built JavaScript for localhost URLs:" && \
    grep -o 'localhost:[0-9]*' dist/assets/*.js | sort -u || echo "No localhost URLs found" && \
    echo "======================================"

FROM nginx:alpine

# Install openssl for certificate generation
RUN apk add --no-cache openssl bash

# Copy build artifacts
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configurations and certificate generation script from frontend directory
COPY nginx.conf /etc/nginx/conf.d/nginx-http.conf
COPY nginx-ssl.conf /etc/nginx/conf.d/nginx-ssl.conf
COPY generate-frontend-certs.sh /usr/local/bin/generate-frontend-certs.sh
RUN chmod +x /usr/local/bin/generate-frontend-certs.sh
RUN chmod +x /usr/local/bin/generate-frontend-certs.sh

# Create entrypoint script
RUN cat > /docker-entrypoint.sh <<'EOF'
#!/bin/bash
set -e

# Use HTTP config for development, HTTPS for other environments
if [ "$ENVIRONMENT" = "development" ]; then
    echo "Using HTTP configuration for development environment"
    if [ -f /etc/nginx/conf.d/nginx-ssl.conf ]; then
        rm -f /etc/nginx/conf.d/nginx-ssl.conf
    fi
    if [ -f /etc/nginx/conf.d/nginx-http.conf ]; then
        cp /etc/nginx/conf.d/nginx-http.conf /etc/nginx/conf.d/default.conf
    fi
else
    echo "Using HTTPS configuration for non-development environment"
    # Only generate certificates if they don't exist (for Docker Compose)
    # In K8s, certificates are mounted as tls.crt/tls.key from TLS secrets
    if [ -f /etc/nginx/certs/tls.crt ] && [ -f /etc/nginx/certs/tls.key ]; then
        echo "Using existing TLS certificates from K8s secret"
    elif [ ! -f /etc/nginx/certs/frontend.crt ] || [ ! -f /etc/nginx/certs/frontend.key ]; then
        echo "Certificates not found, generating..."
        /usr/local/bin/generate-frontend-certs.sh
    else
        echo "Using existing certificates from /etc/nginx/certs"
    fi
    if [ -f /etc/nginx/conf.d/nginx-http.conf ]; then
        rm -f /etc/nginx/conf.d/nginx-http.conf
    fi
    if [ -f /etc/nginx/conf.d/nginx-ssl.conf ]; then
        cp /etc/nginx/conf.d/nginx-ssl.conf /etc/nginx/conf.d/default.conf
    fi
fi

exec nginx -g "daemon off;"
EOF

RUN chmod +x /docker-entrypoint.sh

EXPOSE 80 443

CMD ["/docker-entrypoint.sh"]
