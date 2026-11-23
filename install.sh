#!/usr/bin/env bash
#
# Claude Notify Installer
# Installs notification hooks for Claude Code
#

set -euo pipefail

# Parse arguments
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --dry-run|-n)
            DRY_RUN=true
            ;;
        --help|-h)
            echo "Usage: install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run, -n  Show what would be done without making changes"
            echo "  --help, -h     Show this help message"
            exit 0
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Installation directories
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-notify"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
VERSION_FILE="${CONFIG_DIR}/.version"

# Get current version from repo
get_repo_version() {
    if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
        cat "$SCRIPT_DIR/VERSION" | tr -d '[:space:]'
    else
        echo "0.0.0"
    fi
}

# Get installed version
get_installed_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE" | tr -d '[:space:]'
    else
        echo ""
    fi
}

# Compare semantic versions (returns: 0=equal, 1=first greater, 2=second greater)
compare_versions() {
    local v1="$1"
    local v2="$2"

    if [[ "$v1" == "$v2" ]]; then
        echo 0
        return
    fi

    local IFS='.'
    local i
    local v1_parts=($v1)
    local v2_parts=($v2)

    for ((i=0; i<3; i++)); do
        local v1_part="${v1_parts[i]:-0}"
        local v2_part="${v2_parts[i]:-0}"
        if ((v1_part > v2_part)); then
            echo 1
            return
        elif ((v1_part < v2_part)); then
            echo 2
            return
        fi
    done
    echo 0
}

# Logging functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
dry_run_msg() { echo -e "${YELLOW}[DRY-RUN]${NC} Would: $1"; }

# Execute command or show what would be done in dry-run mode
run_cmd() {
    if [[ "$DRY_RUN" == true ]]; then
        dry_run_msg "$*"
        return 0
    else
        "$@"
    fi
}

# Check for existing installation and handle upgrade
check_upgrade() {
    local repo_version=$(get_repo_version)
    local installed_version=$(get_installed_version)

    if [[ -z "$installed_version" ]]; then
        info "Fresh installation of Claude Notify v${repo_version}"
        return 0
    fi

    local comparison=$(compare_versions "$repo_version" "$installed_version")

    case $comparison in
        0)
            info "Claude Notify v${installed_version} is already installed (same version)"
            if [[ "$DRY_RUN" != true ]]; then
                read -p "Reinstall? [y/N] " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    info "Installation cancelled"
                    exit 0
                fi
            fi
            ;;
        1)
            success "Upgrading Claude Notify: v${installed_version} -> v${repo_version}"
            ;;
        2)
            warn "Installed version (v${installed_version}) is newer than repo (v${repo_version})"
            if [[ "$DRY_RUN" != true ]]; then
                read -p "Downgrade? [y/N] " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    info "Installation cancelled"
                    exit 0
                fi
            fi
            ;;
    esac
}

# Save installed version
save_version() {
    local version=$(get_repo_version)
    if [[ "$DRY_RUN" == true ]]; then
        dry_run_msg "echo $version > $VERSION_FILE"
    else
        echo "$version" > "$VERSION_FILE"
    fi
    info "Version $version recorded"
}

# Check dependencies
check_dependencies() {
    info "Checking dependencies..."

    local missing=()

    # jq is required to update Claude Code's JSON settings
    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    # notify-send (libnotify) is the only notification backend
    if ! command -v notify-send &>/dev/null; then
        missing+=("libnotify")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
        echo ""
        echo "Install them with:"
        echo "  Debian/Ubuntu: sudo apt install jq libnotify-bin"
        echo "  Fedora:        sudo dnf install jq libnotify"
        echo "  Arch:          sudo pacman -S jq libnotify"
        exit 1
    fi

    success "All required dependencies found"
}

# Check for Claude Code installation
check_claude_code() {
    info "Checking Claude Code installation..."

    if [[ ! -d "$HOME/.claude" ]]; then
        error "Claude Code configuration directory not found at ~/.claude"
        echo "Please ensure Claude Code is installed and has been run at least once."
        exit 1
    fi

    if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            dry_run_msg "Create $CLAUDE_SETTINGS with an empty object"
        else
            warn "Claude Code settings.json not found, will create it"
            mkdir -p "$HOME/.claude"
            echo '{}' > "$CLAUDE_SETTINGS"
        fi
    fi

    success "Claude Code installation found"
}

# Backup existing settings
backup_settings() {
    if [[ -f "$CLAUDE_SETTINGS" ]]; then
        local backup="${CLAUDE_SETTINGS}.backup.$(date +%Y%m%d_%H%M%S)"
        if [[ "$DRY_RUN" == true ]]; then
            dry_run_msg "cp $CLAUDE_SETTINGS $backup"
        else
            cp "$CLAUDE_SETTINGS" "$backup"
            info "Backed up settings to $backup"
        fi
    fi
}

# Create installation directories
create_directories() {
    info "Creating directories..."

    if [[ "$DRY_RUN" == true ]]; then
        dry_run_msg "mkdir -p $CONFIG_DIR/hooks"
        dry_run_msg "mkdir -p $ICON_DIR"
    else
        mkdir -p "$CONFIG_DIR/hooks"
        mkdir -p "$ICON_DIR"
    fi

    success "Directories created"
}

# Install hook scripts
install_hooks() {
    info "Installing hook scripts..."

    if [[ "$DRY_RUN" == true ]]; then
        dry_run_msg "cp $SCRIPT_DIR/hooks/notify.sh $CONFIG_DIR/hooks/"
        dry_run_msg "chmod +x $CONFIG_DIR/hooks/notify.sh"
    else
        cp "$SCRIPT_DIR/hooks/notify.sh" "$CONFIG_DIR/hooks/"
        chmod +x "$CONFIG_DIR/hooks/notify.sh"
    fi

    success "Hook scripts installed to $CONFIG_DIR/hooks/"
}

# Install configuration
install_config() {
    info "Installing configuration..."

    if [[ ! -f "$CONFIG_DIR/config.json" ]] || [[ "$DRY_RUN" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
                dry_run_msg "cp $SCRIPT_DIR/config/config.example.json $CONFIG_DIR/config.json"
                success "Configuration installed to $CONFIG_DIR/config.json"
            else
                info "Configuration already exists, skipping"
            fi
        else
            cp "$SCRIPT_DIR/config/config.example.json" "$CONFIG_DIR/config.json"
            success "Configuration installed to $CONFIG_DIR/config.json"
        fi
    else
        info "Configuration already exists, skipping"
    fi
}

# Install icon (if available)
install_icon() {
    info "Setting up notification icon..."

    local icon_name="claude-ai.png"

    # Check for existing Claude icon
    local existing_icon="$ICON_DIR/$icon_name"
    if [[ -f "$existing_icon" ]]; then
        success "Using existing Claude icon at $existing_icon"
        return
    fi

    # Check if we have an icon in the repo
    if [[ -f "$SCRIPT_DIR/icons/$icon_name" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            dry_run_msg "cp $SCRIPT_DIR/icons/$icon_name $ICON_DIR/"
        else
            cp "$SCRIPT_DIR/icons/$icon_name" "$ICON_DIR/"
        fi
        success "Icon installed to $ICON_DIR/$icon_name"
    else
        warn "No icon found. Notifications will use system default icon."
        info "You can add a custom icon later at $ICON_DIR/$icon_name"
    fi
}

# Merge one Claude Notify hook into the in-memory settings. Any earlier
# Claude Notify handler for the same event is replaced; other hooks are kept.
add_own_hook() {
    local event="$1"
    local matcher="$2"
    local ntype="$3"
    local cmd="$CONFIG_DIR/hooks/notify.sh --type $ntype"

    if [[ "$DRY_RUN" == true ]]; then
        if [[ -n "$matcher" ]]; then
            dry_run_msg "Add $event hook (matcher: $matcher): $cmd"
        else
            dry_run_msg "Add $event hook: $cmd"
        fi
        return 0
    fi

    new_settings=$(printf '%s' "$new_settings" | jq \
        --arg event "$event" \
        --arg matcher "$matcher" \
        --arg cmd "$cmd" \
        'def ours: [.hooks[]?.command] | map(tostring) | join(" ") | contains("claude-notify/hooks/notify.sh");
         .hooks = (.hooks // {}) |
         .hooks[$event] = (
             [ (.hooks[$event] // [])[] | select(ours | not) ]
             + [ { "matcher": $matcher, "hooks": [ { "type": "command", "command": $cmd } ] } ]
         )')
}

# Configure Claude Code hooks
configure_hooks() {
    info "Configuring Claude Code hooks..."

    if ! command -v jq &>/dev/null; then
        error "jq is required to update Claude Code settings"
        exit 1
    fi

    local current_settings
    if [[ -f "$CLAUDE_SETTINGS" ]]; then
        current_settings=$(cat "$CLAUDE_SETTINGS")
    else
        current_settings='{}'
    fi

    if ! printf '%s' "$current_settings" | jq -e . &>/dev/null; then
        error "Existing $CLAUDE_SETTINGS is not valid JSON"
        exit 1
    fi

    new_settings="$current_settings"

    # PermissionRequest fires immediately with the exact tool and command, so
    # Notification excludes permission_prompt to avoid a duplicate alert.
    add_own_hook "Notification" \
        "idle_prompt|agent_needs_input|elicitation_dialog|elicitation_url_dialog|quota_auto_resume_fired|quota_auto_resume_stale|quota_auto_resume_disabled" \
        "input"
    add_own_hook "PermissionRequest" "" "input"
    add_own_hook "Stop" "" "complete"
    add_own_hook "StopFailure" "" "error"
    add_own_hook "UserPromptSubmit" "" "prompt"

    if [[ "$DRY_RUN" == true ]]; then
        info "Hooks would be merged into $CLAUDE_SETTINGS (other hooks preserved)"
        return 0
    fi

    # Write updated settings
    printf '%s' "$new_settings" | jq '.' > "$CLAUDE_SETTINGS"

    success "Claude Code hooks configured"
}

# Test notification
test_notification() {
    if [[ "$DRY_RUN" == true ]]; then
        dry_run_msg "Send test notification via $CONFIG_DIR/hooks/notify.sh --test"
        return
    fi

    read -p "Send a test notification? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        return
    fi

    info "Sending test notification..."
    if "$CONFIG_DIR/hooks/notify.sh" --test; then
        success "Test notification sent!"
    else
        error "Test notification failed"
    fi
}

# Print summary
print_summary() {
    local version=$(get_repo_version)
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Claude Notify v${version} installed successfully!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo "Installation locations:"
    echo "  Config:  $CONFIG_DIR/config.json"
    echo "  Hooks:   $CONFIG_DIR/hooks/"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $CONFIG_DIR/config.json to customize notifications"
    echo "  2. Start using Claude Code - you'll now receive notifications!"
    echo ""
    echo "To uninstall, run: $SCRIPT_DIR/uninstall.sh"
    echo ""
}

# Main installation
main() {
    echo ""
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}  Claude Notify Installer${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}Running in DRY-RUN mode - no changes will be made${NC}"
        echo ""
    fi

    check_dependencies
    check_claude_code
    check_upgrade
    backup_settings
    create_directories
    install_hooks
    install_config
    install_icon
    configure_hooks
    save_version
    test_notification
    print_summary
}

main "$@"
