# Claude Notify

Linux desktop notifications for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Get notified when Claude needs your input or finishes a task.

## Features

- **Desktop Notifications** — Native Linux notifications via `notify-send` (libnotify)
- **Contextual content** — Each notification shows the project, git branch, session, and the specific tool call, final message, or error that needs attention
- **Customizable** — Configure icons, urgency, notification content, and context lines
- **Non-intrusive** — Uses Claude Code's built-in hooks system
- **Per-project overrides** — Optional `.claude-notify.json` in a project directory
- **No network access** — Notifications are delivered locally; nothing is sent off your machine

## Requirements

- Linux with a desktop notification daemon (GNOME, KDE, dunst, mako, etc.)
- Bash
- `notify-send` from libnotify
- `jq` (required by the installer and for contextual notification content)
- `git` (optional; adds the current branch to notifications)

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

The installer backs up your existing `~/.claude/settings.json` before adding hooks. It only replaces Claude Notify's own entries and leaves hooks from other tools untouched.

## Configuration

Claude Notify reads its configuration from `~/.config/claude-notify/config.json`.

```json
{
  "icon": "~/.local/share/icons/claude-ai.png",
  "context": {
    "enabled": true,
    "title_prefix": "Claude Code",
    "show_branch": true,
    "show_session": true,
    "show_session_title": true,
    "max_detail_length": 160
  },
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

| Option                       | Type   | Default       | Description                                        |
| ---------------------------- | ------ | ------------- | -------------------------------------------------- |
| `icon`                       | string | `""`          | Path to notification icon (supports `~` expansion) |
| `context.enabled`            | bool   | `true`        | Build title/body from the hook payload and local context |
| `context.title_prefix`       | string | `"Claude Code"` | Prefix for generated titles (`<prefix> · done · 4m12s`) |
| `context.show_branch`        | bool   | `true`        | Include the current git branch                     |
| `context.show_session`       | bool   | `true`        | Include the session short ID                       |
| `context.show_session_title` | bool   | `true`        | Include the session title (or last prompt excerpt) |
| `context.max_detail_length`  | int    | `160`         | Max characters for the event detail line           |
| `notifications.*.enabled`    | bool   | `true`        | Enable/disable a notification type                 |
| `notifications.*.title`      | string | varies        | Notification title (used when `context.enabled` is `false`) |
| `notifications.*.message`    | string | varies        | Notification message (fallback detail line)        |
| `notifications.*.urgency`    | string | varies        | Urgency: `low`, `normal`, `critical`               |
| `notifications.*.icon`       | string | preset        | Optional per-type icon override                    |

### Notification content

With context enabled, notifications are assembled from the hook payload:

```
TITLE │ Claude Code · done · 4m12s
BODY  │
      │ ~/src/my-project · main
      │ Session 9568ef85 — "Fix the login redirect"
      │ Refactored the auth middleware and all tests pass.
```

- **Where** — project path (home shortened to `~`) and git branch.
- **Which session** — first 8 characters of `session_id` plus the session title.
- **What happened** — for approvals, the tool name and command or file (`Approve Bash: git push`); for completion, the first line of Claude's final message; for errors, the API error text.
- **Elapsed time** — when the `UserPromptSubmit` hook recorded the turn start.
- **Background work** — a reminder when the session still has running background tasks.

The session title comes from Claude Code's `session_title` field when present, otherwise from the transcript's generated title, otherwise from the last prompt. The latter two are internal transcript details and may lag or change between Claude Code versions.

Set `context.enabled` to `false` to fall back to the static per-type `title`/`message` values.

### Environment Variables

| Variable             | Description                         |
| -------------------- | ----------------------------------- |
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

| Event               | Trigger                                   | Default Behavior                              |
| ------------------- | ----------------------------------------- | --------------------------------------------- |
| `PermissionRequest` | A tool call needs approval                | Notification with tool and command/file       |
| `Notification`      | Claude is waiting or idle                 | Notification (`permission_prompt` excluded)   |
| `Stop`              | Turn finished                             | Notification with Claude's final message      |
| `StopFailure`       | Turn ended due to an API error            | Notification with the error type              |
| `UserPromptSubmit`  | Prompt submitted                          | Records turn start for the duration line      |

`Notification` is limited to idle and agent/elicitation events because `PermissionRequest` already fires immediately with the exact tool call; wiring both would duplicate every approval alert.

### Manual Testing

```bash
# Preview the three layouts with synthetic data (also sends the notification)
./hooks/notify.sh --type input    --demo --preview
./hooks/notify.sh --type complete --demo --preview
./hooks/notify.sh --type error    --demo --preview

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
--type, -t TYPE      Notification type: input, complete, error, prompt
--title TITLE        Custom notification title
--message, -m MSG    Custom notification message
--urgency, -u LEVEL  Urgency: low, normal, critical
--icon, -i PATH      Path to icon file
--category, -c CAT   Notification category (e.g., im.received)
--action, -a ACTION  Add an action button (format: id=Label)
--wait, -w           Wait for an action response
--test               Send a test notification
--demo               Render using a synthetic hook payload
--preview            Print the rendered title and body
--validate [FILE]    Validate a configuration file and exit
--version, -V        Show version information
--help, -h           Show help
```

## How It Works

Claude Notify integrates with Claude Code's [hooks system](https://docs.anthropic.com/en/docs/claude-code/hooks). The installer merges these hooks into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PermissionRequest": [
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
    "Notification": [
      {
        "matcher": "idle_prompt|agent_needs_input|elicitation_dialog|elicitation_url_dialog|quota_auto_resume_fired|quota_auto_resume_stale|quota_auto_resume_disabled",
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
    ],
    "StopFailure": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/claude-notify/hooks/notify.sh --type error"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/claude-notify/hooks/notify.sh --type prompt"
          }
        ]
      }
    ]
  }
}
```

When an event fires, Claude Code passes a JSON payload on stdin. `notify.sh` reads it, extracts the session ID, project directory, tool call, final message, or error, combines that with the git branch and (optionally) the session title, and sends a local notification with `notify-send`. The `UserPromptSubmit` hook only records a timestamp so `Stop` can report how long the turn took. Nothing is sent over the network.

The installer only replaces Claude Notify's own handlers; hooks owned by other tools are preserved. Re-running the installer updates the existing entries instead of duplicating them.

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
