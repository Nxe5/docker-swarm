#!/usr/bin/env bash
# Smoke test: db_manager show-ports runs and prints a table or "No databases".

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

out=$(./db_manager.sh show-ports 2>&1)
echo "$out" | grep -q "Database Port Assignments\|POSTGRES\|No database\|DATABASE" || { echo "FAIL: unexpected output"; echo "$out"; exit 1; }
echo "test_db_manager_show_ports.sh passed."
