#!/bin/bash
# Generate per-instance docker-compose.yml for Elasticsearch from elasticsearch.env
# Format: name|http_port|cpu|memory|elastic_password

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CONTAINER_PROJECT_ROOT:-$(cd "${HELPER_DIR}/../.." && pwd)}"
CENTRAL_ENV="${ROOT}/elasticsearch.env"
CONTAINERS_DIR="${ROOT}/elasticsearch"

if [ ! -f "$CENTRAL_ENV" ]; then
    echo "Error: elasticsearch.env not found"
    exit 1
fi

mkdir -p "$CONTAINERS_DIR"

while IFS='|' read -r name http_port cpu memory elastic_password rest; do
    [[ "$name" =~ ^#.*$ ]] && continue
    [[ -z "$name" ]] && continue
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
    [[ ! "$http_port" =~ ^[0-9]+$ ]] && continue

    inst_dir="${CONTAINERS_DIR}/${name}"
    mkdir -p "$inst_dir"
    compose_file="${inst_dir}/docker-compose.yml"

    # ES 8.x: single-node, security enabled; password required
    cat > "$compose_file" << EOF
# Auto-generated for Elasticsearch instance: ${name}
# DO NOT EDIT MANUALLY - Use ./container_manager.sh elasticsearch

name: elasticsearch-${name}

services:
  ${name}:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.15.0
    container_name: elasticsearch-${name}
    restart: unless-stopped
    ports:
      - "${http_port}:9200"
    environment:
      discovery.type: single-node
      xpack.security.enabled: "true"
      ELASTIC_PASSWORD: "${elastic_password}"
      # Increase vm.max_map_count on host if needed: sysctl -w vm.max_map_count=262144
    deploy:
      resources:
        limits:
          cpus: '${cpu:-2.0}'
          memory: ${memory:-1g}
    volumes:
      - ${name}-data:/usr/share/elasticsearch/data
    healthcheck:
      test: ["CMD-SHELL", "curl -s -u elastic:\${ELASTIC_PASSWORD} http://localhost:9200/_cluster/health | grep -q '\"status\":\"green\"\\|\"status\":\"yellow\"'"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 60s

volumes:
  ${name}-data:
EOF

    echo "Generated: ${compose_file}"
done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$CENTRAL_ENV")

echo "Elasticsearch compose files generated successfully."
