#!/usr/bin/env bash
# Smoke test: livekit show-ports runs (via container_manager).

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

out=$(./container_manager.sh livekit show-ports 2>&1)
echo "$out" | grep -q "LiveKit port\|NAME\|WebSocket URL" || { echo "FAIL: unexpected output"; echo "$out"; exit 1; }
echo "test_livekit_manager_show_ports.sh passed."
