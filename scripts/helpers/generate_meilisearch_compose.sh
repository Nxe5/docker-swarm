#!/bin/bash
# Generate per-instance docker-compose.yml for Meilisearch from meilisearch.env
# Format: name|http_port|cpu|memory|master_key (master_key optional)

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CONTAINER_PROJECT_ROOT:-$(cd "${HELPER_DIR}/../.." && pwd)}"
CENTRAL_ENV="${ROOT}/meilisearch.env"
CONTAINERS_DIR="${ROOT}/meilisearch"

if [ ! -f "$CENTRAL_ENV" ]; then
    echo "Error: meilisearch.env not found"
    exit 1
fi

mkdir -p "$CONTAINERS_DIR"

while IFS='|' read -r name http_port cpu memory master_key rest; do
    [[ "$name" =~ ^#.*$ ]] && continue
    [[ -z "$name" ]] && continue
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
    [[ ! "$http_port" =~ ^[0-9]+$ ]] && continue

    inst_dir="${CONTAINERS_DIR}/${name}"
    mkdir -p "$inst_dir"
    compose_file="${inst_dir}/docker-compose.yml"

    # Meilisearch: MEILI_MASTER_KEY optional; if set, API requires Authorization header
    env_block=""
    if [ -n "$master_key" ]; then
        env_block="
    environment:
      MEILI_MASTER_KEY: \"${master_key}\"
"
    fi

    cat > "$compose_file" << EOF
# Auto-generated for Meilisearch instance: ${name}
# DO NOT EDIT MANUALLY - Use ./container_manager.sh meilisearch

name: meilisearch-${name}

services:
  ${name}:
    image: getmeili/meilisearch:v1.11
    container_name: meilisearch-${name}
    restart: unless-stopped
    ports:
      - "${http_port}:7700"
    volumes:
      - ${name}-data:/meili_data
    deploy:
      resources:
        limits:
          cpus: '${cpu:-1.0}'
          memory: ${memory:-512m}${env_block}

volumes:
  ${name}-data:
EOF

    echo "Generated: ${compose_file}"
done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$CENTRAL_ENV")

echo "Meilisearch compose files generated successfully."
