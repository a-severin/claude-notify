# Contributing to Claude Notify

Thank you for your interest in contributing to Claude Notify! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)
- [Reporting Bugs](#reporting-bugs)
- [Suggesting Features](#suggesting-features)

## Getting Started

1. Fork the repository
2. Clone your fork locally:
   ```bash
   git clone <your-fork-url> claude-notify
   cd claude-notify
   ```
3. Create a branch for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## How to Contribute

We welcome several types of contributions:

- **Bug fixes** — Fix issues reported in the issue tracker
- **New features** — Improve notifications or add functionality
- **Documentation** — Improve or add documentation
- **Tests** — Add or improve test coverage

### Before You Start

1. Check the issue tracker for existing issues or feature requests
2. For major changes, open an issue first to discuss your proposed changes
3. Check [TODO.md](TODO.md) for planned work and its status

## Development Setup

### Prerequisites

- Git
- Bash
- `notify-send` (libnotify)
- `jq`

```bash
# Debian/Ubuntu
sudo apt install libnotify-bin jq

# Fedora
sudo dnf install libnotify jq

# Arch Linux
sudo pacman -S libnotify jq
```

### Setup

```bash
# Clone and enter the repository
git clone <your-fork-url> claude-notify
cd claude-notify

# Test the notification script directly
./hooks/notify.sh --test
```

## Coding Standards

### Shell Scripts (Bash)

- Use `#!/usr/bin/env bash` shebang
- Follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- Use `shellcheck` to lint your scripts:
  ```bash
  shellcheck hooks/notify.sh install.sh uninstall.sh
  ```
- Quote all variables: `"${variable}"` not `$variable`
- Use `[[ ]]` for conditionals instead of `[ ]`
- Add comments for non-obvious logic

### JSON Configuration

- Use 2-space indentation
- Validate JSON before committing:
  ```bash
  jq . config/config.example.json
  ```

## Commit Messages

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### Examples

```
feat(notify): support per-type icons

fix(linux): handle missing notify-send gracefully

docs(readme): clarify configuration options
```

## Pull Request Process

1. **Update documentation** — If your changes affect user-facing behavior, update the README and any relevant documentation.

2. **Test your changes:**
   ```bash
   # Test notification
   ./hooks/notify.sh --test

   # Test installation (use --dry-run first)
   ./install.sh --dry-run
   ```

3. **Create the pull request:**
   - Use a clear, descriptive title
   - Reference any related issues (e.g., "Fixes #123")
   - Describe what changes you made and why
   - Include screenshots for visible changes

4. **Address review feedback** — Be responsive to review comments and make requested changes.

### PR Checklist

- [ ] Code follows project coding standards
- [ ] Self-reviewed the code changes
- [ ] Added/updated documentation as needed
- [ ] Added/updated tests as needed
- [ ] Commits follow conventional commit format

## Reporting Bugs

When reporting bugs, please include:

1. **Environment information:**
   - Linux distribution and version
   - Desktop environment / notification daemon
   - Shell version (`bash --version`)
   - Claude Code version
   - Claude Notify version (`cat VERSION`)

2. **Steps to reproduce:**
   - Exact commands you ran
   - Expected behavior
   - Actual behavior

3. **Relevant logs/output:**
   - Error messages
   - Debug output if available

### Bug Report Template

```markdown
## Environment
- OS: [e.g., Fedora 41]
- Desktop/daemon: [e.g., GNOME, dunst]
- Shell: [e.g., bash 5.2.0]
- Claude Code: [version]
- Claude Notify: [version from VERSION file]

## Description
[Clear description of the bug]

## Steps to Reproduce
1. [First step]
2. [Second step]
3. [...]

## Expected Behavior
[What you expected to happen]

## Actual Behavior
[What actually happened]

## Additional Context
[Any other relevant information, logs, screenshots]
```

## Suggesting Features

We welcome feature suggestions! When suggesting a feature:

1. **Check existing issues** — Your idea may already be proposed or in development
2. **Check TODO.md** — The feature might already be planned
3. **Open an issue** with:
   - Clear description of the feature
   - Use case / motivation
   - Proposed implementation (if you have ideas)
   - Any alternatives you've considered

### Feature Request Template

```markdown
## Feature Description
[Clear description of the proposed feature]

## Motivation
[Why is this feature needed? What problem does it solve?]

## Proposed Implementation
[If you have ideas on how to implement this]

## Alternatives Considered
[Any alternative approaches you've thought about]

## Additional Context
[Any other relevant information]
```

## Questions?

If you have questions about contributing, feel free to open an issue with the "question" label.

Thank you for contributing to Claude Notify!
