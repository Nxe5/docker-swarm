#!/bin/bash

# Generate per-instance docker-compose.yml and livekit.yaml for LiveKit from livekit.env
# Each instance: livekit-server + redis. Called by container_manager.sh.

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CONTAINER_PROJECT_ROOT:-$(cd "${HELPER_DIR}/../.." && pwd)}"
CENTRAL_ENV="${ROOT}/livekit.env"
CONTAINERS_DIR="${ROOT}/livekit"

if [ ! -f "$CENTRAL_ENV" ]; then
    echo "Error: livekit.env not found"
    exit 1
fi

mkdir -p "$CONTAINERS_DIR"

while IFS='|' read -r name http_port webrtc_tcp_port rtp_start rtp_end cpu memory api_key api_secret rest; do
    [[ "$name" =~ ^#.*$ ]] && continue
    [[ -z "$name" ]] && continue
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
    [[ ! "$http_port" =~ ^[0-9]+$ ]] && continue

    inst_dir="${CONTAINERS_DIR}/${name}"
    mkdir -p "$inst_dir"
    compose_file="${inst_dir}/docker-compose.yml"
    config_file="${inst_dir}/livekit.yaml"

    # LiveKit config YAML (redis = same-compose redis service)
    cat > "$config_file" << EOF
# Auto-generated for LiveKit instance: ${name}
port: 7880
rtc:
  tcp_port: 7881
  port_range_start: ${rtp_start:-50000}
  port_range_end: ${rtp_end:-50100}
  use_external_ip: false
redis:
  address: ${name}-redis:6379
keys:
  ${api_key:-devkey}: ${api_secret:-secret}
EOF

    # docker-compose: livekit + redis (bridge network, no host mode for Mac/Win compatibility)
    cat > "$compose_file" << EOF
# Auto-generated for LiveKit instance: ${name}
# DO NOT EDIT MANUALLY - Use ./container_manager.sh livekit

name: livekit-${name}

services:
  ${name}-redis:
    image: redis:7-alpine
    container_name: livekit-${name}-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - ${name}-redis-data:/data

  ${name}:
    image: livekit/livekit-server:latest
    container_name: livekit-${name}
    restart: unless-stopped
    ports:
      - "${http_port}:7880"
      - "${webrtc_tcp_port:-$((http_port+1))}:7881"
      - "${rtp_start:-50000}-${rtp_end:-50100}:${rtp_start:-50000}-${rtp_end:-50100}/udp"
    volumes:
      - ./livekit.yaml:/etc/livekit.yaml:ro
    command: --config /etc/livekit.yaml
    deploy:
      resources:
        limits:
          cpus: '${cpu:-1.0}'
          memory: ${memory:-512m}
    depends_on:
      - ${name}-redis

volumes:
  ${name}-redis-data:
EOF

    echo "Generated: ${compose_file} and ${config_file}"
done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$CENTRAL_ENV")

echo "LiveKit compose and config files generated successfully."
