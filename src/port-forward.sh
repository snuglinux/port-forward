#!/bin/bash
# Port Forward Manager v2.0
# Universal port forwarding using socat with multi-language support

set -euo pipefail
shopt -s extglob
# Enable debug tracing if DEBUG=true in config/environment
if [[ "${DEBUG:-false}" == "true" ]]; then
    set -x
fi
# Configuration
CONFIG_DIR="/etc/port-forward"
PORTS_FILE="${CONFIG_DIR}/ports.conf"
MAIN_CONFIG="${CONFIG_DIR}/port-forward.conf"
LOCALE_DIR="/usr/share/port-forward/locale"
LOG_DIR="/var/log/port-forward"
PID_DIR="/run/port-forward"

# Default values
DEFAULT_LANG="en"
LOGGING_ENABLED=false
LOG_FILE="${LOG_DIR}/port-forward.log"
RUN_AS_USER=$(whoami)

# Import configuration if exists
if [[ -f "$MAIN_CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$MAIN_CONFIG"
fi

# Function to detect language
detect_language() {
    local lang="${LANGUAGE:-AUTO}"

    if [[ "$lang" == "AUTO" ]]; then
        local sys_lang="${LANG:-en_US.UTF-8}"
        sys_lang="${sys_lang%_*}"

        if [[ -f "${LOCALE_DIR}/${sys_lang}.json" ]]; then
            echo "$sys_lang"
        else
            echo "$DEFAULT_LANG"
        fi
    else
        echo "$lang"
    fi
}

CURRENT_LANG=$(detect_language)

# Localization support
get_text() {
    local key="$1"
    local lang="${2:-$CURRENT_LANG}"
    local locale_file="${LOCALE_DIR}/${lang}.json"

    if [[ -f "$locale_file" ]]; then
        jq -r ".$key // \"$key\"" "$locale_file" 2>/dev/null || echo "$key"
    else
        echo "$key"
    fi
}

# Create directories with proper permissions
setup_directories() {
    # Create directories if they don't exist
    mkdir -p "$LOG_DIR" 2>/dev/null || {
        # If /var/log/port-forward fails, try /tmp
        LOG_DIR="/tmp/port-forward"
        LOG_FILE="${LOG_DIR}/port-forward.log"
        mkdir -p "$LOG_DIR"
    }

    mkdir -p "$PID_DIR" 2>/dev/null || {
        PID_DIR="/tmp/port-forward-pids"
        mkdir -p "$PID_DIR"
    }

    mkdir -p "$CONFIG_DIR" 2>/dev/null || true
    mkdir -p "${LOCALE_DIR}" 2>/dev/null || true

    # Set permissions (only if we can)
    chmod 755 "$LOG_DIR" 2>/dev/null || true
    chmod 755 "$PID_DIR" 2>/dev/null || true
    chmod 755 "$CONFIG_DIR" 2>/dev/null || true
}

# Ensure log file exists and is writable
ensure_log_file() {
    # If logging is disabled, don't create log file
    [[ "$LOGGING_ENABLED" != "true" ]] && return 0

    # Create directory first
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || {
        echo "Warning: Cannot create log directory. Using /tmp instead." >&2
        LOG_FILE="/tmp/port-forward.log"
    }

    # Create log file if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        if touch "$LOG_FILE" 2>/dev/null; then
            chmod 644 "$LOG_FILE" 2>/dev/null || true
            return 0
        else
            echo "Warning: Cannot create log file at $LOG_FILE" >&2
            LOGGING_ENABLED=false
            return 1
        fi
    fi

    # Check if existing file is writable
    if [[ -w "$LOG_FILE" ]]; then
        return 0
    else
        echo "Warning: Log file exists but is not writable: $LOG_FILE" >&2
        LOGGING_ENABLED=false
        return 1
    fi
}

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Always output to console
    case "$level" in
        "ERROR")
            echo "$(get_text "error"): $message" >&2
            ;;
        "INFO")
            echo "$(get_text "info"): $message"
            ;;
        "WARN")
            echo "$(get_text "warning"): $message" >&2
            ;;
        *)
            echo "$message"
            ;;
    esac

    # Log to file if enabled
    if [[ "$LOGGING_ENABLED" == "true" ]]; then
        if ensure_log_file; then
            echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || {
                echo "Warning: Failed to write to log file" >&2
            }
        fi
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()

    for cmd in socat jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_message "ERROR" "$(get_text "missing_deps"): ${missing[*]}"
        exit 1
    fi
}

# Start port forwarding
start_forward() {
    local local_port="$1"
    local destination="$2"
    local proto="${3:-tcp}"
    local pid_file="${PID_DIR}/port_${local_port}.pid"

    # Check if port is already in use (optional)
    if [[ "${CHECK_PORTS_BEFORE_START:-true}" == "true" ]]; then
        if [[ "$proto" == "udp" ]]; then
            if ss -uln 2>/dev/null | grep -q ":$local_port "; then
                log_message "WARN" "$(get_text "port_in_use"): $local_port"
                return 1
            fi
        else
            if ss -tln 2>/dev/null | grep -q ":$local_port "; then
                log_message "WARN" "$(get_text "port_in_use"): $local_port"
                return 1
            fi
        fi
    fi

    # Build socat command
    local socat_cmd=""
    if [[ "$proto" == "udp" ]]; then
        socat_cmd="socat UDP-LISTEN:${local_port},fork,reuseaddr UDP:${destination}"
    else
        socat_cmd="socat TCP-LISTEN:${local_port},fork,reuseaddr TCP:${destination}"
    fi

    # Add extra options if specified
    if [[ -n "${EXTRA_SOCAT_OPTS:-}" ]]; then
        socat_cmd="${socat_cmd}${EXTRA_SOCAT_OPTS}"
    fi

    log_message "INFO" "$(get_text "starting_forward"): $local_port -> $destination ($proto)"

    # Run socat in background
    if [[ "$LOGGING_ENABLED" == "true" ]]; then
        eval "$socat_cmd" >> "$LOG_FILE" 2>&1 &
    else
        eval "$socat_cmd" >/dev/null 2>&1 &
    fi

    local pid=$!

    # Save PID to file
    echo "$pid" > "$pid_file"
    chmod 644 "$pid_file" 2>/dev/null || true

    # Wait and check if process is running
    sleep 0.5
    if kill -0 "$pid" 2>/dev/null; then
        log_message "INFO" "$(get_text "forward_started"): $local_port (PID: $pid)"
        return 0
    else
        log_message "ERROR" "$(get_text "forward_failed"): $local_port"
        rm -f "$pid_file" 2>/dev/null || true
        return 1
    fi
}

# Parse ports configuration file
parse_ports_file() {
    local file="$1"
    local -n ports_array="$2"

    if [[ ! -f "$file" ]]; then
        log_message "ERROR" "$(get_text "no_ports_file"): $file"
        return 1
    fi

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((++line_num))

        # Remove comments and trim whitespace
        line="${line%%#*}"
        line="${line##*( )}"
        line="${line%%*( )}"
        [[ -z "$line" ]] && continue

        # Parse formats
        local local_port=""
        local destination=""
        local proto="tcp"

        # Format 1: <local_port> <destination_ip:destination_port> [tcp|udp]
        if [[ "$line" =~ ^([0-9]+)[[:space:]]+([^[:space:]]+:[0-9]+)([[:space:]]+(tcp|udp))?$ ]]; then
            local_port="${BASH_REMATCH[1]}"
            destination="${BASH_REMATCH[2]}"
            proto="${BASH_REMATCH[4]:-tcp}"

        # Format 2: <local_port> <destination_ip> <destination_port> [tcp|udp]
        elif [[ "$line" =~ ^([0-9]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([0-9]+)([[:space:]]+(tcp|udp))?$ ]]; then
            local_port="${BASH_REMATCH[1]}"
            destination="${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
            proto="${BASH_REMATCH[5]:-tcp}"
        else
            log_message "WARN" "$(get_text "invalid_line"): '$line' ($(get_text "line"): $line_num)"
            continue
        fi

        # Validate port numbers
        if [[ "$local_port" -lt 1 ]] || [[ "$local_port" -gt 65535 ]]; then
            log_message "WARN" "$(get_text "invalid_port"): $local_port"
            continue
        fi

        ports_array["$local_port"]="$destination $proto"

    done < "$file"

    return 0
}

# Main commands
cmd_start() {
    log_message "INFO" "$(get_text "starting_service")"
    check_dependencies
    setup_directories

    declare -A ports
    parse_ports_file "$PORTS_FILE" ports

    if [[ ${#ports[@]} -eq 0 ]]; then
        log_message "WARN" "$(get_text "no_ports_configured")"
        return 0
    fi

    for local_port in "${!ports[@]}"; do
        read destination proto <<< "${ports[$local_port]}"
        start_forward "$local_port" "$destination" "$proto" || true
    done
}

cmd_stop() {
    log_message "INFO" "$(get_text "stopping_service")"

    if [[ -d "$PID_DIR" ]]; then
        for pid_file in "$PID_DIR"/port_*.pid; do
            [[ -f "$pid_file" ]] || continue

            local pid=$(cat "$pid_file" 2>/dev/null)
            local port="${pid_file##*port_}"
            port="${port%.pid}"

            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null
                sleep 0.2

                if kill -0 "$pid" 2>/dev/null; then
                    kill -9 "$pid" 2>/dev/null
                    log_message "INFO" "$(get_text "force_stopped"): $port"
                else
                    log_message "INFO" "$(get_text "stopped"): $port"
                fi
            fi

            rm -f "$pid_file" 2>/dev/null || true
        done
    fi

    # NOTE:
    # We intentionally do NOT pkill generic socat listeners, because that may kill
    # unrelated forwarding services on the same host. We only stop processes that
    # we started and recorded in PID files above.
}

cmd_restart() {
    cmd_stop
    sleep 1
    cmd_start
}

cmd_status() {
    echo "=== $(get_text "port_forward_status") ==="
    echo "$(get_text "config_file"): $PORTS_FILE"
    echo "$(get_text "logging_enabled"): $LOGGING_ENABLED"
    echo "$(get_text "running_as_user"): $RUN_AS_USER"
    echo "$(get_text "log_file"): $LOG_FILE"
    echo ""

    if [[ -d "$PID_DIR" ]]; then
        local active_count=0
        local inactive_count=0

        for pid_file in "$PID_DIR"/port_*.pid; do
            [[ -f "$pid_file" ]] || continue

            local pid=$(cat "$pid_file" 2>/dev/null)
            local port="${pid_file##*port_}"
            port="${port%.pid}"

            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                echo "✅ $(get_text "port"): $port - $(get_text "pid"): $pid ($(get_text "status_active"))"
                ((active_count++))
            else
                echo "❌ $(get_text "port"): $port ($(get_text "status_inactive"))"
                ((inactive_count++))
                rm -f "$pid_file" 2>/dev/null || true
            fi
        done

        echo ""
        echo "$(get_text "active_ports"): $active_count"
        echo "$(get_text "inactive_ports"): $inactive_count"
    else
        echo "$(get_text "service_not_running")"
    fi
}

cmd_reload() {
    log_message "INFO" "$(get_text "reloading_config")"
    cmd_stop
    sleep 0.5
    cmd_start
}

# Show help
show_help() {
    cat << EOF
$(get_text "app_name") v2.0 - $(get_text "app_description")

$(get_text "usage"): $0 {start|stop|restart|status|reload|help}

$(get_text "commands"):
  start    - $(get_text "cmd_start_help")
  stop     - $(get_text "cmd_stop_help")
  restart  - $(get_text "cmd_restart_help")
  status   - $(get_text "cmd_status_help")
  reload   - $(get_text "cmd_reload_help")
  help     - $(get_text "cmd_help_help")

$(get_text "config_files"):
  $MAIN_CONFIG    - $(get_text "main_config_file")
  $PORTS_FILE     - $(get_text "ports_config_file")

$(get_text "examples"):
  $0 start
  $0 status
  $0 reload

$(get_text "documentation"): https://github.com/khvalera/port-forward
EOF
}

# Main function
main() {
    local action="${1:-start}"

    case "$action" in
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart
            ;;
        status)
            cmd_status
            ;;
        reload)
            cmd_reload
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "$(get_text "invalid_command"): $action"
            show_help
            exit 1
            ;;
    esac
}

# Signal handlers
trap 'log_message "INFO" "$(get_text "received_signal")"; cmd_stop; exit 0' INT TERM

# Entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
