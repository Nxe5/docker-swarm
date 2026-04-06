#!/bin/bash
# Ensure no port conflicts: check port_registry.env for duplicates.
# Exit 0 if no conflicts, 1 if conflicts found.
# Compatible with Bash 3 (no associative arrays). Uses PORT_REGISTRY_FILE for tests.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY="${PORT_REGISTRY_FILE:-$ROOT/port_registry.env}"

conflicts=0

# Read registry into temp file, skip comments/empty
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
grep -v '^#' "$REGISTRY" 2>/dev/null | grep -E '^[^|]+\|[^|]+\|[^|]+\|[^|]+' > "$tmp" || true

# Check 1: duplicate (type|port_or_range) -> same key used twice
while IFS='|' read -r type port_or_range it name; do
  key="${type}|${port_or_range}"
  count=$(grep -cF "$key" "$tmp" 2>/dev/null || echo 0)
  if [ "$count" -gt 1 ]; then
    echo "Conflict in port_registry.env: $type port/range $port_or_range used by multiple instances"
    conflicts=$((conflicts + 1))
    break
  fi
done < "$tmp"

# Check 2: duplicate single port number across any type (e.g. 5432 used by postgres and redis)
while IFS='|' read -r type port_or_range it name; do
  if echo "$port_or_range" | grep -qE '^[0-9]+$'; then
    count=$(awk -F'|' -v p="$port_or_range" '$2 == p { print }' "$tmp" | wc -l | tr -d ' ')
    if [ "$count" -gt 1 ]; then
      echo "Port conflict: port $port_or_range used by multiple instances"
      conflicts=$((conflicts + 1))
      break
    fi
  fi
done < "$tmp"

if [ "$conflicts" -gt 0 ]; then
  echo "Total conflicts: $conflicts"
  exit 1
fi

echo "No port conflicts found. Registry: $REGISTRY"
exit 0
