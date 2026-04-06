#!/usr/bin/env bash
# Test validate_ports.sh with a clean registry (no duplicates) -> exit 0.

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/validate_ports.sh" 2>&1 | grep -q "No port conflicts"
echo "test_validate_ports_no_conflict.sh passed."
