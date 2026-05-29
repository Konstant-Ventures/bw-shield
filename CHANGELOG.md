# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-05-29

### Added
- Initial release of `bw-shield`.
- Secure authentication in the current PowerShell session via `Read-Host -AsSecureString`.
- Optional `-Isolate` switch to spawn a fully isolated child window for maximum paranoia.
- Configuration file support (`config/defaults.json`).
- CLI parameter overrides for server URL, vault item name, and access-token field name.
- Cross-platform PowerShell 7.2+ support.
- `$LASTEXITCODE` validation for all `bw` and `bws` commands.
- Proper detection of `bw` and `bws` prerequisites.
- `bw status` check before unlock to provide clear error messages.
- Conditional `bw config server` to avoid forced logout when already on the correct server.
- Mock-based end-to-end test suite in `tests/`.

### Added
- `Start-BwShield.ps1` helper script for AI agents and non-interactive shells.
  Wraps the proven `cmd /c start` launcher so you do not have to remember
  the full command.
- Direct authentication support for AI agents via `-PasswordFile` on
  `bw-shield.ps1`.

### Fixed
- Corrected the recommended launcher for non-interactive shells.
  `Start-Process pwsh` and `launch-interactive.cmd` inherit the `NonInteractive`
  flag and cause `Read-Host` to fail. The reliable method is:
  `cmd /c start "" pwsh -Interactive -NoProfile -NoExit -File ".\bw-shield.ps1"`.
