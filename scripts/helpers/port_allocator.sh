#!/bin/bash

# Central port registry: one source of truth to avoid conflicts across db, redis, livekit.
# Format: type|port_or_range|instance_type|instance_name
# instance_type: db | redis | livekit | minio | elasticsearch | meilisearch
#
# Usage: source this file, then call port_allocator_get_next_* and port_allocator_register_*

# PROJECT_ROOT must be set by caller (e.g. container_manager or db_manager)
if [ -z "${CONTAINER_PROJECT_ROOT:-}" ]; then
    # When sourced from a script in scripts/, go up one level
    _PORT_allocator_src="${BASH_SOURCE[0]}"
    _PORT_allocator_scripts="$(cd "$(dirname "$_PORT_allocator_src")/.." && pwd)"
    CONTAINER_PROJECT_ROOT="$(cd "$_PORT_allocator_scripts/.." && pwd)"
fi
PORT_REGISTRY_FILE="${CONTAINER_PROJECT_ROOT}/port_registry.env"
PORT_UDP_RANGE_SIZE=100

# Ensure registry exists
_port_allocator_ensure_registry() {
    if [ ! -f "$PORT_REGISTRY_FILE" ]; then
        touch "$PORT_REGISTRY_FILE"
    fi
}

# Get max allocated port for a type (single port types)
_port_allocator_max_port() {
    local type="$1"
    local base="$2"
    _port_allocator_ensure_registry
    local max=$base
    while IFS='|' read -r t port it iname; do
        [[ "$t" != "$type" ]] && continue
        [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt "$max" ] 2>/dev/null && max=$port
    done < "$PORT_REGISTRY_FILE" 2>/dev/null || true
    echo $max
}

# Get next single port for a type
port_allocator_get_next() {
    local type="$1"
    local base_default="$2"
    local max
    case "$type" in
        postgres)     max=$(_port_allocator_max_port "postgres" "${base_default:-5431}") ;;
        kong_http)    max=$(_port_allocator_max_port "kong_http" "${base_default:-7999}") ;;
        kong_https)   max=$(_port_allocator_max_port "kong_https" "${base_default:-8442}") ;;
        pooler)       max=$(_port_allocator_max_port "pooler" "${base_default:-6542}") ;;
        redis)        max=$(_port_allocator_max_port "redis" "${base_default:-6378}") ;;
        livekit_http)   max=$(_port_allocator_max_port "livekit_http" "${base_default:-7879}") ;;
        livekit_tcp)    max=$(_port_allocator_max_port "livekit_tcp" "${base_default:-7880}") ;;
        minio_api)      max=$(_port_allocator_max_port "minio_api" "${base_default:-8999}") ;;
        minio_console)  max=$(_port_allocator_max_port "minio_console" "${base_default:-9000}") ;;
        elasticsearch_http) max=$(_port_allocator_max_port "elasticsearch_http" "${base_default:-9199}") ;;
        meilisearch_http)   max=$(_port_allocator_max_port "meilisearch_http" "${base_default:-7699}") ;;
        *)              max=${base_default:-0} ;;
    esac
    echo $((max + 1))
}

# Get next UDP range for LiveKit (returns "start end")
port_allocator_get_next_udp_range() {
    local range_size="${1:-$PORT_UDP_RANGE_SIZE}"
    local base=49999
    _port_allocator_ensure_registry
    local max_end=$base
    while IFS='|' read -r t port_or_range it iname; do
        [[ "$t" != "livekit_udp" ]] && continue
        if [[ "$port_or_range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local end="${BASH_REMATCH[2]}"
            [ "$end" -gt "$max_end" ] 2>/dev/null && max_end=$end
        fi
    done < "$PORT_REGISTRY_FILE" 2>/dev/null || true
    local start=$((max_end + 1))
    local end=$((start + range_size - 1))
    echo "$start $end"
}

# Register one port (or range) for an instance
port_allocator_register() {
    local type="$1"
    local port_or_range="$2"
    local instance_type="$3"
    local instance_name="$4"
    _port_allocator_ensure_registry
    echo "${type}|${port_or_range}|${instance_type}|${instance_name}" >> "$PORT_REGISTRY_FILE"
}

# Unregister all ports for an instance (on remove)
port_allocator_unregister_instance() {
    local instance_type="$1"
    local instance_name="$2"
    [ ! -f "$PORT_REGISTRY_FILE" ] && return 0
    local tmp
    tmp=$(mktemp)
    while IFS='|' read -r type port_or_range it iname; do
        [[ "$it" == "$instance_type" && "$iname" == "$instance_name" ]] && continue
        echo "${type}|${port_or_range}|${it}|${iname}"
    done < "$PORT_REGISTRY_FILE" > "$tmp"
    mv "$tmp" "$PORT_REGISTRY_FILE"
}

# Bootstrap registry from existing databases.env, redis.env, livekit.env (call once if registry empty)
port_allocator_bootstrap() {
    _port_allocator_ensure_registry
    # If registry already has entries, skip
    if [ -s "$PORT_REGISTRY_FILE" ] && grep -qE "^\w+\|[0-9]" "$PORT_REGISTRY_FILE" 2>/dev/null; then
        return 0
    fi
    local root="$CONTAINER_PROJECT_ROOT"
    # Databases
    if [ -f "${root}/databases.env" ]; then
        while IFS='|' read -r name postgres_port kong_http_port kong_https_port pooler_port rest; do
            [[ "$name" =~ ^#.*$ ]] && continue
            [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
            [[ "$name" == "DASHBOARD_USERNAME" ]] && break
            [[ ! "$postgres_port" =~ ^[0-9]+$ ]] && continue
            echo "postgres|${postgres_port}|db|${name}" >> "$PORT_REGISTRY_FILE"
            echo "kong_http|${kong_http_port}|db|${name}" >> "$PORT_REGISTRY_FILE"
            echo "kong_https|${kong_https_port}|db|${name}" >> "$PORT_REGISTRY_FILE"
            echo "pooler|${pooler_port}|db|${name}" >> "$PORT_REGISTRY_FILE"
        done < "${root}/databases.env"
    fi
    # Redis
    if [ -f "${root}/redis.env" ]; then
        while IFS='|' read -r name port rest; do
            [[ "$name" =~ ^#.*$ ]] && continue
            [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
            [[ ! "$port" =~ ^[0-9]+$ ]] && continue
            echo "redis|${port}|redis|${name}" >> "$PORT_REGISTRY_FILE"
        done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "${root}/redis.env" 2>/dev/null)
    fi
    # LiveKit
    if [ -f "${root}/livekit.env" ]; then
        while IFS='|' read -r name http_port tcp_port rtp_start rtp_end rest; do
            [[ "$name" =~ ^#.*$ ]] && continue
            [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
            [[ ! "$http_port" =~ ^[0-9]+$ ]] && continue
            echo "livekit_http|${http_port}|livekit|${name}" >> "$PORT_REGISTRY_FILE"
            echo "livekit_tcp|${tcp_port}|livekit|${name}" >> "$PORT_REGISTRY_FILE"
            echo "livekit_udp|${rtp_start}-${rtp_end}|livekit|${name}" >> "$PORT_REGISTRY_FILE"
        done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "${root}/livekit.env" 2>/dev/null)
    fi
    # MinIO (api_port, console_port = api_port+1)
    if [ -f "${root}/minio.env" ]; then
        while IFS='|' read -r name api_port rest; do
            [[ "$name" =~ ^#.*$ ]] && continue
            [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
            [[ ! "$api_port" =~ ^[0-9]+$ ]] && continue
            echo "minio_api|${api_port}|minio|${name}" >> "$PORT_REGISTRY_FILE"
            echo "minio_console|$((api_port + 1))|minio|${name}" >> "$PORT_REGISTRY_FILE"
        done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "${root}/minio.env" 2>/dev/null)
    fi
    # Elasticsearch
    if [ -f "${root}/elasticsearch.env" ]; then
        while IFS='|' read -r name http_port rest; do
            [[ "$name" =~ ^#.*$ ]] && continue
            [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
            [[ ! "$http_port" =~ ^[0-9]+$ ]] && continue
            echo "elasticsearch_http|${http_port}|elasticsearch|${name}" >> "$PORT_REGISTRY_FILE"
        done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "${root}/elasticsearch.env" 2>/dev/null)
    fi
    # Meilisearch
    if [ -f "${root}/meilisearch.env" ]; then
        while IFS='|' read -r name http_port rest; do
            [[ "$name" =~ ^#.*$ ]] && continue
            [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
            [[ ! "$http_port" =~ ^[0-9]+$ ]] && continue
            echo "meilisearch_http|${http_port}|meilisearch|${name}" >> "$PORT_REGISTRY_FILE"
        done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "${root}/meilisearch.env" 2>/dev/null)
    fi
}
