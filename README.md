# secret-gate

Secure Bitwarden authentication and environment variable management.
Cross-platform. Zero dependencies. Python 3.9+.

## How it works

**The agent runs `secret-gate auth`.** A GUI password dialog appears on your
desktop (Windows) or a secure prompt in your terminal (macOS/Linux). You type
your Bitwarden master password — it is **never** echoed to the terminal,
scrollback, or agent logs. The session is cached so subsequent runs skip the
password prompt.

**The agent runs `secret-gate refresh`** to pull secrets from Bitwarden
Secrets Manager and export them as environment variables. Secrets are filtered
by pre-configured **sets** (named groups like `ci`, `inbox-agent`) or
explicit key lists.

## Quick Start

```bash
pip install -e .

# One-time: authenticate (GUI dialog pops up)
secret-gate auth

# Pull secrets and export as environment variables
eval $(secret-gate refresh --print-env)

# Or export only CI secrets (e.g., CONDUCTOR_MCP_AUTH_TOKEN)
eval $(secret-gate refresh --set ci --print-env)
```

## OpenCode / MCP Integration

```bash
# In your terminal, before launching opencode:
eval $(secret-gate refresh --set ci --print-env)

# Now start opencode — {env:CONDUCTOR_MCP_AUTH_TOKEN} is available
opencode
```

The opencode config (`opencode.json`) references it as:

```json
{
  "mcp": {
    "conductor": {
      "type": "remote",
      "url": "https://conductor-konstant.hectorsanchez.eu/mcp",
      "headers": { "Authorization": "Bearer {env:CONDUCTOR_MCP_AUTH_TOKEN}" }
    }
  }
}
```

## Commands

| Command | Description |
|---------|-------------|
| `secret-gate auth` | Open a GUI dialog to authenticate to Bitwarden |
| `secret-gate auth -p PASS` | Direct password (testing only) |
| `secret-gate auth --password-file PATH` | Read password from file (CI/headless) |
| `secret-gate refresh` | Export ALL BWS secrets as env vars |
| `secret-gate refresh -s ci` | Export only the "ci" set |
| `secret-gate refresh -k KEY1,KEY2` | Export only specific keys |
| `secret-gate refresh --print-env` | Output `export KEY=value` for shell sourcing |
| `secret-gate status` | Check if authenticated |

## Expected behavior

- **`secret-gate auth`** is run by the AI agent. It triggers a GUI password
  dialog. The user enters their master password. No password is typed into
  the terminal. After auth, the session is cached to disk so subsequent
  commands don't need the password again.
- **`secret-gate refresh`** reads the cached session and pulls the latest
  secrets from Bitwarden Secrets Manager. Each secret key becomes an
  environment variable.
- **`eval $(secret-gate refresh --print-env)`** is how you source the
  environment variables into your parent shell.

## Configuration

### Secret sets (`config/defaults.json`)

```json
{
  "serverUrl": "https://vault.bitwarden.eu",
  "vaultItemName": "Bitwarden SM - ops-bootstrap Access Token",
  "accessTokenFieldName": "Access Token",
  "sets": {
    "all": "*",
    "ci": ["CONDUCTOR_MCP_AUTH_TOKEN"],
    "inbox-agent": ["INBOX_TELEGRAM_BOT_TOKEN", "INBOX_GOOGLE_CLIENT_ID", "..."]
  }
}
```

Sets are pre-defined groups of secrets. The `"*"` wildcard exports everything.
Use `-s` / `--set` to select a set, or `-k` / `--keys` for ad-hoc filtering.
When both are given, the result is the intersection.

### Built-in defaults

All configuration has sensible built-in defaults. An external config file is
optional — the package works after `pip install` with no additional setup.

## Security

- **Master password**: sent to `bw unlock` via stdin, never in process args
- **GUI dialog** (Windows): password input is masked, works in NonInteractive shells
- **Secure prompt** (macOS/Linux): uses `getpass`, no echo
- **Session cache**: stored at platform-appropriate path (`%LOCALAPPDATA%` / `~/.local/state`)
- **No secrets in chat**: the agent sees only key names and value lengths

## Platform Support

| Platform | Password Input | Session Cache |
|----------|---------------|---------------|
| Windows | tkinter GUI dialog | `%LOCALAPPDATA%\secret-gate\session.json` |
| macOS | getpass (terminal) | `~/.local/state/secret-gate/session.json` |
| Linux | getpass (terminal) | `~/.local/state/secret-gate/session.json` |

## Development

```bash
pip install -e ".[dev]"
pytest -v
ruff check secret_gate/
```

## License

MIT
