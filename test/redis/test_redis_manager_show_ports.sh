#!/usr/bin/env bash
# Smoke test: redis show-ports runs (via container_manager).

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

out=$(./container_manager.sh redis show-ports 2>&1)
echo "$out" | grep -q "Redis port\|NAME\|Connection: redis" || { echo "FAIL: unexpected output"; echo "$out"; exit 1; }
echo "test_redis_manager_show_ports.sh passed."
