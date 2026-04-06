#!/bin/bash
# Generate per-instance docker-compose.yml for MinIO from minio.env
# Format: name|api_port|cpu|memory|root_user|root_password

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CONTAINER_PROJECT_ROOT:-$(cd "${HELPER_DIR}/../.." && pwd)}"
CENTRAL_ENV="${ROOT}/minio.env"
CONTAINERS_DIR="${ROOT}/minio"

if [ ! -f "$CENTRAL_ENV" ]; then
    echo "Error: minio.env not found"
    exit 1
fi

mkdir -p "$CONTAINERS_DIR"

while IFS='|' read -r name api_port cpu memory root_user root_password rest; do
    [[ "$name" =~ ^#.*$ ]] && continue
    [[ -z "$name" ]] && continue
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
    [[ ! "$api_port" =~ ^[0-9]+$ ]] && continue

    console_port=$((api_port + 1))
    inst_dir="${CONTAINERS_DIR}/${name}"
    mkdir -p "$inst_dir"
    compose_file="${inst_dir}/docker-compose.yml"

    cat > "$compose_file" << EOF
# Auto-generated for MinIO instance: ${name}
# DO NOT EDIT MANUALLY - Use ./container_manager.sh minio

name: minio-${name}

services:
  ${name}:
    image: minio/minio:latest
    container_name: minio-${name}
    restart: unless-stopped
    ports:
      - "${api_port}:9000"
      - "${console_port}:9001"
    environment:
      MINIO_ROOT_USER: "${root_user:-minioadmin}"
      MINIO_ROOT_PASSWORD: "${root_password:-minioadmin}"
    command: server /data --console-address ":9001"
    deploy:
      resources:
        limits:
          cpus: '${cpu:-1.0}'
          memory: ${memory:-512m}
    volumes:
      - ${name}-data:/data

volumes:
  ${name}-data:
EOF

    echo "Generated: ${compose_file}"
done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$CENTRAL_ENV")

echo "MinIO compose files generated successfully."
