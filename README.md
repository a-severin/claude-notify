# Claude Notify

Linux desktop notifications for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Get notified when Claude needs your input or finishes a task.

## Features

- **Desktop Notifications** — Native Linux notifications via `notify-send` (libnotify)
- **Customizable** — Configure icons, urgency, and notification content
- **Non-intrusive** — Uses Claude Code's built-in hooks system
- **Per-project overrides** — Optional `.claude-notify.json` in a project directory
- **No network access** — Notifications are delivered locally; nothing is sent off your machine

## Requirements

- Linux with a desktop notification daemon (GNOME, KDE, dunst, mako, etc.)
- Bash
- `notify-send` from libnotify
- `jq` (used by the installer to update Claude Code settings)

```bash
# Debian/Ubuntu
sudo apt install jq libnotify-bin

# Fedora
sudo dnf install jq libnotify

# Arch Linux
sudo pacman -S jq libnotify
```

## Quick Start

```bash
git clone <your-repository-url> claude-notify
cd claude-notify

# Preview the installation without making changes
./install.sh --dry-run

# Install
./install.sh
```

That's it — you'll now receive desktop notifications when Claude Code needs input or completes a task.

## Installation

1. **Clone the repository**
   ```bash
   git clone <your-repository-url> claude-notify
   cd claude-notify
   ```

2. **Review the configuration** (optional)
   ```bash
   cp config/config.example.json config/config.json
   # Edit config/config.json to customize
   ```

3. **Run the installer**
   ```bash
   ./install.sh
   ```

4. **Verify**
   ```bash
   ./hooks/notify.sh --test
   ```

The installer backs up your existing `~/.claude/settings.json` before adding hooks, and asks before overwriting existing hooks.

## Configuration

Claude Notify reads its configuration from `~/.config/claude-notify/config.json`.

```json
{
  "icon": "~/.local/share/icons/claude-ai.png",
  "notifications": {
    "input_needed": {
      "enabled": true,
      "title": "Claude Code",
      "message": "Claude needs your input",
      "urgency": "normal"
    },
    "task_complete": {
      "enabled": true,
      "title": "Claude Code",
      "message": "Task completed",
      "urgency": "low"
    },
    "error": {
      "enabled": true,
      "title": "Claude Code",
      "message": "An error occurred",
      "urgency": "critical"
    }
  }
}
```

### Configuration Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `icon` | string | `""` | Path to notification icon (supports `~` expansion) |
| `notifications.*.enabled` | bool | `true` | Enable/disable a notification type |
| `notifications.*.title` | string | varies | Notification title |
| `notifications.*.message` | string | varies | Notification message body |
| `notifications.*.urgency` | string | varies | Urgency: `low`, `normal`, `critical` |
| `notifications.*.icon` | string | preset | Optional per-type icon override |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `CLAUDE_NOTIFY_ICON` | Override the notification icon path |

### Per-project configuration

`notify.sh` also looks for a `.claude-notify.json` file while walking up from the current directory (restricted to your home directory). Values in it are merged over the global config. Only use this in repositories you trust.

Validate a configuration file with:

```bash
./hooks/notify.sh --validate
./hooks/notify.sh --validate /path/to/config.json
```

## Usage

Once installed, Claude Notify runs automatically through Claude Code's hooks. No manual intervention is required.

### Hook Events

| Event | Trigger | Default Behavior |
|-------|---------|------------------|
| `Notification` | Claude needs user input | Desktop notification |
| `Stop` | Task completed | Desktop notification |

### Manual Testing

```bash
# Test input-needed notification
./hooks/notify.sh --type input

# Test task-complete notification
./hooks/notify.sh --type complete

# Test with a custom message
./hooks/notify.sh --title "Test" --message "Hello from Claude Notify"

# Send the built-in test notification
./hooks/notify.sh --test
```

### Command-line Options

```
--type, -t TYPE      Notification type: input, complete, error
--title TITLE        Custom notification title
--message, -m MSG    Custom notification message
--urgency, -u LEVEL  Urgency: low, normal, critical
--icon, -i PATH      Path to icon file
--category, -c CAT   Notification category (e.g., im.received)
--action, -a ACTION  Add an action button (format: id=Label)
--wait, -w           Wait for an action response
--test               Send a test notification
--validate [FILE]    Validate a configuration file and exit
--version, -V        Show version information
--help, -h           Show help
```

## How It Works

Claude Notify integrates with Claude Code's [hooks system](https://docs.anthropic.com/en/docs/claude-code/hooks). The installer adds these hooks to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/claude-notify/hooks/notify.sh --type input"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/claude-notify/hooks/notify.sh --type complete"
          }
        ]
      }
    ]
  }
}
```

When Claude Code fires one of these events, the hook calls `notify.sh`, which sends a local notification with `notify-send`. The script does not read the event payload from stdin and sends no data over the network.

## Uninstallation

```bash
./uninstall.sh
```

This will:

1. Remove Claude Notify hooks from Claude Code settings
2. Remove configuration files (optional, prompted)
3. Remove the installed icon (optional, prompted)

## Troubleshooting

### Notifications not appearing

1. **Check that `notify-send` works:**
   ```bash
   notify-send "Test" "This is a test notification"
   ```

2. **Check the notification daemon:**
   ```bash
   # GNOME
   systemctl --user status org.gnome.Shell

   # Other desktops
   ps aux | grep -i dunst   # dunst
   ps aux | grep -i mako    # mako (Wayland)
   ```

3. **Check the hooks:**
   ```bash
   jq '.hooks' ~/.claude/settings.json
   ```

### Hooks not triggering

1. **Verify your Claude Code version** — hooks require a recent release.
2. **Check `settings.json` syntax:**
   ```bash
   jq . ~/.claude/settings.json
   ```

### Config validation

```bash
./hooks/notify.sh --validate
```

## Security

- **Local only** — notifications are delivered through the local desktop notification daemon. No network requests are made.
- **Path validation** — project config files are only loaded from within the user's home directory.
- **Safe uninstall** — directory deletion is validated against the expected config path before removal.
- **Settings backup** — the installer backs up `~/.claude/settings.json` before modification.

If you discover a security issue, please report it privately rather than opening a public issue.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) by Anthropic
- [libnotify](https://gitlab.gnome.org/GNOME/libnotify) by the GNOME project
