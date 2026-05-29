# secret-gate

**secret-gate** is a secure-session wrapper for secret manager CLIs (Bitwarden, 1Password, HashiCorp Vault, etc.). It lets you authenticate with your master password in a way that never exposes it to terminal scrollback or AI agents, then exports the session credentials into the **current** PowerShell session so you (and any AI assistant attached to it) can use the CLIs immediately.

## The Problem

When you run secret manager CLI commands directly in a terminal that is shared with an AI coding assistant, the assistant can observe:

- Your master password when you type it into a prompt
- Access tokens and session keys when you `export` them
- Long-lived machine-account credentials in command history or scrollback

`secret-gate` solves this by handling authentication securely and keeping the master password out of the terminal output entirely.

## The Solution

`secret-gate` authenticates in the **current** PowerShell session:

1. Checks whether your vault is already unlocked, locked, or unauthenticated
2. If locked, a **GUI password dialog** appears on your desktop — the password is masked and never typed into the terminal
3. Unlocks the password manager and stores the session key
4. Retrieves your machine-account token from the vault
5. Both credentials are now available as environment variables in the current session

AI assistants can then run CLI commands on your behalf without ever having seen your master password or the machine access token in the terminal output.

> **Paranoid mode:** Use `-Isolate` to spawn a fully separate PowerShell window where credentials stay confined. In that mode the AI in the parent terminal will **not** be able to use the CLIs.

## Prerequisites

- [PowerShell 7.2+](https://github.com/PowerShell/PowerShell)
- [Bitwarden CLI (`bw`)](https://bitwarden.com/help/cli/)
- [Bitwarden Secrets Manager CLI (`bws`)](https://bitwarden.com/help/secrets-manager-cli/)
- You must have run `bw login` at least once on the machine so that `bw unlock` works.

## Usage

### Default — Authenticate in current session (AI-friendly)

```powershell
.\secret-gate.ps1
```

A **GUI password dialog** appears on your screen. Type your master password (characters are masked with `*`), click OK, and the session is ready in the current shell. The AI agent can then run:

```powershell
bws secret list
bw get item "My Secret"
```

> **Why a GUI dialog?** `Read-Host` is blocked when PowerShell runs in NonInteractive mode (AI agents, CI runners, scheduled tasks). The GUI dialog works everywhere — interactive terminals, agent shells, and headless automation (via `-PasswordFile`).

### Using `Start-SecretGate.ps1` (convenience wrapper)

```powershell
.\Start-SecretGate.ps1
```

A thin wrapper that dot-sources `secret-gate.ps1`. Identical behavior to running the main script directly.

### Isolated mode (credentials trapped in child window)

```powershell
.\secret-gate.ps1 -Isolate
```

A new PowerShell window opens. Credentials stay in that window only. Use this when you want zero exposure in the parent terminal.

### Command-line Options

| Parameter | Description |
|-----------|-------------|
| `-ServerUrl` | Bitwarden server (default: `https://vault.bitwarden.eu`) |
| `-VaultItemName` | Vault item containing the machine token |
| `-AccessTokenFieldName` | Custom field name that holds the token |
| `-ConfigPath` | Path to a JSON config file with defaults |
| `-PasswordFile` | Read master password from a file (deleted after use) |
| `-Isolate` | Spawn a new isolated window instead of the current session |

## Configuration

Create a JSON config file (e.g., `my-config.json`) to avoid passing parameters every time:

```json
{
  "serverUrl": "https://vault.bitwarden.eu",
  "vaultItemName": "Bitwarden SM - ops-bootstrap Access Token",
  "accessTokenFieldName": "Access Token"
}
```

Then run:

```powershell
.\secret-gate.ps1 -ConfigPath .\my-config.json
```

Precedence: CLI parameters > config file > `config/defaults.json`.

## How It Works

```
Current Terminal (AI agent is here)
  |
  |-- secret-gate.ps1
        |-- Check for cached session        (saved to %LOCALAPPDATA%\secret-gate\)
        |-- If cached & valid → load, skip auth
        |-- If not cached:
        |     |-- GUI password dialog        (masked, not in terminal output)
        |     |-- bw unlock                  (session key in $env:BW_SESSION)
        |     |-- bw list items              (retrieve access token)
        |     |-- $env:BWS_ACCESS_TOKEN      (set in current session)
        |     |-- Cache session to disk
        |-- AI can now run bw/bws            (available in current shell)
```

### Security Properties

- **Master password never echoed**: Either via GUI dialog (masked) or `Read-Host -AsSecureString` (silent mode).
- **No disk persistence**: The session cache at `%LOCALAPPDATA%\secret-gate\session.json` stores only the short-lived session key and the machine access token (which is the same token you already store in your password manager vault).
- **No command-line leakage**: The master password is piped to `bw` via stdin, never appearing in process arguments.
- **Session-scoped**: Environment variables last only until you close the terminal. Delete the cache file to force re-authentication.

## Vault Setup

Before running `secret-gate`, create a Password Manager vault item:

1. Open the Bitwarden web vault.
2. Create a new item named `Bitwarden SM - ops-bootstrap Access Token` (or whatever you configure in `vaultItemName`).
3. Add a **Custom Text Field** named `Access Token` (or your configured `accessTokenFieldName`).
4. Paste your Secrets Manager machine-account access token into that field.
5. Save the item.

## Testing

A mock-based end-to-end test suite is included in `tests/`.

```powershell
& .\tests\Run-E2ETest.ps1
```

This validates the full script flow (status checks, unlock, token retrieval, and environment variable export) without needing real Bitwarden credentials.

## Troubleshooting

### "bw was not found in PATH"

Install the Bitwarden CLI and ensure it is on your system PATH.

### "You are not logged in to Bitwarden on this device"

Run `bw login` in any terminal first. `secret-gate` only performs `bw unlock`; it does not handle the initial device login.

### "Failed to switch Bitwarden server"

If you recently changed servers, run `bw logout` first, then `bw login` with the new server, then re-run `secret-gate`.

### "Vault item not found"

Check that the vault item name exactly matches your config. You can verify with:

```powershell
bw list items --search "ops-bootstrap" | ConvertFrom-Json | Select-Object name
```

### "The window opens and immediately closes" / "PowerShell is in NonInteractive mode"

You are in a non-interactive shell. Run `secret-gate.ps1` directly — it uses a GUI password dialog that works in both interactive and non-interactive shells.

### "Access Token field is empty"

Make sure the custom field is a **Text** field (not Hidden, unless you adjust the script), and that the value is not the placeholder `PASTE_TOKEN_HERE`.

## Contributing

Issues and pull requests are welcome. Please open an issue first for major changes.

## License

[MIT](LICENSE)
