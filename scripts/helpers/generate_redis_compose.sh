#!/bin/bash

# Generate per-instance docker-compose.yml for Redis from redis.env
# Called by container_manager.sh

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CONTAINER_PROJECT_ROOT:-$(cd "${HELPER_DIR}/../.." && pwd)}"
CENTRAL_ENV="${ROOT}/redis.env"
CONTAINERS_DIR="${ROOT}/redis"

if [ ! -f "$CENTRAL_ENV" ]; then
    echo "Error: redis.env not found"
    exit 1
fi

mkdir -p "$CONTAINERS_DIR"

while IFS='|' read -r name port cpu memory password rest; do
    [[ "$name" =~ ^#.*$ ]] && continue
    [[ -z "$name" ]] && continue
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
    [[ ! "$port" =~ ^[0-9]+$ ]] && continue

    inst_dir="${CONTAINERS_DIR}/${name}"
    mkdir -p "$inst_dir"
    compose_file="${inst_dir}/docker-compose.yml"

    # Optional Redis password: use --requirepass if set
    requirepass=""
    if [ -n "$password" ]; then
        requirepass="      REDIS_PASSWORD: ${password}"
    fi

    cat > "$compose_file" << EOF
# Auto-generated for Redis instance: ${name}
# DO NOT EDIT MANUALLY - Use ./container_manager.sh redis

name: redis-${name}

services:
  ${name}:
    image: redis:7-alpine
    container_name: redis-${name}
    restart: unless-stopped
    ports:
      - "${port}:6379"
    deploy:
      resources:
        limits:
          cpus: '${cpu:-0.5}'
          memory: ${memory:-256m}
    volumes:
      - ${name}-data:/data
EOF

    if [ -n "$password" ]; then
        cat >> "$compose_file" << EOF
    command: redis-server --requirepass \$REDIS_PASSWORD --appendonly yes
    environment:
      REDIS_PASSWORD: ${password}
EOF
    else
        cat >> "$compose_file" << EOF
    command: redis-server --appendonly yes
EOF
    fi

    cat >> "$compose_file" << EOF

volumes:
  ${name}-data:
EOF

    echo "Generated: ${compose_file}"
done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$CENTRAL_ENV")

echo "Redis compose files generated successfully."
