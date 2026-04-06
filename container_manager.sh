#!/bin/bash
# Wrapper: runs scripts/container_manager.sh (centralized db + redis + livekit, shared port registry).
# Usage: ./container_manager.sh <db|redis|livekit|minio|elasticsearch|meilisearch> <command> [options]
#        ./container_manager.sh show-ports

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/scripts/container_manager.sh" "$@"
