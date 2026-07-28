# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-05-29

### Added
- Initial release of `secret-gate`.
- Secure authentication via GUI password dialog (works in interactive and non-interactive shells).
- Session persistence to disk (`%LOCALAPPDATA%\secret-gate\session.json`) — re-authenticate once, reuse across AI agent calls.
- Optional `-Isolate` switch for maximum paranoia (credentials stay in a child window).
- Configuration file support (`config/defaults.json`).
- CLI parameter overrides for server URL, vault item name, and access-token field name.
- Cross-platform PowerShell 7.2+ support.
- `$LASTEXITCODE` validation for all `bw` and `bws` commands.
- Proper detection of `bw` and `bws` prerequisites.
- `bw status` check before unlock to provide clear error messages.
- Conditional `bw config server` to avoid forced logout when already on the correct server.
- `-PasswordFile` parameter for headless CI/automation.
- `Start-SecretGate.ps1` convenience wrapper.
- Mock-based end-to-end test suite in `tests/`.

### Fixed
- `Clear-Host` crash in terminals without a console handle.
- `bw config server` now skips when already on the correct server (avoids forced logout).
- Non-interactive shell launcher: `cmd /c start "" pwsh` instead of `Start-Process pwsh`.
- Session persistence across separate shell invocations (the fundamental AI agent requirement).
