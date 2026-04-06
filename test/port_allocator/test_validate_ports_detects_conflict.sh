#!/usr/bin/env bash
# Test that validate_ports.sh detects duplicate port in registry -> exit 1.

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Registry with duplicate port (5432 used twice)
cat > "$TMP/port_registry.env" << 'EOF'
postgres|5432|db|db1
postgres|5432|db|db2
EOF

# validate_ports.sh respects PORT_REGISTRY_FILE
set +e
out=$(PORT_REGISTRY_FILE="$TMP/port_registry.env" "$ROOT/scripts/validate_ports.sh" 2>&1)
code=$?
set -e
echo "$out" | grep -qi "conflict" || { echo "FAIL: expected output to mention conflict. Got: $out"; exit 1; }
[ "$code" -ne 0 ] || { echo "FAIL: expected exit code non-zero, got $code"; exit 1; }
echo "test_validate_ports_detects_conflict.sh passed."
