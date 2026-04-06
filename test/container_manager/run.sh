#!/usr/bin/env bash
# Run container_manager-area tests. Add test_*.sh here and run them from this script.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

echo "=== test/container_manager ==="
run_count=0
for f in "$SCRIPT_DIR"/test_*.sh; do
  [ -f "$f" ] || continue
  echo "Running $f"
  bash "$f"
  ((run_count++)) || true
done
if [ "$run_count" -eq 0 ]; then
  echo "No tests yet. Add test_*.sh in test/container_manager/ and re-run."
fi
echo "Done."
