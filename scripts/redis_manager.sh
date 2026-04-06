#!/bin/bash
# Redis instance manager. Uses central port registry. Instance dirs: <ROOT>/redis/<name>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CONTAINER_PROJECT_ROOT="$ROOT"
source "$SCRIPT_DIR/helpers/port_allocator.sh" 2>/dev/null || true
port_allocator_bootstrap 2>/dev/null || true

REDIS_ENV="${ROOT}/redis.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_error() { echo -e "${RED}✗ $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }
print_header() { echo -e "${BLUE}▶ $1${NC}"; }

redis_add() {
    local name="$1"
    local port="${2:-}"
    local cpu="${3:-0.5}"
    local memory="${4:-256m}"
    local password="${5:-}"
    [[ -z "$name" ]] && { print_error "Name required"; exit 1; }
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && { print_error "Invalid name"; exit 1; }
    grep -qE "^${name}\|" "$REDIS_ENV" 2>/dev/null && { print_error "Redis instance '$name' already exists"; exit 1; }
    if [ -z "$port" ]; then
        port=$(port_allocator_get_next redis 6378) 2>/dev/null || port=6379
    fi
    print_header "Adding Redis: $name"
    local entry="${name}|${port}|${cpu}|${memory}|${password}"
    echo "$entry" >> "$REDIS_ENV"
    type port_allocator_register &>/dev/null && port_allocator_register redis "$port" redis "$name" || true
    CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_redis_compose.sh"
    # Per-instance .env for credentials and connection URL
    local dir="${ROOT}/redis/${name}"
    mkdir -p "$dir"
    if [ -n "$password" ]; then
        echo "REDIS_PORT=$port
REDIS_PASSWORD=$password
REDIS_URL=redis://:${password}@localhost:${port}
# Connection: redis://:<REDIS_PASSWORD>@localhost:${port}" > "${dir}/.env"
    else
        echo "REDIS_PORT=$port
REDIS_URL=redis://localhost:${port}
# Connection: redis://localhost:${port}" > "${dir}/.env"
    fi
    print_success "Redis '$name' added (port $port)"
    print_info "Credentials: ${dir}/.env"
    print_info "Start: ./container_manager.sh redis start $name"
}

redis_remove() {
    local name="$1"
    [[ -z "$name" ]] && { print_error "Name required"; exit 1; }
    grep -qE "^${name}\|" "$REDIS_ENV" || { print_error "Redis instance '$name' not found"; exit 1; }
    print_header "Removing Redis: $name"
    sed -i.bak "/^${name}|/d" "$REDIS_ENV" && rm -f "${REDIS_ENV}.bak"
    type port_allocator_unregister_instance &>/dev/null && port_allocator_unregister_instance redis "$name" || true
    [ -d "${ROOT}/redis/${name}" ] && rm -rf "${ROOT}/redis/${name}"
    CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_redis_compose.sh"
    print_success "Redis '$name' removed"
}

redis_start() {
    local names=("$@")
    [[ ${#names[@]} -eq 0 ]] && { print_error "Usage: $0 start <name> [name2 ...] or start-all"; exit 1; }
    print_header "Starting Redis"
    for n in "${names[@]}"; do
        grep -qE "^${n}\|" "$REDIS_ENV" || { print_error "Not found: $n"; continue; }
        local dir="${ROOT}/redis/${n}"
        [ -f "${dir}/docker-compose.yml" ] || CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_redis_compose.sh"
        (cd "$dir" && docker compose up -d) && print_success "$n started" || print_error "Failed $n"
    done
}

redis_start_all() {
    print_header "Starting all Redis"
    local list; list=$(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$REDIS_ENV" 2>/dev/null | cut -d'|' -f1)
    [ -z "$list" ] && { print_info "No Redis instances"; return 0; }
    for n in $list; do redis_start "$n"; done
}

redis_stop() {
    local names=("$@")
    [[ ${#names[@]} -eq 0 ]] && { print_error "Usage: $0 stop <name> [name2 ...] or stop-all"; exit 1; }
    print_header "Stopping Redis"
    for n in "${names[@]}"; do
        local dir="${ROOT}/redis/${n}"
        [ -f "${dir}/docker-compose.yml" ] && (cd "$dir" && docker compose stop) && print_success "$n stopped" || print_error "Failed or not found: $n"
    done
}

redis_stop_all() {
    print_header "Stopping all Redis"
    local list; list=$(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$REDIS_ENV" 2>/dev/null | cut -d'|' -f1)
    [ -z "$list" ] && { print_info "No Redis instances"; return 0; }
    for n in $list; do redis_stop "$n"; done
}

redis_show_ports() {
    print_header "Redis port assignments"
    printf "%-20s %-10s %-10s %-10s\n" "NAME" "PORT" "CPU" "MEMORY"
    echo "--------------------------------------------------------"
    while IFS='|' read -r name port cpu memory rest; do
        [[ "$name" =~ ^#.*$ ]] && continue
        [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
        printf "%-20s %-10s %-10s %-10s\n" "$name" "$port" "${cpu:-0.5}" "${memory:-256m}"
    done < "$REDIS_ENV" 2>/dev/null || true
    echo ""; print_info "Connection: redis://localhost:<PORT>"
}

CMD="${1:-}"; shift 2>/dev/null || true
case "${CMD:-}" in
    add) redis_add "$@" ;;
    remove|rm) redis_remove "$1" ;;
    start) redis_start "$@" ;;
    start-all) redis_start_all ;;
    stop) redis_stop "$@" ;;
    stop-all) redis_stop_all ;;
    show-ports|ports) redis_show_ports ;;
    generate) CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_redis_compose.sh" ;;
    *) echo "Usage: $0 {add|remove|start|stop|start-all|stop-all|show-ports|generate} [options]"; exit 1 ;;
esac
