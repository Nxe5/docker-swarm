#!/bin/bash
# Elasticsearch instance manager. Uses central port registry. Instance dirs: <ROOT>/elasticsearch/<name>
# Env format: name|http_port|cpu|memory|elastic_password

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CONTAINER_PROJECT_ROOT="$ROOT"
source "$SCRIPT_DIR/helpers/port_allocator.sh" 2>/dev/null || true
port_allocator_bootstrap 2>/dev/null || true

ELASTICSEARCH_ENV="${ROOT}/elasticsearch.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_error() { echo -e "${RED}✗ $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }
print_header() { echo -e "${BLUE}▶ $1${NC}"; }

generate_password() { openssl rand -base64 24 | tr -d "=+/" | cut -c1-32; }

elasticsearch_add() {
    local name="$1"
    local http_port="${2:-}"
    local cpu="${3:-2.0}"
    local memory="${4:-1g}"
    local elastic_password="${5:-$(generate_password)}"
    [[ -z "$name" ]] && { print_error "Name required"; exit 1; }
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && { print_error "Invalid name"; exit 1; }
    if [ -f "$ELASTICSEARCH_ENV" ]; then
        grep -qE "^${name}\|" "$ELASTICSEARCH_ENV" 2>/dev/null && { print_error "Elasticsearch instance '$name' already exists"; exit 1; }
    fi

    if [ -z "$http_port" ]; then
        http_port=$(port_allocator_get_next elasticsearch_http 9199) 2>/dev/null || http_port=9200
    fi

    print_header "Adding Elasticsearch: $name"
    touch "$ELASTICSEARCH_ENV"
    local entry="${name}|${http_port}|${cpu}|${memory}|${elastic_password}"
    echo "$entry" >> "$ELASTICSEARCH_ENV"
    type port_allocator_register &>/dev/null && port_allocator_register elasticsearch_http "$http_port" elasticsearch "$name" || true

    CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_elasticsearch_compose.sh"
    local dir="${ROOT}/elasticsearch/${name}"
    mkdir -p "$dir"
    cat > "${dir}/.env" << EOF
# Elasticsearch: $name
ELASTICSEARCH_HTTP_PORT=${http_port}
ELASTICSEARCH_URL=http://localhost:${http_port}
ELASTIC_USER=elastic
ELASTIC_PASSWORD=${elastic_password}
# curl -u elastic:\$ELASTIC_PASSWORD http://localhost:${http_port}/_cluster/health
EOF
    print_success "Elasticsearch '$name' added (HTTP $http_port)"
    print_info "Credentials: ${dir}/.env"
    print_info "Start: ./container_manager.sh elasticsearch start $name"
    print_info "Note: Ensure vm.max_map_count >= 262144 on host (e.g. sysctl -w vm.max_map_count=262144)"
}

elasticsearch_remove() {
    local name="$1"
    [[ -z "$name" ]] && { print_error "Name required"; exit 1; }
    [ ! -f "$ELASTICSEARCH_ENV" ] && { print_error "Elasticsearch instance '$name' not found"; exit 1; }
    grep -qE "^${name}\|" "$ELASTICSEARCH_ENV" || { print_error "Elasticsearch instance '$name' not found"; exit 1; }
    print_header "Removing Elasticsearch: $name"
    sed -i.bak "/^${name}|/d" "$ELASTICSEARCH_ENV" && rm -f "${ELASTICSEARCH_ENV}.bak"
    type port_allocator_unregister_instance &>/dev/null && port_allocator_unregister_instance elasticsearch "$name" || true
    [ -d "${ROOT}/elasticsearch/${name}" ] && rm -rf "${ROOT}/elasticsearch/${name}"
    CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_elasticsearch_compose.sh"
    print_success "Elasticsearch '$name' removed"
}

elasticsearch_start() {
    local names=("$@")
    [[ ${#names[@]} -eq 0 ]] && { print_error "Usage: $0 start <name> [name2 ...] or start-all"; exit 1; }
    print_header "Starting Elasticsearch"
    for n in "${names[@]}"; do
        grep -qE "^${n}\|" "$ELASTICSEARCH_ENV" 2>/dev/null || { print_error "Not found: $n"; continue; }
        local dir="${ROOT}/elasticsearch/${n}"
        [ -f "${dir}/docker-compose.yml" ] || CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_elasticsearch_compose.sh"
        (cd "$dir" && docker compose up -d) && print_success "$n started" || print_error "Failed $n"
    done
}

elasticsearch_start_all() {
    print_header "Starting all Elasticsearch"
    local list; list=$(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$ELASTICSEARCH_ENV" 2>/dev/null | cut -d'|' -f1)
    [ -z "$list" ] && { print_info "No Elasticsearch instances"; return 0; }
    for n in $list; do elasticsearch_start "$n"; done
}

elasticsearch_stop() {
    local names=("$@")
    [[ ${#names[@]} -eq 0 ]] && { print_error "Usage: $0 stop <name> [name2 ...] or stop-all"; exit 1; }
    print_header "Stopping Elasticsearch"
    for n in "${names[@]}"; do
        local dir="${ROOT}/elasticsearch/${n}"
        [ -f "${dir}/docker-compose.yml" ] && (cd "$dir" && docker compose stop) && print_success "$n stopped" || print_error "Failed or not found: $n"
    done
}

elasticsearch_stop_all() {
    print_header "Stopping all Elasticsearch"
    local list; list=$(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$ELASTICSEARCH_ENV" 2>/dev/null | cut -d'|' -f1)
    [ -z "$list" ] && { print_info "No Elasticsearch instances"; return 0; }
    for n in $list; do elasticsearch_stop "$n"; done
}

elasticsearch_show_ports() {
    print_header "Elasticsearch port assignments"
    printf "%-20s %-10s %-10s %-10s\n" "NAME" "HTTP" "CPU" "MEMORY"
    echo "--------------------------------------------------------"
    while IFS='|' read -r name http_port cpu memory rest; do
        [[ "$name" =~ ^#.*$ ]] && continue
        [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
        [[ ! "$http_port" =~ ^[0-9]+$ ]] && continue
        printf "%-20s %-10s %-10s %-10s\n" "$name" "$http_port" "${cpu:-2}" "${memory:-1g}"
    done < "$ELASTICSEARCH_ENV" 2>/dev/null || true
    echo ""; print_info "HTTP API: http://localhost:<HTTP> (user: elastic)"
}

CMD="${1:-}"; shift 2>/dev/null || true
case "${CMD:-}" in
    add) elasticsearch_add "$@" ;;
    remove|rm) elasticsearch_remove "$1" ;;
    start) elasticsearch_start "$@" ;;
    start-all) elasticsearch_start_all ;;
    stop) elasticsearch_stop "$@" ;;
    stop-all) elasticsearch_stop_all ;;
    show-ports|ports) elasticsearch_show_ports ;;
    generate) CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_elasticsearch_compose.sh" ;;
    *) echo "Usage: $0 {add|remove|start|stop|start-all|stop-all|show-ports|generate} [options]"; exit 1 ;;
esac
