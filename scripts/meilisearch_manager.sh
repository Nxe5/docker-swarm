#!/bin/bash
# Meilisearch instance manager. Uses central port registry. Instance dirs: <ROOT>/meilisearch/<name>
# Env format: name|http_port|cpu|memory|master_key (master_key optional)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CONTAINER_PROJECT_ROOT="$ROOT"
source "$SCRIPT_DIR/helpers/port_allocator.sh" 2>/dev/null || true
port_allocator_bootstrap 2>/dev/null || true

MEILISEARCH_ENV="${ROOT}/meilisearch.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_error() { echo -e "${RED}✗ $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }
print_header() { echo -e "${BLUE}▶ $1${NC}"; }

generate_master_key() { openssl rand -hex 32; }

meilisearch_add() {
    local name="$1"
    local http_port="${2:-}"
    local cpu="${3:-1.0}"
    local memory="${4:-512m}"
    local master_key="${5:-$(generate_master_key)}"
    [[ -z "$name" ]] && { print_error "Name required"; exit 1; }
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && { print_error "Invalid name"; exit 1; }
    if [ -f "$MEILISEARCH_ENV" ]; then
        grep -qE "^${name}\|" "$MEILISEARCH_ENV" 2>/dev/null && { print_error "Meilisearch instance '$name' already exists"; exit 1; }
    fi

    if [ -z "$http_port" ]; then
        http_port=$(port_allocator_get_next meilisearch_http 7699) 2>/dev/null || http_port=7700
    fi

    print_header "Adding Meilisearch: $name"
    touch "$MEILISEARCH_ENV"
    local entry="${name}|${http_port}|${cpu}|${memory}|${master_key}"
    echo "$entry" >> "$MEILISEARCH_ENV"
    type port_allocator_register &>/dev/null && port_allocator_register meilisearch_http "$http_port" meilisearch "$name" || true

    CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_meilisearch_compose.sh"
    local dir="${ROOT}/meilisearch/${name}"
    mkdir -p "$dir"
    cat > "${dir}/.env" << EOF
# Meilisearch: $name
MEILISEARCH_HTTP_PORT=${http_port}
MEILISEARCH_URL=http://localhost:${http_port}
MEILI_MASTER_KEY=${master_key}
# API: http://localhost:${http_port}. Use X-Meili-API-Key: \$MEILI_MASTER_KEY for protected routes.
EOF
    print_success "Meilisearch '$name' added (HTTP $http_port)"
    print_info "Credentials: ${dir}/.env"
    print_info "Start: ./container_manager.sh meilisearch start $name"
}

meilisearch_remove() {
    local name="$1"
    [[ -z "$name" ]] && { print_error "Name required"; exit 1; }
    [ ! -f "$MEILISEARCH_ENV" ] && { print_error "Meilisearch instance '$name' not found"; exit 1; }
    grep -qE "^${name}\|" "$MEILISEARCH_ENV" || { print_error "Meilisearch instance '$name' not found"; exit 1; }
    print_header "Removing Meilisearch: $name"
    sed -i.bak "/^${name}|/d" "$MEILISEARCH_ENV" && rm -f "${MEILISEARCH_ENV}.bak"
    type port_allocator_unregister_instance &>/dev/null && port_allocator_unregister_instance meilisearch "$name" || true
    [ -d "${ROOT}/meilisearch/${name}" ] && rm -rf "${ROOT}/meilisearch/${name}"
    CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_meilisearch_compose.sh"
    print_success "Meilisearch '$name' removed"
}

meilisearch_start() {
    local names=("$@")
    [[ ${#names[@]} -eq 0 ]] && { print_error "Usage: $0 start <name> [name2 ...] or start-all"; exit 1; }
    print_header "Starting Meilisearch"
    for n in "${names[@]}"; do
        grep -qE "^${n}\|" "$MEILISEARCH_ENV" 2>/dev/null || { print_error "Not found: $n"; continue; }
        local dir="${ROOT}/meilisearch/${n}"
        [ -f "${dir}/docker-compose.yml" ] || CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_meilisearch_compose.sh"
        (cd "$dir" && docker compose up -d) && print_success "$n started" || print_error "Failed $n"
    done
}

meilisearch_start_all() {
    print_header "Starting all Meilisearch"
    local list; list=$(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$MEILISEARCH_ENV" 2>/dev/null | cut -d'|' -f1)
    [ -z "$list" ] && { print_info "No Meilisearch instances"; return 0; }
    for n in $list; do meilisearch_start "$n"; done
}

meilisearch_stop() {
    local names=("$@")
    [[ ${#names[@]} -eq 0 ]] && { print_error "Usage: $0 stop <name> [name2 ...] or stop-all"; exit 1; }
    print_header "Stopping Meilisearch"
    for n in "${names[@]}"; do
        local dir="${ROOT}/meilisearch/${n}"
        [ -f "${dir}/docker-compose.yml" ] && (cd "$dir" && docker compose stop) && print_success "$n stopped" || print_error "Failed or not found: $n"
    done
}

meilisearch_stop_all() {
    print_header "Stopping all Meilisearch"
    local list; list=$(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$MEILISEARCH_ENV" 2>/dev/null | cut -d'|' -f1)
    [ -z "$list" ] && { print_info "No Meilisearch instances"; return 0; }
    for n in $list; do meilisearch_stop "$n"; done
}

meilisearch_show_ports() {
    print_header "Meilisearch port assignments"
    printf "%-20s %-10s %-10s %-10s\n" "NAME" "HTTP" "CPU" "MEMORY"
    echo "--------------------------------------------------------"
    while IFS='|' read -r name http_port cpu memory rest; do
        [[ "$name" =~ ^#.*$ ]] && continue
        [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
        [[ ! "$http_port" =~ ^[0-9]+$ ]] && continue
        printf "%-20s %-10s %-10s %-10s\n" "$name" "$http_port" "${cpu:-1}" "${memory:-512m}"
    done < "$MEILISEARCH_ENV" 2>/dev/null || true
    echo ""; print_info "API: http://localhost:<HTTP>"
}

CMD="${1:-}"; shift 2>/dev/null || true
case "${CMD:-}" in
    add) meilisearch_add "$@" ;;
    remove|rm) meilisearch_remove "$1" ;;
    start) meilisearch_start "$@" ;;
    start-all) meilisearch_start_all ;;
    stop) meilisearch_stop "$@" ;;
    stop-all) meilisearch_stop_all ;;
    show-ports|ports) meilisearch_show_ports ;;
    generate) CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_meilisearch_compose.sh" ;;
    *) echo "Usage: $0 {add|remove|start|stop|start-all|stop-all|show-ports|generate} [options]"; exit 1 ;;
esac
