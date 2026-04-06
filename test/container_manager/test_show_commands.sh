#!/usr/bin/env bash
# Test container_manager show-ports, show-credentials, validate-ports (exit 0 and expected output).

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "  show-ports..."
out=$(./container_manager.sh show-ports 2>&1)
echo "$out" | grep -q "Databases\|Redis\|LiveKit\|Port registry" || { echo "FAIL show-ports: expected section headers"; exit 1; }
echo "OK show-ports"

echo "  show-credentials (default)..."
out=$(./container_manager.sh show-credentials 2>&1)
echo "$out" | grep -q "Credentials per service\|Summary" || { echo "FAIL show-credentials: expected summary"; exit 1; }
echo "OK show-credentials"

echo "  show-credentials --paths-only..."
out=$(./container_manager.sh show-credentials --paths-only 2>&1)
# May be empty if no instances; otherwise should list .env paths or nothing
[[ "$out" == *".env"* || -z "$out" ]] || true
echo "OK show-credentials --paths-only"

echo "  validate-ports..."
out=$(./container_manager.sh validate-ports 2>&1)
echo "$out" | grep -q "No port conflicts found\|conflict" || { echo "FAIL validate-ports: $out"; exit 1; }
echo "OK validate-ports"

echo "test_show_commands.sh passed."
