#!/usr/bin/env bash
#
# Claude Notify - Linux desktop notification script
# Sends notifications via notify-send (libnotify).
#
# Usage:
#   notify.sh --type input|complete|error
#   notify.sh --title "Title" --message "Message"
#   notify.sh --test
#

set -euo pipefail

# Error trap: output useful message if script fails unexpectedly
trap 'echo "Error: notify.sh failed at line $LINENO" >&2' ERR

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-notify"
CONFIG_FILE="${CONFIG_DIR}/config.json"
PROJECT_CONFIG_NAME=".claude-notify.json"
VERSION_FILE="${CONFIG_DIR}/.version"

# Defaults
DEFAULT_ICON=""
DEFAULT_URGENCY="normal"

# Notification presets
declare -A PRESET_TITLES=(
    [input]="Claude Code"
    [complete]="Claude Code"
    [error]="Claude Code"
)

declare -A PRESET_MESSAGES=(
    [input]="Claude needs your input"
    [complete]="Task completed"
    [error]="An error occurred"
)

declare -A PRESET_URGENCY=(
    [input]="normal"
    [complete]="low"
    [error]="critical"
)

declare -A PRESET_ICONS=(
    [input]="dialog-question"
    [complete]="dialog-ok"
    [error]="dialog-error"
)

declare -A PRESET_CATEGORIES=(
    [input]="im.received"
    [complete]="transfer.complete"
    [error]="im.error"
)

declare -A PRESET_ACTIONS=(
    [input]="view=View in Terminal"
    [complete]="view=View in Terminal"
    [error]="view=View Error"
)

# Parse command line arguments
TYPE=""
TITLE=""
MESSAGE=""
URGENCY=""
ICON=""
CATEGORY=""
ACTION=""
WAIT_FOR_ACTION=false
TEST_MODE=false
VALIDATE_MODE=false
VALIDATE_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --type|-t)
            TYPE="$2"
            shift 2
            ;;
        --title)
            TITLE="$2"
            shift 2
            ;;
        --message|-m)
            MESSAGE="$2"
            shift 2
            ;;
        --urgency|-u)
            URGENCY="$2"
            shift 2
            ;;
        --icon|-i)
            ICON="$2"
            shift 2
            ;;
        --category|-c)
            CATEGORY="$2"
            shift 2
            ;;
        --action|-a)
            ACTION="$2"
            shift 2
            ;;
        --wait|-w)
            WAIT_FOR_ACTION=true
            shift
            ;;
        --test)
            TEST_MODE=true
            shift
            ;;
        --validate)
            VALIDATE_MODE=true
            if [[ -n "${2:-}" && ! "$2" =~ ^-- ]]; then
                VALIDATE_FILE="$2"
                shift
            fi
            shift
            ;;
        --version|-V)
            if [[ -f "$VERSION_FILE" ]]; then
                echo "Claude Notify v$(tr -d '[:space:]' < "$VERSION_FILE")"
            else
                echo "Claude Notify (version unknown - not installed via installer)"
            fi
            exit 0
            ;;
        --help|-h)
            echo "Usage: notify.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --type, -t TYPE      Notification type: input, complete, error"
            echo "  --title TITLE        Custom notification title"
            echo "  --message, -m MSG    Custom notification message"
            echo "  --urgency, -u LEVEL  Urgency: low, normal, critical"
            echo "  --icon, -i PATH      Path to icon file"
            echo "  --category, -c CAT   Notification category (e.g., im.received)"
            echo "  --action, -a ACTION  Add action button (format: id=Label)"
            echo "  --wait, -w           Wait for action response"
            echo "  --test               Send a test notification"
            echo "  --validate [FILE]    Validate configuration file and exit"
            echo "  --version, -V        Show version information"
            echo "  --help, -h           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Find project-specific config file (walks up the directory tree)
# Security: only searches within the user's home directory to prevent
# loading configs from system directories or other users' directories.
find_project_config() {
    local dir="$PWD"
    local home_dir="${HOME:-}"

    [[ -n "$home_dir" ]] || return 1
    home_dir="${home_dir%/}"

    while [[ "$dir" == "$home_dir" || "$dir" == "$home_dir"/* ]]; do
        if [[ -f "$dir/$PROJECT_CONFIG_NAME" ]]; then
            echo "$dir/$PROJECT_CONFIG_NAME"
            return 0
        fi
        [[ "$dir" == "/" ]] && break
        dir="$(dirname "$dir")"
    done
    return 1
}

# Merge two JSON configs (second takes precedence)
merge_configs() {
    local base="$1"
    local overlay="$2"

    if ! command -v jq &>/dev/null; then
        # Without jq, just use overlay if it exists
        if [[ -f "$overlay" ]]; then
            cat "$overlay"
        else
            cat "$base"
        fi
        return
    fi

    # Deep merge: overlay values take precedence
    jq -s '.[0] * .[1]' "$base" "$overlay" 2>/dev/null
}

# Validate configuration file
validate_config() {
    local config_file="$1"
    local errors=()

    if [[ ! -f "$config_file" ]]; then
        echo "Config file not found: $config_file"
        return 1
    fi

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        echo "Warning: jq not installed, skipping config validation"
        return 0
    fi

    # Validate JSON syntax
    if ! jq '.' "$config_file" &>/dev/null; then
        echo "Invalid JSON syntax in $config_file"
        return 1
    fi

    # Validate urgency levels
    local urgency_fields=("input_needed" "task_complete" "error")
    local valid_urgencies="low normal critical"
    local field urgency
    for field in "${urgency_fields[@]}"; do
        urgency=$(jq -r ".notifications.${field}.urgency // \"normal\"" "$config_file" 2>/dev/null)
        if [[ -n "$urgency" && ! " $valid_urgencies " =~ " $urgency " ]]; then
            errors+=("Invalid urgency '$urgency' in notifications.${field}. Valid: $valid_urgencies")
        fi
    done

    # Report errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "Configuration errors in $config_file:"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        return 1
    fi

    return 0
}

# Effective merged configuration (set by load_config)
EFFECTIVE_CONFIG=""

# Read a value from the effective config, falling back to a default
cfg() {
    local filter="$1"
    local default="${2:-}"
    local value=""

    if [[ -n "$EFFECTIVE_CONFIG" ]] && command -v jq &>/dev/null; then
        value=$(printf '%s' "$EFFECTIVE_CONFIG" | jq -r "$filter // empty" 2>/dev/null || true)
        if [[ -n "$value" ]]; then
            printf '%s' "$value"
            return 0
        fi
    fi

    printf '%s' "$default"
}

# Map a notification type to its configuration key
config_type_key() {
    case "$1" in
        input)    echo "input_needed" ;;
        complete) echo "task_complete" ;;
        error)    echo "error" ;;
        *)        echo "$1" ;;
    esac
}

# Return whether a notification type is enabled ("true"/"false")
config_type_enabled() {
    local type_key="$1"

    if [[ -n "$EFFECTIVE_CONFIG" ]] && command -v jq &>/dev/null; then
        printf '%s' "$EFFECTIVE_CONFIG" \
            | jq -r "if (.notifications.${type_key}.enabled == false) then \"false\" else \"true\" end" 2>/dev/null \
            || echo "true"
    else
        echo "true"
    fi
}

# Load configuration
load_config() {
    local project_config=""

    CONFIG_ICON=""

    # Check for project-specific config
    project_config=$(find_project_config 2>/dev/null || echo "")

    if command -v jq &>/dev/null; then
        # Determine effective config (merge global + project)
        if [[ -f "$CONFIG_FILE" && -n "$project_config" && -f "$project_config" ]]; then
            EFFECTIVE_CONFIG=$(merge_configs "$CONFIG_FILE" "$project_config")
        elif [[ -n "$project_config" && -f "$project_config" ]]; then
            EFFECTIVE_CONFIG=$(cat "$project_config")
        elif [[ -f "$CONFIG_FILE" ]]; then
            EFFECTIVE_CONFIG=$(cat "$CONFIG_FILE")
        fi

        if [[ -n "$EFFECTIVE_CONFIG" ]]; then
            CONFIG_ICON=$(cfg '.icon' "")

            # Skip notification types disabled in configuration
            if [[ -n "$TYPE" ]]; then
                local type_key type_enabled
                type_key=$(config_type_key "$TYPE")
                type_enabled=$(config_type_enabled "$type_key")
                if [[ "$type_enabled" == "false" ]]; then
                    exit 0
                fi
            fi
        fi
    fi

    # Environment variable overrides
    ICON="${ICON:-${CLAUDE_NOTIFY_ICON:-${CONFIG_ICON:-$DEFAULT_ICON}}}"
}

# Expand ~ in paths
expand_path() {
    local path="$1"
    echo "${path/#\~/$HOME}"
}

# Send notification via notify-send (Linux)
send_notify_send() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"
    local icon="$4"
    local category="${5:-}"
    local action="${6:-}"
    local wait_for_action="${7:-false}"

    local args=()
    args+=("--urgency=$urgency")

    if [[ -n "$icon" ]]; then
        local expanded_icon
        expanded_icon=$(expand_path "$icon")
        if [[ -f "$expanded_icon" ]]; then
            args+=("--icon=$expanded_icon")
        else
            args+=("--icon=$icon")
        fi
    fi

    # Add notification category/hint
    if [[ -n "$category" ]]; then
        args+=("--category=$category")
    fi

    # Add action buttons (only if waiting, since --action blocks)
    if [[ "$wait_for_action" == true ]]; then
        if [[ -n "$action" ]]; then
            args+=("--action=$action")
        fi
        args+=("--wait")
    fi

    args+=("--app-name=Claude Code")
    args+=("$title")
    args+=("$message")

    local result
    if ! result=$(notify-send "${args[@]}" 2>&1); then
        echo "notify-send failed: ${result:-unknown error}" >&2
        return 1
    fi

    # Return the clicked action (if any)
    if [[ -n "$result" ]]; then
        echo "$result"
    fi
}

# Main function
main() {
    # Validate mode - just validate config and exit
    if [[ "$VALIDATE_MODE" == true ]]; then
        local file_to_validate="${VALIDATE_FILE:-$CONFIG_FILE}"
        if [[ -f "$file_to_validate" ]]; then
            if validate_config "$file_to_validate"; then
                echo "Configuration is valid: $file_to_validate"
                exit 0
            else
                exit 1
            fi
        else
            echo "No configuration file found at $file_to_validate"
            echo "Using default settings."
            exit 0
        fi
    fi

    load_config

    # Test mode
    if [[ "$TEST_MODE" == true ]]; then
        TYPE="${TYPE:-input}"
        TITLE="${TITLE:-Test Notification}"
        MESSAGE="${MESSAGE:-This is a test notification from Claude Notify}"
    fi

    # Apply presets and per-type configuration
    if [[ -n "$TYPE" ]]; then
        local type_key
        type_key=$(config_type_key "$TYPE")

        TITLE="${TITLE:-$(cfg ".notifications.${type_key}.title" "${PRESET_TITLES[$TYPE]:-Claude Code}")}"
        MESSAGE="${MESSAGE:-$(cfg ".notifications.${type_key}.message" "${PRESET_MESSAGES[$TYPE]:-Notification}")}"
        URGENCY="${URGENCY:-$(cfg ".notifications.${type_key}.urgency" "${PRESET_URGENCY[$TYPE]:-normal}")}"
        if [[ -z "$ICON" ]]; then
            ICON=$(cfg ".notifications.${type_key}.icon" "${PRESET_ICONS[$TYPE]:-}")
        fi
        if [[ -z "$CATEGORY" ]]; then
            CATEGORY="${PRESET_CATEGORIES[$TYPE]:-}"
        fi
        if [[ -z "$ACTION" ]]; then
            ACTION="${PRESET_ACTIONS[$TYPE]:-}"
        fi
    fi

    # Require title and message
    if [[ -z "$TITLE" || -z "$MESSAGE" ]]; then
        echo "Error: --title and --message are required, or use --type" >&2
        exit 1
    fi

    # Set defaults
    URGENCY="${URGENCY:-$DEFAULT_URGENCY}"

    # notify-send is the only supported backend
    if ! command -v notify-send &>/dev/null; then
        echo "Warning: notify-send not found. Install libnotify to receive desktop notifications." >&2
        exit 0
    fi

    send_notify_send "$TITLE" "$MESSAGE" "$URGENCY" "$ICON" "$CATEGORY" "$ACTION" "$WAIT_FOR_ACTION"

    if [[ "$TEST_MODE" == true ]]; then
        echo "Test notification sent via notify-send"
    fi
}

main "$@"
