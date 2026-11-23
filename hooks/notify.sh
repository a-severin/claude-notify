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
DEMO_MODE=false
PREVIEW_MODE=false
TITLE_USER_SET=false
MESSAGE_USER_SET=false
DEMO_DURATION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --type|-t)
            TYPE="$2"
            shift 2
            ;;
        --title)
            TITLE="$2"
            TITLE_USER_SET=true
            shift 2
            ;;
        --message|-m)
            MESSAGE="$2"
            MESSAGE_USER_SET=true
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
        --demo)
            DEMO_MODE=true
            shift
            ;;
        --preview)
            PREVIEW_MODE=true
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
            echo "  --type, -t TYPE      Notification type: input, complete, error, prompt"
            echo "  --title TITLE        Custom notification title"
            echo "  --message, -m MSG    Custom notification message"
            echo "  --urgency, -u LEVEL  Urgency: low, normal, critical"
            echo "  --icon, -i PATH      Path to icon file"
            echo "  --category, -c CAT   Notification category (e.g., im.received)"
            echo "  --action, -a ACTION  Add action button (format: id=Label)"
            echo "  --wait, -w           Wait for action response"
            echo "  --test               Send a test notification"
            echo "  --demo               Render using a synthetic hook payload (prototype)"
            echo "  --preview            Print the rendered title and body"
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

# Read a boolean config value (accepts only the literal "true")
# Note: cfg() cannot be used here because jq's `//` treats false as absent.
cfg_bool() {
    local filter="$1"
    local default="$2"
    local value=""

    if [[ -n "$EFFECTIVE_CONFIG" ]] && command -v jq &>/dev/null; then
        value=$(printf '%s' "$EFFECTIVE_CONFIG" | jq -r "$filter" 2>/dev/null || true)
        case "$value" in
            true)  return 0 ;;
            false) return 1 ;;
        esac
    fi

    [[ "$default" == "true" ]]
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

# ---------------------------------------------------------------------------
# Notification content composition
#
# Claude Code passes a JSON payload on stdin. Historically this script ignored
# it, which is why every notification said the same thing. The helpers below
# read that payload and build a notification that identifies the session.
# ---------------------------------------------------------------------------

HOOK_JSON=""

# Read the hook payload from stdin. Interactive runs (stdin is a TTY) skip it.
read_hook_input() {
    local raw
    if [[ -t 0 ]]; then
        return 0
    fi
    raw=$(cat 2>/dev/null || true)
    if [[ -z "$raw" ]]; then
        return 0
    fi
    if command -v jq &>/dev/null && printf '%s' "$raw" | jq -e . &>/dev/null; then
        HOOK_JSON="$raw"
    fi
}

# Read one field from the hook payload. Prints nothing when unavailable.
hook_get() {
    local filter="$1"
    if [[ -z "$HOOK_JSON" ]] || ! command -v jq &>/dev/null; then
        return 0
    fi
    printf '%s' "$HOOK_JSON" | jq -r "$filter" 2>/dev/null || true
}

# Synthetic payload so layouts can be previewed without a live event.
load_demo_payload() {
    local cwd="$PWD"
    local sid="9568ef85-ec86-4f84-b391-89cfacfbcf7b"

    if ! command -v jq &>/dev/null; then
        return 0
    fi

    case "${TYPE:-input}" in
        complete)
            HOOK_JSON=$(jq -nc --arg c "$cwd" --arg s "$sid" '{
                session_id: $s,
                cwd: $c,
                hook_event_name: "Stop",
                permission_mode: "default",
                session_title: "Notification content options for notify.sh",
                last_assistant_message: "Refactored notify.sh to read hook JSON from stdin and render project, branch and session context in desktop notifications.",
                background_tasks: [
                    {id: "t1", type: "shell", status: "running", description: "tail logs"}
                ]
            }')
            DEMO_DURATION=252
            ;;
        error)
            HOOK_JSON=$(jq -nc --arg c "$cwd" --arg s "$sid" '{
                session_id: $s,
                cwd: $c,
                hook_event_name: "StopFailure",
                session_title: "Notification content options for notify.sh",
                error: "rate_limit",
                error_details: "429 Too Many Requests",
                last_assistant_message: "API Error: Rate limit reached"
            }')
            ;;
        *)
            HOOK_JSON=$(jq -nc --arg c "$cwd" --arg s "$sid" '{
                session_id: $s,
                cwd: $c,
                hook_event_name: "PermissionRequest",
                permission_mode: "default",
                session_title: "Notification content options for notify.sh",
                tool_name: "Bash",
                tool_input: {command: "git push origin main"}
            }')
            ;;
    esac
}

# Replace the home directory with ~ for compact display.
shorten_path() {
    local p="$1"
    local tilde='~'
    if [[ -n "${HOME:-}" && "$p" == "$HOME"* ]]; then
        p="${tilde}${p#"$HOME"}"
    fi
    printf '%s' "$p"
}

# Collapse newlines and repeated whitespace into single spaces, then trim.
squash_whitespace() {
    local text="$1"
    text="${text//$'\n'/ }"
    text="${text//$'\t'/ }"
    text=$(printf '%s' "$text" | tr -s ' ')
    text="${text#"${text%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    printf '%s' "$text"
}

# Print only the first non-empty line of a block of text.
first_line() {
    printf '%s\n' "$1" | awk 'NF { print; exit }'
}

# Current git branch (or short SHA when detached). Empty outside a repo.
git_branch() {
    local dir="$1"
    local branch=""
    if [[ -z "$dir" || ! -d "$dir" ]] || ! command -v git &>/dev/null; then
        return 0
    fi
    branch=$(timeout 1 git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    if [[ "$branch" == "HEAD" ]]; then
        branch=$(timeout 1 git -C "$dir" rev-parse --short HEAD 2>/dev/null || true)
    fi
    printf '%s' "$branch"
}

# Last value of a given entry type in a transcript (e.g. ai-title, last-prompt).
transcript_last() {
    local tp="$1" entry_type="$2" field="$3"
    if [[ -z "$tp" || ! -f "$tp" ]] || ! command -v jq &>/dev/null; then
        return 0
    fi
    timeout 2 jq -r "select(.type == \"$entry_type\") | .$field // empty" "$tp" 2>/dev/null | tail -n 1
}

human_duration() {
    local s="$1"
    if (( s < 0 )); then
        s=0
    fi
    if (( s < 60 )); then
        printf '%ds' "$s"
    elif (( s < 3600 )); then
        printf '%dm%ds' $(( s / 60 )) $(( s % 60 ))
    else
        printf '%dh%dm' $(( s / 3600 )) $(( s % 3600 / 60 ))
    fi
}

# Elapsed time for a session, when a UserPromptSubmit hook recorded a start.
session_duration() {
    local session_id="$1"
    local start_file start now

    if [[ -n "$DEMO_DURATION" ]]; then
        human_duration "$DEMO_DURATION"
        return 0
    fi
    if [[ -z "$session_id" ]]; then
        return 0
    fi
    start_file="$CONFIG_DIR/sessions/${session_id}.start"
    if [[ ! -f "$start_file" ]]; then
        return 0
    fi
    start=$(tr -dc '0-9' < "$start_file" 2>/dev/null || true)
    if [[ -z "$start" ]]; then
        return 0
    fi
    now=$(date +%s)
    human_duration $(( now - 10#$start ))
}

# The "what happened" line, derived from the hook event.
compose_detail() {
    local event tool cmd fp msg error_type last
    event=$(hook_get '.hook_event_name // empty')

    case "$event" in
        PermissionRequest)
            tool=$(hook_get '.tool_name // empty')
            case "$tool" in
                Bash)
                    cmd=$(hook_get '.tool_input.command // empty')
                    printf 'Approve Bash: %s' "$cmd"
                    ;;
                Edit|Write|Read|MultiEdit|NotebookEdit)
                    fp=$(hook_get '.tool_input.file_path // empty')
                    printf 'Approve %s: %s' "$tool" "$(shorten_path "$fp")"
                    ;;
                "")
                    hook_get '.message // empty'
                    ;;
                *)
                    printf 'Approve %s' "$tool"
                    ;;
            esac
            ;;
        Notification)
            msg=$(hook_get '.message // empty')
            printf '%s' "$msg"
            ;;
        Stop)
            last=$(hook_get '.last_assistant_message // empty')
            first_line "$last"
            ;;
        StopFailure)
            error_type=$(hook_get '.error // empty')
            last=$(hook_get '.last_assistant_message // empty')
            if [[ -n "$last" ]]; then
                printf '%s' "$last"
            elif [[ -n "$error_type" ]]; then
                printf 'Error: %s' "$error_type"
            fi
            ;;
        *)
            printf ''
            ;;
    esac
}

# Build TITLE and MESSAGE from the hook payload and local context.
compose_notification() {
    local cwd session_id sess_short title detail branch bg_count
    local line1 line2 tp error_type notification_type duration
    local prefix max_detail

    prefix=$(cfg '.context.title_prefix' 'Claude Code')
    if [[ -z "$prefix" ]]; then
        prefix="Claude Code"
    fi

    max_detail=$(cfg '.context.max_detail_length' '160')
    if [[ ! "$max_detail" =~ ^[0-9]+$ ]] || (( max_detail < 20 )); then
        max_detail=160
    fi

    cwd=$(hook_get '.cwd // empty')
    if [[ -z "$cwd" ]]; then
        cwd="$PWD"
    fi
    session_id=$(hook_get '.session_id // empty')
    sess_short=""
    if cfg_bool '.context.show_session' 'true'; then
        sess_short="${session_id:0:8}"
    fi

    # Session title: explicit title, then generated transcript title, then prompt
    title=$(hook_get '.session_title // empty')
    if [[ -z "$title" ]]; then
        tp=$(hook_get '.transcript_path // empty')
        if [[ -n "$tp" ]]; then
            title=$(transcript_last "$tp" "ai-title" "aiTitle")
        fi
        if [[ -z "$title" && -n "$tp" ]]; then
            title=$(transcript_last "$tp" "last-prompt" "lastPrompt")
        fi
    fi
    title=$(squash_whitespace "$title")
    if ! cfg_bool '.context.show_session_title' 'true'; then
        title=""
    fi
    if (( ${#title} > 60 )); then
        title="${title:0:60}…"
    fi

    branch=""
    if cfg_bool '.context.show_branch' 'true'; then
        branch=$(git_branch "$cwd")
    fi

    # Detail line
    if [[ "$MESSAGE_USER_SET" == true ]]; then
        detail="$MESSAGE"
    else
        detail=$(compose_detail)
        if [[ -z "$detail" ]]; then
            detail="$MESSAGE"
        fi
    fi
    detail=$(squash_whitespace "$detail")
    if (( ${#detail} > max_detail )); then
        detail="${detail:0:max_detail}…"
    fi

    # Title line
    if [[ "$TITLE_USER_SET" != true ]]; then
        case "$TYPE" in
            complete)
                duration=$(session_duration "$session_id")
                if [[ -n "$duration" ]]; then
                    TITLE="$prefix · done · $duration"
                else
                    TITLE="$prefix · done"
                fi
                ;;
            error)
                error_type=$(hook_get '.error // empty')
                if [[ -n "$error_type" ]]; then
                    TITLE="$prefix · failed ($error_type)"
                else
                    TITLE="$prefix · failed"
                fi
                ;;
            input)
                notification_type=$(hook_get '.notification_type // empty')
                case "$notification_type" in
                    idle_prompt) TITLE="$prefix · waiting" ;;
                    *)           TITLE="$prefix · needs you" ;;
                esac
                ;;
        esac
    fi

    # Body: where, then which session, then what happened
    line1="$(shorten_path "$cwd")"
    if [[ -n "$branch" ]]; then
        line1="$line1 · $branch"
    fi

    line2=""
    if [[ -n "$sess_short" ]]; then
        line2="Session $sess_short"
        if [[ -n "$title" ]]; then
            line2="$line2 — \"$title\""
        fi
    fi

    MESSAGE="$line1"
    if [[ -n "$line2" ]]; then
        MESSAGE="$MESSAGE"$'\n'"$line2"
    fi
    if [[ -n "$detail" ]]; then
        MESSAGE="$MESSAGE"$'\n'"$detail"
    fi

    bg_count=$(hook_get '.background_tasks | length')
    if [[ "$bg_count" =~ ^[0-9]+$ ]] && (( bg_count > 0 )); then
        MESSAGE="$MESSAGE"$'\n'"$bg_count background task(s) still running"
    fi
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
    read_hook_input

    # Test mode
    if [[ "$TEST_MODE" == true ]]; then
        TYPE="${TYPE:-input}"
        if [[ "$DEMO_MODE" != true ]]; then
            TITLE="${TITLE:-Test Notification}"
            MESSAGE="${MESSAGE:-This is a test notification from Claude Notify}"
            TITLE_USER_SET=true
            MESSAGE_USER_SET=true
        fi
    fi

    # Prototype: --demo without a type shows the "needs input" layout.
    if [[ "$DEMO_MODE" == true && -z "$TYPE" ]]; then
        TYPE=input
    fi

    # Prompt bookkeeping: record the turn start so Stop can report a duration.
    if [[ "$TYPE" == "prompt" ]]; then
        local prompt_session
        prompt_session=$(hook_get '.session_id // empty')
        if [[ -n "$prompt_session" ]]; then
            mkdir -p "$CONFIG_DIR/sessions" 2>/dev/null || true
            date +%s > "$CONFIG_DIR/sessions/${prompt_session}.start" 2>/dev/null || true
            # Drop timestamps for sessions that have been idle for a day.
            find "$CONFIG_DIR/sessions" -type f -name '*.start' -mmin +1440 -delete 2>/dev/null || true
        fi
        exit 0
    fi

    # Prototype: substitute a synthetic payload when no live event is available.
    if [[ "$DEMO_MODE" == true ]]; then
        load_demo_payload
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

    # Compose content from the hook payload and local context
    if [[ -n "$TYPE" ]] && cfg_bool '.context.enabled' 'true'; then
        compose_notification
    fi

    if [[ "$PREVIEW_MODE" == true ]]; then
        printf 'TITLE │ %s\n' "$TITLE"
        printf 'BODY  │\n'
        printf '%s\n' "$MESSAGE" | sed 's/^/      │ /'
        printf '%s\n' '------'
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

    # Hook invocations must not report errors to Claude Code; a failed
    # notification is not a reason to add a hook-error notice to the session.
    if ! send_notify_send "$TITLE" "$MESSAGE" "$URGENCY" "$ICON" "$CATEGORY" "$ACTION" "$WAIT_FOR_ACTION"; then
        if [[ "$TEST_MODE" == true ]]; then
            exit 1
        fi
        exit 0
    fi

    if [[ "$TEST_MODE" == true ]]; then
        echo "Test notification sent via notify-send"
    fi
}

main "$@"
