#!/bin/bash
# Wrapper: runs scripts/db_manager.sh (centralized manager with port registry).
# Usage: ./db_manager.sh <command> [options]  (same as before)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/scripts/db_manager.sh" "$@"
