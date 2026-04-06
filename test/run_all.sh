#!/usr/bin/env bash
# Run all area test runners. Use from project root: ./test/run_all.sh

set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TEST_DIR/.." && pwd)"
cd "$ROOT"

echo "Running all test areas from $ROOT"
echo ""

failed=0
for area in databases redis livekit port_allocator container_manager; do
  run_script="$TEST_DIR/$area/run.sh"
  if [ -x "$run_script" ]; then
    "$run_script" || ((failed++)) || true
  elif [ -f "$run_script" ]; then
    bash "$run_script" || ((failed++)) || true
  fi
  echo ""
done

if [ "$failed" -gt 0 ]; then
  echo "One or more areas had failures."
  exit 1
fi
echo "All areas finished."
