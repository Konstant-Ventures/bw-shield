# Secret Gate - Bitwarden Authentication and Environment Variable Management

**Secret Gate** is a secure session wrapper for secret manager CLIs. It lets you authenticate with your master password without exposing it to terminal output or AI agents, then exports session credentials into the current environment.

## The Problem

When you run secret manager CLI commands in a terminal shared with an AI coding assistant, the assistant can observe:

- Your master password when you type it
- Access tokens and session keys when you export them
- Long-lived machine-account credentials in command history

`secret-gate` solves this by handling authentication securely and keeping the master password out of terminal output entirely.

## The Solution

`secret-gate` authenticates securely and sets environment variables in the current session:

1. Checks for cached session (skip auth if valid)
2. If needed, GUI password dialog appears (masked, never in terminal output)
3. Unlocks Bitwarden → sets `BW_SESSION`
4. Retrieves machine-account token → sets `BWS_ACCESS_TOKEN`
5. Caches session for reuse

## Quick Start

```bash
# Authenticate (first time)
secret-gate auth

# Refresh all BWS secrets as environment variables
eval $(secret-gate refresh)

# Or just specific sets
secret-gate refresh --set ci
secret-gate refresh --keys CONDUCTOR_MCP_AUTH_TOKEN,ANOTHER_KEY

# Check status
secret-gate status
```

Once authenticated:

```bash
eval $(secret-gate refresh)
opencode  # {env:CONDUCTOR_MCP_AUTH_TOKEN} is available
```

## Commands

| Command | Description |
|---------|-------------|
| `secret-gate auth` | Authenticate to Bitwarden (set BW_SESSION + BWS_ACCESS_TOKEN) |
| `secret-gate refresh` | Pull all secrets from BWS → export as env vars |
| `secret-gate refresh --set ci` | Only export secrets in the 'ci' set |
| `secret-gate refresh --print-env` | Output `export KEY=value` for shell sourcing |
| `secret-gate status` | Check if cached session is valid |

## Installation

```bash
pip install secret-gate
```

Or from the local repo:

```bash
cd /path/to/secret-gate
pip install -e .
```

## Usage

### Basic Auth

```bash
secret-gate auth
```

Enters interactive auth mode (GUI prompt on Windows, password input on other OSes). First time creates a session cache, subsequent runs reuse until cache expires.

### Authentication Options

```bash
# GUI password prompt (works everywhere)
secret-gate auth

# Direct password for testing (not recommended, but available)
secret-gate auth --password "your-password"

# Read password from file (CI/headless)
secret-gate auth --password-file /path/to/password.txt
```

### Environment Variable Refresh

```bash
# All secrets → set all as env vars (overwrites existing)
eval $(secret-gate refresh)

# Only named sets (pre-configured groups)
secret-gate refresh --set ci
eval $(secret-gate refresh --set inbox-agent --print-env)

# Or just specific keys
secret-gate refresh --keys CONDUCTOR_MCP_AUTH_TOKEN,GOOGLE_CLIENT_ID,GOOGLE_CLIENT_SECRET
```

### Print Environment Variables for Sourcing

```bash
# Useful for multi-line commands or launchers
eval $(secret-gate refresh --print-env)
```

Or save to a file and source it:

```bash
secret-gate refresh --print-env > .env
eval "$(cat .env)"
```

## Configuration

### Defaults (in `config/defaults.json`)

```json
{
  "serverUrl": "https://vault.bitwarden.eu",
  "vaultItemName": "Bitwarden SM - ops-bootstrap Access Token",
  "accessTokenFieldName": "Access Token",
  "sets": {
    "default": "*",
    "ci": "CONDUCTOR_MCP_AUTH_TOKEN;ANOTHER_CI_SECRET",
    "inbox-agent": "INBOX_TELEGRAM_BOT_TOKEN;INBOX_GOOGLE_CLIENT_ID;INBOX_GOOGLE_CLIENT_SECRET;INBOX_OWNER_USER_ID;INBOX_TELEGRAM_GROUP_CHAT_ID;AI_WRITING_COPILOT_OPENCODE_API_KEY"
  }
}
```

**Sets** define named groups of secrets for quick access. Use `"*"` to export all secrets.

### CLI Overrides

```bash
secret-gate refresh --set ci
secret-gate refresh --keys KEY1,KEY2,KEY3
```

### Config File

Create `my-config.json` to avoid repeating parameters:

```json
{
  "serverUrl": "https://vault.bitwarden.eu",
  "vaultItemName": "Bitwarden SM - ops-bootstrap Access Token",
  "accessTokenFieldName": "Access Token"
}
```

Then:

```bash
secret-gate auth --config-path ./my-config.json
secret-gate refresh --config-path ./my-config.json
```

## Authentication Flow

```
Current Terminal
   |
   |-- secret-gate.auth()
         |-- Check cache session (session.json)
         |-- If cached & valid → load, exit
         |-- If locked → prompt password (GUI on Windows, stdin elsewhere)
         |-- Run: bw unlock --password "***" --raw
         |-- BWS setup: bws config server-base <serverUrl>
         |-- Retrieve token from vault item
         |-- Cache session.json
         |-- Set BW_SESSION, BWS_ACCESS_TOKEN
         |     |
         |     |-- Available to current shell
         |     `  --> AI can use bw/bws commands
```

## Platform-Specific Behavior

### Windows

- GUI password dialog using tkinter (appears on desktop)
- Works in both interactive and non-interactive shells
- Session cache at `%LOCALAPPDATA%\secret-gate\session.json`

### macOS/Linux

- Password input via stdin (or readline mode where available)
- Uses XDG home: `~/.local/state/secret-gate/session.json`

### Environment Variables Exported

- `BW_SESSION`: Bitwarden Password Manager session key
- `BWS_ACCESS_TOKEN`: Secrets Manager machine-account token

These secret keys can be accessed by subsequent commands in the same session. They persist only while the shell is active.

## Security Properties

- **Master password never echoed**: GUI dialog (masked) or secure read (stdin)
- **No disk persistence**: Session cache stores short-lived tokens only
- **No command-line leakage**: Password passed via stdin to `bw unlock`
- **Session-scoped**: Exported variables last only while shell is active
- **Zero knowledge of credentials**: AI assistants cannot see password

## Vault Setup

Before running `secret-gate`:

1. Open Bitwarden web vault (`https://vault.bitwarden.eu`)
2. Create an item with the configured `vaultItemName` (default: `Bitwarden SM - ops-bootstrap Access Token`)
3. Add a Custom Text field with `accessTokenFieldName` (default: `Access Token`)
4. Paste your Secrets Manager machine-account access token

## Secret Sets (Reusable Groups)

The `sets` configuration lets you group secrets for common use cases:

### Pre-defined Sets

| Set Name | Purpose | Example Secrets |
|----------|---------|----------------|
| `default` | Full access | All secrets from BWS |
| `ci` | CI/CD pipelines | `CONDUCTOR_MCP_AUTH_TOKEN` |
| `inbox-agent` | Email daemon | Telegram + Google + OpenCode keys |

### Creating New Sets

Add to `config/defaults.json` or pass via `--set` to create on-the-fly sets:

```bash
# One-time set
secret-gate refresh --set custom-set --keys SECRET1,SECRET2

# Later use
eval $(secret-gate refresh --set custom-set --print-env)
```

## Testing

Mock-based end-to-end tests validate the full flow without real credentials:

```bash
pytest secret_gate/tests/
```

Or use the test runner:

```bash
python -m secret_gate.tests.run_e2e
```

## Integrations

### OpenCode / opencode Integration

With `CONDUCTOR_MCP_AUTH_TOKEN` exported:

```bash
eval $(secret-gate refresh --set ci)
opencode
```

OpenCode will detect the environment variable and use it for Conductor MCP authentication.

### CI/CD Pipelines

```bash
# Export CI secrets for deployment
eval $(secret-gate refresh --set ci --print-env)
# Or use in Docker entrypoint
COPY secrets.sh /entrypoint/secrets.sh
ENTRYPOINT ["/entrypoint/secrets.sh"]
```

### Local Development

```bash
# In container or local environment
eval "$(secret-gate refresh --set ci --print-env)"
# Run your app
my-app --config config.json
```

## Development

### Install dev dependencies

```bash
pip install -e .[dev]
```

### Run tests

```bash
pytest
```

### Code quality

```bash
black secret_gate/
ruff secret_gate/
mypy secret_gate/
```

## Migration from PowerShell Version

If you're coming from the `.ps1` version:

**Old way:**

```powershell
.\secret-gate.ps1
bws secret list
```

**New way:**

```bash
secret-gate auth
eval $(secret-gate refresh)
bws secret list
```

The Python version offers:

- Same authentication security
- Better cross-platform support
- CLI-first philosophy
- Installable via pip
- Type hints and modern Python idioms

## Common Tasks

### Add a new secret to the workspace

```bash
# One-time: add secret to BWS (placeholder)
secret-gate auth
eval $(secret-gate refresh --set default)
bws secret create \
  MY_NEW_SECRET \
  "REPLACE_IN_WEB_VAULT" \
  PROJECT_ID \
  --note "Add your actual value here"
```

### Daily workflow: set up environment

```bash
#!/usr/bin/env bash

# Export CI secrets
eval "$(secret-gate refresh --set ci --print-env)"

# Run your application
exec "$@"
```

### Docker entrypoint

```dockerfile
FROM python:3-slim
WORKDIR /app
COPY entrypoint.sh .
COPY pyproject.toml .
RUN pip install -e .
COPY . .
ENTRYPOINT ["./entrypoint.sh"]
```

```bash
# entrypoint.sh
#!/bin/bash
readonly set -e

eval "$(secret-gate refresh --set ci --print-env)"
exec "$@"
```

## Troubleshooting

### "Command not found: secret-gate"

```bash
pip install secret-gate
# or
cd /path/to/secret-gate
pip install -e .
```

### "not logged in to Bitwarden"

```bash
# Run bw login first in any terminal
bw login
# Then re-run secret-gate
secret-gate auth
```

### "Access Token field is empty"

Check that the vault item has a non-empty custom field. The placeholder `PASTE_TOKEN_HERE` is replaced during setup.

### "Failed to switch Bitwarden server"

If you changed servers, run `bw logout` first, then `bw login`, then re-run `secret-gate`.

### AI Interaction

- Never paste master passwords into chat
- Never share `BW_SESSION` or `BWS_ACCESS_TOKEN` values
- Use `--output none` when running `bws secret create` in AI workflows
- If a secret placeholder is created, tell the user to replace it in the web UI

## License

MIT. See LICENSE file.

## References

- Bitwarden CLI: https://bitwarden.com/help/cli/
- Bitwarden SM CLI: https://bitwarden.com/help/secrets-manager-cli/
- PowerShell 7+: https://github.com/PowerShell/PowerShell
