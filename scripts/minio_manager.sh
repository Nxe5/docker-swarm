#!/bin/bash
# MinIO instance manager. Uses central port registry. Instance dirs: <ROOT>/minio/<name>
# Env format: name|api_port|cpu|memory|root_user|root_password

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CONTAINER_PROJECT_ROOT="$ROOT"
source "$SCRIPT_DIR/helpers/port_allocator.sh" 2>/dev/null || true
port_allocator_bootstrap 2>/dev/null || true

MINIO_ENV="${ROOT}/minio.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_error() { echo -e "${RED}✗ $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }
print_header() { echo -e "${BLUE}▶ $1${NC}"; }

generate_password() { openssl rand -base64 24 | tr -d "=+/" | cut -c1-32; }

minio_add() {
    local name="$1"
    local api_port="${2:-}"
    local cpu="${3:-1.0}"
    local memory="${4:-512m}"
    local root_user="${5:-minioadmin}"
    local root_password="${6:-$(generate_password)}"
    [[ -z "$name" ]] && { print_error "Name required"; exit 1; }
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && { print_error "Invalid name"; exit 1; }
    if [ -f "$MINIO_ENV" ]; then
        grep -qE "^${name}\|" "$MINIO_ENV" 2>/dev/null && { print_error "MinIO instance '$name' already exists"; exit 1; }
    fi

    if [ -z "$api_port" ]; then
        api_port=$(port_allocator_get_next minio_api 8999) 2>/dev/null || api_port=9000
    fi
    local console_port=$((api_port + 1))

    print_header "Adding MinIO: $name"
    touch "$MINIO_ENV"
    local entry="${name}|${api_port}|${cpu}|${memory}|${root_user}|${root_password}"
    echo "$entry" >> "$MINIO_ENV"
    type port_allocator_register &>/dev/null && port_allocator_register minio_api "$api_port" minio "$name" && port_allocator_register minio_console "$console_port" minio "$name" || true

    CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_minio_compose.sh"
    local dir="${ROOT}/minio/${name}"
    mkdir -p "$dir"
    cat > "${dir}/.env" << EOF
# MinIO: $name
MINIO_API_PORT=${api_port}
MINIO_CONSOLE_PORT=${console_port}
MINIO_ENDPOINT=http://localhost:${api_port}
MINIO_CONSOLE_URL=http://localhost:${console_port}
MINIO_ROOT_USER=${root_user}
MINIO_ROOT_PASSWORD=${root_password}
# S3-compatible: use endpoint http://localhost:${api_port} with access key / secret above
EOF
    print_success "MinIO '$name' added (API $api_port, Console $console_port)"
    print_info "Credentials: ${dir}/.env"
    print_info "Start: ./container_manager.sh minio start $name"
}

minio_remove() {
    local name="$1"
    [[ -z "$name" ]] && { print_error "Name required"; exit 1; }
    [ ! -f "$MINIO_ENV" ] && { print_error "MinIO instance '$name' not found"; exit 1; }
    grep -qE "^${name}\|" "$MINIO_ENV" || { print_error "MinIO instance '$name' not found"; exit 1; }
    print_header "Removing MinIO: $name"
    sed -i.bak "/^${name}|/d" "$MINIO_ENV" && rm -f "${MINIO_ENV}.bak"
    type port_allocator_unregister_instance &>/dev/null && port_allocator_unregister_instance minio "$name" || true
    [ -d "${ROOT}/minio/${name}" ] && rm -rf "${ROOT}/minio/${name}"
    CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_minio_compose.sh"
    print_success "MinIO '$name' removed"
}

minio_start() {
    local names=("$@")
    [[ ${#names[@]} -eq 0 ]] && { print_error "Usage: $0 start <name> [name2 ...] or start-all"; exit 1; }
    print_header "Starting MinIO"
    for n in "${names[@]}"; do
        grep -qE "^${n}\|" "$MINIO_ENV" 2>/dev/null || { print_error "Not found: $n"; continue; }
        local dir="${ROOT}/minio/${n}"
        [ -f "${dir}/docker-compose.yml" ] || CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_minio_compose.sh"
        (cd "$dir" && docker compose up -d) && print_success "$n started" || print_error "Failed $n"
    done
}

minio_start_all() {
    print_header "Starting all MinIO"
    local list; list=$(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$MINIO_ENV" 2>/dev/null | cut -d'|' -f1)
    [ -z "$list" ] && { print_info "No MinIO instances"; return 0; }
    for n in $list; do minio_start "$n"; done
}

minio_stop() {
    local names=("$@")
    [[ ${#names[@]} -eq 0 ]] && { print_error "Usage: $0 stop <name> [name2 ...] or stop-all"; exit 1; }
    print_header "Stopping MinIO"
    for n in "${names[@]}"; do
        local dir="${ROOT}/minio/${n}"
        [ -f "${dir}/docker-compose.yml" ] && (cd "$dir" && docker compose stop) && print_success "$n stopped" || print_error "Failed or not found: $n"
    done
}

minio_stop_all() {
    print_header "Stopping all MinIO"
    local list; list=$(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$MINIO_ENV" 2>/dev/null | cut -d'|' -f1)
    [ -z "$list" ] && { print_info "No MinIO instances"; return 0; }
    for n in $list; do minio_stop "$n"; done
}

minio_show_ports() {
    print_header "MinIO port assignments"
    printf "%-20s %-10s %-10s %-10s %-10s\n" "NAME" "API" "CONSOLE" "CPU" "MEMORY"
    echo "------------------------------------------------------------------------"
    while IFS='|' read -r name api_port cpu memory rest; do
        [[ "$name" =~ ^#.*$ ]] && continue
        [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
        [[ ! "$api_port" =~ ^[0-9]+$ ]] && continue
        console_port=$((api_port + 1))
        printf "%-20s %-10s %-10s %-10s %-10s\n" "$name" "$api_port" "$console_port" "${cpu:-1}" "${memory:-512m}"
    done < "$MINIO_ENV" 2>/dev/null || true
    echo ""; print_info "API: http://localhost:<API>, Console: http://localhost:<CONSOLE>"
}

CMD="${1:-}"; shift 2>/dev/null || true
case "${CMD:-}" in
    add) minio_add "$@" ;;
    remove|rm) minio_remove "$1" ;;
    start) minio_start "$@" ;;
    start-all) minio_start_all ;;
    stop) minio_stop "$@" ;;
    stop-all) minio_stop_all ;;
    show-ports|ports) minio_show_ports ;;
    generate) CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_minio_compose.sh" ;;
    *) echo "Usage: $0 {add|remove|start|stop|start-all|stop-all|show-ports|generate} [options]"; exit 1 ;;
esac
