# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases use
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- Transactional Windows upgrades with staged validation, lock waiting, atomic
  replacement, locking-process diagnostics, and preservation on timeout

## 0.1.0 - 2026-07-11

### Added

- Linux SSH runtime dispatcher with direct fallback for unrelated hosts
- Native Windows client built by the PowerShell installer
- NUL-delimited helper protocol that preserves argument boundaries
- Relay-owned ControlMaster reuse
- VS Code Remote SSH dynamic-forward bridging
- Linux SSHFS wrapper with nonblocking binary stream support
- Linux and Windows installation scripts
- Cross-platform fake-transport tests and GitHub Actions workflow
- Security model, security policy, known limitations, and benchmarks
- Apache License 2.0

### Fixed

- UTF-8 BOM handling for Windows .NET Framework redirected stdin
- Windows persistent-stream buffering and bulk-transfer stalls
- Client-local access to relay-side dynamic forwarding listeners
- SSHFS disconnects caused by nonblocking stdin
