#!/usr/bin/env bash
# Basic port allocator tests using a temp registry (does not touch project port_registry.env).

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$ROOT/scripts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CONTAINER_PROJECT_ROOT="$TMP"
# Create empty registry
touch "$TMP/port_registry.env"
source "$SCRIPTS/helpers/port_allocator.sh"

assert_eq() {
  local want="$1"
  local got="$2"
  local msg="${3:-}"
  if [ "$got" != "$want" ]; then
    echo "FAIL ${msg}: expected '$want', got '$got'"
    exit 1
  fi
  echo "OK ${msg}"
}

echo "  get_next with empty registry..."
p1=$(port_allocator_get_next postgres 5431)
assert_eq "5432" "$p1" "first postgres port"
r1=$(port_allocator_get_next redis 6378)
assert_eq "6379" "$r1" "first redis port"

echo "  register and get_next again..."
port_allocator_register postgres 5432 db mydb
port_allocator_register redis 6379 redis cache1
p2=$(port_allocator_get_next postgres 5431)
assert_eq "5433" "$p2" "second postgres port"
r2=$(port_allocator_get_next redis 6378)
assert_eq "6380" "$r2" "second redis port"

echo "  unregister instance..."
port_allocator_unregister_instance db mydb
p3=$(port_allocator_get_next postgres 5431)
assert_eq "5432" "$p3" "postgres port after unregister (reuse)"

echo "  UDP range..."
read -r udp_start udp_end <<< "$(port_allocator_get_next_udp_range 100)"
[ "$udp_start" -ge 50000 ] && [ "$udp_end" -eq $((udp_start + 99)) ] || { echo "FAIL udp range"; exit 1; }
echo "OK udp range $udp_start-$udp_end"

echo "test_port_allocator_basic.sh passed."
