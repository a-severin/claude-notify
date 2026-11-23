#!/usr/bin/env bash
#
# Claude Notify Uninstaller
# Removes notification hooks from Claude Code
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation directories
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-notify"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons"

# Logging functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Remove hooks from Claude Code settings
remove_hooks() {
    info "Removing hooks from Claude Code settings..."

    if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
        warn "Claude Code settings not found, skipping hook removal"
        return
    fi

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        error "jq is required to modify settings. Please remove hooks manually from $CLAUDE_SETTINGS"
        return 1
    fi

    # Backup settings
    local backup="${CLAUDE_SETTINGS}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CLAUDE_SETTINGS" "$backup"
    info "Backed up settings to $backup"

    # Read current settings
    local current_settings
    current_settings=$(cat "$CLAUDE_SETTINGS")

    # Count our handlers before removal (any event, any matcher group)
    local ours_count
    ours_count=$(printf '%s' "$current_settings" | jq \
        '[.hooks // {} | .[]? | .[]? | .hooks[]?
          | select((.command // "") | tostring | contains("claude-notify/hooks/notify.sh"))]
         | length' 2>/dev/null || echo "0")

    if [[ "$ours_count" == "0" ]]; then
        info "No Claude Notify hooks found to remove"
    else
        # Remove every handler group that references our script, preserving
        # hooks owned by other tools.
        current_settings=$(printf '%s' "$current_settings" | jq '
            def ours: [.hooks[]?.command] | map(tostring) | join(" ")
                      | contains("claude-notify/hooks/notify.sh");
            if (.hooks | type) == "object" then
                .hooks |= with_entries(
                    .value |= (if type == "array" then map(select(ours | not)) else . end)
                )
            else . end
        ')

        # Drop events that no longer have any hook groups
        current_settings=$(printf '%s' "$current_settings" | jq '
            if (.hooks | type) == "object" then
                .hooks |= with_entries(select((.value | type) == "array" and (.value | length) > 0))
            else . end
        ')

        success "Removed Claude Notify hooks ($ours_count handler(s))"
    fi

    # Clean up empty hooks object
    local hooks_count
    hooks_count=$(printf '%s' "$current_settings" | jq '.hooks | length' 2>/dev/null || echo "0")
    if [[ "$hooks_count" == "0" ]]; then
        current_settings=$(printf '%s' "$current_settings" | jq 'del(.hooks)')
    fi

    # Write updated settings
    printf '%s' "$current_settings" | jq '.' > "$CLAUDE_SETTINGS"
}

# Remove configuration files
remove_config() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        info "Configuration directory not found, nothing to remove"
        return
    fi

    # Security: Validate that CONFIG_DIR is within expected paths
    # to prevent accidental deletion of system directories
    local resolved_path
    resolved_path=$(cd "$CONFIG_DIR" 2>/dev/null && pwd -P)
    local expected_parent="${XDG_CONFIG_HOME:-$HOME/.config}"

    if [[ -z "$resolved_path" ]]; then
        error "Cannot resolve config directory path"
        return 1
    fi

    if [[ "$resolved_path" != "$expected_parent/claude-notify" ]]; then
        error "Config directory path mismatch. Expected: $expected_parent/claude-notify, Got: $resolved_path"
        error "Refusing to delete for safety. Please remove manually if needed."
        return 1
    fi

    echo ""
    read -p "Remove configuration files at $CONFIG_DIR? [y/N] " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        success "Configuration directory removed"
    else
        info "Keeping configuration files"
    fi
}

# Remove icon
remove_icon() {
    local icon_file="$ICON_DIR/claude-ai.png"

    if [[ ! -f "$icon_file" ]]; then
        return
    fi

    echo ""
    read -p "Remove notification icon at $icon_file? [y/N] " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$icon_file"
        success "Icon removed"
    else
        info "Keeping icon file"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Claude Notify uninstalled${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo "Claude Code will no longer send notifications."
    echo ""
    echo "To reinstall, run: ./install.sh"
    echo ""
}

# Main uninstallation
main() {
    echo ""
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}  Claude Notify Uninstaller${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo ""

    read -p "Are you sure you want to uninstall Claude Notify? [y/N] " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Uninstallation cancelled"
        exit 0
    fi

    remove_hooks
    remove_config
    remove_icon
    print_summary
}

main "$@"
