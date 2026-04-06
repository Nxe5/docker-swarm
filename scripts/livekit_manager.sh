#!/bin/bash
# LiveKit instance manager. Uses central port registry. Instance dirs: <ROOT>/livekit/<name>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CONTAINER_PROJECT_ROOT="$ROOT"
source "$SCRIPT_DIR/helpers/port_allocator.sh" 2>/dev/null || true
port_allocator_bootstrap 2>/dev/null || true

LIVEKIT_ENV="${ROOT}/livekit.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_error() { echo -e "${RED}✗ $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }
print_header() { echo -e "${BLUE}▶ $1${NC}"; }

generate_password() { openssl rand -base64 24 | tr -d "=+/" | cut -c1-32; }
generate_api_key() { echo -n "lk-"; openssl rand -hex 8; }

livekit_add() {
    local name="$1"
    local http_port="${2:-}"
    local cpu="${3:-1.0}"
    local memory="${4:-512m}"
    local api_key="${5:-$(generate_api_key)}"
    local api_secret="${6:-$(generate_password)}"
    [[ -z "$name" ]] && { print_error "Name required"; exit 1; }
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && { print_error "Invalid name"; exit 1; }
    grep -qE "^${name}\|" "$LIVEKIT_ENV" 2>/dev/null && { print_error "LiveKit instance '$name' already exists"; exit 1; }

    local webrtc_tcp_port rtp_start rtp_end
    if type port_allocator_get_next &>/dev/null && type port_allocator_get_next_udp_range &>/dev/null; then
        read -r rtp_start rtp_end <<< "$(port_allocator_get_next_udp_range 100)"
        if [ -z "$http_port" ]; then
            http_port=$(port_allocator_get_next livekit_http 7879)
            webrtc_tcp_port=$(port_allocator_get_next livekit_tcp 7880)
        else
            webrtc_tcp_port=$((http_port + 1))
        fi
    else
        rtp_start=50000; rtp_end=50100
        http_port="${http_port:-7880}"
        webrtc_tcp_port=$((http_port + 1))
    fi

    print_header "Adding LiveKit: $name"
    local entry="${name}|${http_port}|${webrtc_tcp_port}|${rtp_start}|${rtp_end}|${cpu}|${memory}|${api_key}|${api_secret}"
    echo "$entry" >> "$LIVEKIT_ENV"
    type port_allocator_register &>/dev/null && port_allocator_register livekit_http "$http_port" livekit "$name" && port_allocator_register livekit_tcp "$webrtc_tcp_port" livekit "$name" && port_allocator_register livekit_udp "${rtp_start}-${rtp_end}" livekit "$name" || true

    CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_livekit_compose.sh"
    local dir="${ROOT}/livekit/${name}"
    cat > "${dir}/.env" << EOF
# LiveKit: $name
LIVEKIT_URL=ws://localhost:${http_port}
LIVEKIT_HTTP_URL=http://localhost:${http_port}
LIVEKIT_API_KEY=${api_key}
LIVEKIT_API_SECRET=${api_secret}
EOF
    print_success "LiveKit '$name' added (HTTP $http_port, WebRTC TCP $webrtc_tcp_port, RTP UDP $rtp_start-$rtp_end)"
    print_info "Start: ./scripts/container_manager.sh livekit start $name"
}

livekit_remove() {
    local name="$1"
    [[ -z "$name" ]] && { print_error "Name required"; exit 1; }
    grep -qE "^${name}\|" "$LIVEKIT_ENV" || { print_error "LiveKit instance '$name' not found"; exit 1; }
    print_header "Removing LiveKit: $name"
    sed -i.bak "/^${name}|/d" "$LIVEKIT_ENV" && rm -f "${LIVEKIT_ENV}.bak"
    type port_allocator_unregister_instance &>/dev/null && port_allocator_unregister_instance livekit "$name" || true
    [ -d "${ROOT}/livekit/${name}" ] && rm -rf "${ROOT}/livekit/${name}"
    CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_livekit_compose.sh"
    print_success "LiveKit '$name' removed"
}

livekit_start() {
    local names=("$@")
    [[ ${#names[@]} -eq 0 ]] && { print_error "Usage: $0 start <name> [name2 ...] or start-all"; exit 1; }
    print_header "Starting LiveKit"
    for n in "${names[@]}"; do
        grep -qE "^${n}\|" "$LIVEKIT_ENV" || { print_error "Not found: $n"; continue; }
        local dir="${ROOT}/livekit/${n}"
        [ -f "${dir}/docker-compose.yml" ] || CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_livekit_compose.sh"
        (cd "$dir" && docker compose up -d) && print_success "$n started" || print_error "Failed $n"
    done
}

livekit_start_all() {
    print_header "Starting all LiveKit"
    local list; list=$(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$LIVEKIT_ENV" 2>/dev/null | cut -d'|' -f1)
    [ -z "$list" ] && { print_info "No LiveKit instances"; return 0; }
    for n in $list; do livekit_start "$n"; done
}

livekit_stop() {
    local names=("$@")
    [[ ${#names[@]} -eq 0 ]] && { print_error "Usage: $0 stop <name> [name2 ...] or stop-all"; exit 1; }
    print_header "Stopping LiveKit"
    for n in "${names[@]}"; do
        local dir="${ROOT}/livekit/${n}"
        [ -f "${dir}/docker-compose.yml" ] && (cd "$dir" && docker compose stop) && print_success "$n stopped" || print_error "Failed or not found: $n"
    done
}

livekit_stop_all() {
    print_header "Stopping all LiveKit"
    local list; list=$(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$LIVEKIT_ENV" 2>/dev/null | cut -d'|' -f1)
    [ -z "$list" ] && { print_info "No LiveKit instances"; return 0; }
    for n in $list; do livekit_stop "$n"; done
}

livekit_show_ports() {
    print_header "LiveKit port assignments"
    printf "%-20s %-10s %-12s %-15s %-8s %-8s\n" "NAME" "HTTP" "WebRTC TCP" "RTP UDP" "CPU" "MEMORY"
    echo "--------------------------------------------------------------------------------"
    while IFS='|' read -r name http_port tcp_port rtp_start rtp_end cpu memory rest; do
        [[ "$name" =~ ^#.*$ ]] && continue
        [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
        printf "%-20s %-10s %-12s %-15s %-8s %-8s\n" "$name" "$http_port" "$tcp_port" "${rtp_start}-${rtp_end}" "${cpu:-1}" "${memory:-512m}"
    done < "$LIVEKIT_ENV" 2>/dev/null || true
    echo ""; print_info "WebSocket URL: ws://localhost:<HTTP_PORT>"
}

CMD="${1:-}"; shift 2>/dev/null || true
case "${CMD:-}" in
    add) livekit_add "$@" ;;
    remove|rm) livekit_remove "$1" ;;
    start) livekit_start "$@" ;;
    start-all) livekit_start_all ;;
    stop) livekit_stop "$@" ;;
    stop-all) livekit_stop_all ;;
    show-ports|ports) livekit_show_ports ;;
    generate) CONTAINER_PROJECT_ROOT="$ROOT" "$SCRIPT_DIR/helpers/generate_livekit_compose.sh" ;;
    *) echo "Usage: $0 {add|remove|start|stop|start-all|stop-all|show-ports|generate} [options]"; exit 1 ;;
esac
