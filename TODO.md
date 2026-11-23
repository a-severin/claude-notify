# Claude Notify - Development Roadmap

This document tracks the development progress of Claude Notify, a Linux desktop notification tool for Claude Code.

## Project Status: Alpha

---

## Phase 1: Core Infrastructure

### 1.1 Project Setup
- [x] Initialize git repository
- [x] Add Apache 2.0 license
- [x] Create directory structure
- [x] Write README.md documentation
- [x] Create TODO.md roadmap

### 1.2 Linux Desktop Notifications (notify-send)
- [x] Create notification hook script
- [x] Support custom icons
- [x] Support notification urgency levels
- [x] Add notification categories/hints
- [x] Support notification actions (buttons)

### 1.3 Configuration System
- [x] Create JSON configuration schema
- [x] Support environment variable overrides
- [x] Create example configuration file
- [x] Add configuration validation
- [x] Support per-project configuration overrides

### 1.4 Installation System
- [x] Create install.sh for Linux
- [x] Create uninstall.sh
- [x] Auto-detect existing Claude Code installation
- [x] Backup existing hooks before modification
- [x] Add --dry-run option to installer
- [x] Add version detection and upgrade path

---

## Phase 2: Testing & Quality

- [ ] Add shell tests for configuration parsing
- [ ] Add integration tests for notify-send backend
- [ ] Add CI/CD pipeline (GitHub Actions)
- [ ] Run shellcheck in CI

## Phase 3: Developer Experience

- [x] Create comprehensive README
- [x] Document configuration options
- [x] Create contribution guidelines (CONTRIBUTING.md)
- [ ] Add a changelog

## Phase 4: Distribution

- [ ] Create AUR package (Arch Linux)
- [ ] Create .deb package (Debian/Ubuntu)
- [ ] Create .rpm package (Fedora/RHEL)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache 2.0 - See [LICENSE](LICENSE) for details.
