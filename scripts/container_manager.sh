#!/bin/bash

# Central container manager: one entry point for db, redis, livekit, minio, elasticsearch, meilisearch.
# Ensures no port conflicts via shared port registry.
# Usage: ./container_manager.sh <db|redis|livekit|minio|elasticsearch|meilisearch> <command> [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CONTAINER_PROJECT_ROOT="$ROOT"

# Bootstrap port registry from existing env files if empty
source "$SCRIPT_DIR/helpers/port_allocator.sh"
port_allocator_bootstrap

TYPE="${1:-}"
shift 2>/dev/null || true

case "$TYPE" in
    db|database|databases)
        CMD="${1:-}"; shift 2>/dev/null || true
        exec "$SCRIPT_DIR/db_manager.sh" "$CMD" "$@"
        ;;
    redis)
        CMD="${1:-}"; shift 2>/dev/null || true
        exec "$SCRIPT_DIR/redis_manager.sh" "$CMD" "$@"
        ;;
    livekit)
        CMD="${1:-}"; shift 2>/dev/null || true
        exec "$SCRIPT_DIR/livekit_manager.sh" "$CMD" "$@"
        ;;
    minio)
        CMD="${1:-}"; shift 2>/dev/null || true
        exec "$SCRIPT_DIR/minio_manager.sh" "$CMD" "$@"
        ;;
    elasticsearch|es)
        CMD="${1:-}"; shift 2>/dev/null || true
        exec "$SCRIPT_DIR/elasticsearch_manager.sh" "$CMD" "$@"
        ;;
    meilisearch)
        CMD="${1:-}"; shift 2>/dev/null || true
        exec "$SCRIPT_DIR/meilisearch_manager.sh" "$CMD" "$@"
        ;;
    show-ports|ports)
        echo "=== Databases (Supabase) ==="
        "$SCRIPT_DIR/db_manager.sh" show-ports 2>/dev/null || true
        echo ""
        echo "=== Redis ==="
        "$SCRIPT_DIR/redis_manager.sh" show-ports 2>/dev/null || true
        echo ""
        echo "=== LiveKit ==="
        "$SCRIPT_DIR/livekit_manager.sh" show-ports 2>/dev/null || true
        echo ""
        echo "=== MinIO ==="
        "$SCRIPT_DIR/minio_manager.sh" show-ports 2>/dev/null || true
        echo ""
        echo "=== Elasticsearch ==="
        "$SCRIPT_DIR/elasticsearch_manager.sh" show-ports 2>/dev/null || true
        echo ""
        echo "=== Meilisearch ==="
        "$SCRIPT_DIR/meilisearch_manager.sh" show-ports 2>/dev/null || true
        echo ""
        echo "=== Port registry (all allocated) ==="
        [ -f "$ROOT/port_registry.env" ] && grep -v "^#" "$ROOT/port_registry.env" | while IFS='|' read -r t port it name; do printf "  %-14s %-20s %s\n" "$t" "$port" "$it/$name"; done || echo "  (empty)"
        ;;
    show-credentials|credentials)
        exec "$SCRIPT_DIR/credentials_summary.sh" "$@"
        ;;
    validate-ports)
        exec "$SCRIPT_DIR/validate_ports.sh"
        ;;
    *)
        echo "Usage: $0 <db|redis|livekit|minio|elasticsearch|meilisearch> <command> [options]"
        echo "       $0 show-ports          # all port assignments and registry"
        echo "       $0 show-credentials [--show|--paths-only]  # where credentials live per service"
        echo "       $0 validate-ports       # check for port conflicts"
        echo ""
        echo "  db           - Supabase databases (add, add-full, remove, start, stop, show-ports, generate, ...)"
        echo "  redis        - Redis instances (add, remove, start, stop, show-ports, generate)"
        echo "  livekit      - LiveKit instances (add, remove, start, stop, show-ports, generate)"
        echo "  minio        - MinIO object storage (add, remove, start, stop, show-ports, generate)"
        echo "  elasticsearch - Elasticsearch (add, remove, start, stop, show-ports, generate)"
        echo "  meilisearch  - Meilisearch (add, remove, start, stop, show-ports, generate)"
        echo ""
        echo "Port registry: $ROOT/port_registry.env (prevents conflicts across all services)"
        echo "Credentials:   $0 show-credentials   (per-service .env files)"
        exit 1
        ;;
esac
