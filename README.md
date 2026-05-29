# bw-shield

**bw-shield** is a secure-session wrapper for the Bitwarden CLI (`bw`) and Bitwarden Secrets Manager CLI (`bws`). It lets you authenticate with your master password in a way that never exposes it to terminal scrollback or AI agents, then exports the session credentials into the **current** PowerShell session so you (and any AI assistant attached to it) can use both CLIs immediately.

## The Problem

When you run Bitwarden CLI commands directly in a terminal that is shared with an AI coding assistant, the assistant can observe:

- Your master password when you type it into a prompt
- Access tokens and session keys when you `export` them
- Long-lived machine-account credentials in command history or scrollback

`bw-shield` solves this by handling authentication securely and keeping the master password out of the terminal output entirely.

## The Solution

`bw-shield` authenticates in the **current** PowerShell session:

1. Checks whether your vault is already unlocked, locked, or unauthenticated
2. If locked, prompts for your master password with `Read-Host -AsSecureString` — the password is **never echoed** to the terminal
3. Unlocks Bitwarden Password Manager and stores `BW_SESSION`
4. Retrieves your Secrets Manager machine-account token from the vault and stores `BWS_ACCESS_TOKEN`
5. Both environment variables are now available in the current session

AI assistants can then run `bw` and `bws` commands on your behalf without ever having seen your master password or the machine access token in the terminal output.

> **Paranoid mode:** Use `-Isolate` to spawn a fully separate PowerShell window where credentials stay confined. In that mode the AI in the parent terminal will **not** be able to use `bw`/`bws`.

## Installation

### Prerequisites

- [PowerShell 7.2+](https://github.com/PowerShell/PowerShell)
- [Bitwarden CLI (`bw`)](https://bitwarden.com/help/cli/)
- [Bitwarden Secrets Manager CLI (`bws`)](https://bitwarden.com/help/secrets-manager-cli/)
- You must have run `bw login` at least once on the machine so that `bw unlock` works.

### Quick Install

```powershell
# Clone the repository
git clone https://github.com/konstant-ventures/bw-shield.git

# Run directly (authenticates in the current session)
.\bw-shield\bw-shield.ps1
```

### Optional: Add to PATH

```powershell
$target = "D:\01 - Workspace\01 - Infrastructure\secrets\bw-shield"
[Environment]::SetEnvironmentVariable("Path", "$target;$env:Path", "User")
```

Then restart your terminal and run:

```powershell
bw-shield.ps1
```

## Usage

### Default — Authenticate in current session (AI-friendly)

```powershell
.\bw-shield.ps1
```

Enter your master password when prompted. The session key and access token are exported to the current shell. You can immediately run:

```powershell
bws secret list
bw get item "My Secret"
```

### For AI agents — launch an interactive window for the user

When PowerShell is running in **NonInteractive** mode (common for AI agents and automation), `Read-Host` is blocked. The helper script opens a truly interactive window so the user can type their password safely:

```powershell
.\Start-BwShield.ps1
```

This is the exact same as running:

```batch
cmd /c start "" pwsh -Interactive -NoProfile -NoExit -File ".\bw-shield.ps1"
```

> **Why this works:** `cmd /c start` creates a brand-new interactive console that does **not** inherit the parent shell's `NonInteractive` flag. `Start-Process pwsh` inherits it, which is why it crashes.

### For AI agents — direct authentication (no window needed)

If you want the AI to authenticate **directly in the current session** so it can use `bw`/`bws` immediately, create a one-time password file and run:

```powershell
# The user puts their master password in this file
$env:TEMP\bw-pass.txt

.\bw-shield.ps1 -PasswordFile "$env:TEMP\bw-pass.txt"
```

The script will:
1. Read the password from the file
2. Unlock Bitwarden and export `BW_SESSION`
3. Retrieve the machine token and export `BWS_ACCESS_TOKEN`
4. **Immediately delete the password file**
5. The AI can now run `bw` and `bws` commands in the same session.

### Isolated mode (credentials trapped in child window)

```powershell
.\bw-shield.ps1 -Isolate
```

A new PowerShell window opens. Credentials stay in that window only. Use this when you want zero exposure in the parent terminal.

### Command-line Options

| Parameter | Description |
|-----------|-------------|
| `-ServerUrl` | Bitwarden server (default: `https://vault.bitwarden.eu`) |
| `-VaultItemName` | Vault item containing the machine token |
| `-AccessTokenFieldName` | Custom field name that holds the token |
| `-ConfigPath` | Path to a JSON config file with defaults |
| `-Isolate` | Spawn a new isolated window instead of the current session |

### Example with Overrides

```powershell
.\bw-shield.ps1 -ServerUrl "https://vault.bitwarden.com" -VaultItemName "My SM Token"
```

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
.\bw-shield.ps1 -ConfigPath .\my-config.json
```

Precedence: CLI parameters > config file > `config/defaults.json`.

## How It Works

### Default (Current Session) Mode

```
Current Terminal (AI agent is here)
  |
  |-- bw-shield.ps1
        |-- bw status               (check lock state)
        |-- Read-Host -AsSecureString  (master password hidden)
        |-- bw unlock --raw          (session key in $env:BW_SESSION)
        |-- bw list items            (retrieve access token)
        |-- $env:BWS_ACCESS_TOKEN    (set in current session)
        |-- AI can now run bw/bws    (available in current shell)
```

### Security Properties

- **Master password never echoed**: `Read-Host -AsSecureString` suppresses all characters from terminal output and scrollback.
- **No disk persistence**: Secrets are never written to files.
- **No command-line leakage**: The master password is piped to `bw` via stdin, never appearing in process arguments.
- **Session-scoped only**: Environment variables last only until you close the terminal.

## Vault Setup

Before running `bw-shield`, create a Password Manager vault item:

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

Run `bw login` in any terminal first. `bw-shield` only performs `bw unlock`; it does not handle the initial device login.

### "Failed to switch Bitwarden server"

If you recently changed servers, run `bw logout` first, then `bw login` with the new server, then re-run `bw-shield`.

### "Vault item not found"

Check that the vault item name exactly matches your config. You can verify with:

```powershell
bw list items --search "ops-bootstrap" | ConvertFrom-Json | Select-Object name
```

### "The window opens and immediately closes"

You are launching from a non-interactive shell. `Start-Process pwsh` inherits the `NonInteractive` flag and blocks `Read-Host`. Use the helper script instead:

```powershell
.\Start-BwShield.ps1
```

Or the raw command:

```batch
cmd /c start "" pwsh -Interactive -NoProfile -NoExit -File ".\bw-shield.ps1"
```

### "PowerShell is in NonInteractive mode. Read and Prompt functionality is not available."

Same issue as above — the parent shell is non-interactive. Use `Start-BwShield.ps1`.

### "The argument 'D:\01' is not recognized as the name of a script file"

Path contains spaces and the launcher is not quoting it properly. Use `Start-BwShield.ps1` which handles quoting correctly.

### "Access Token field is empty"

Make sure the custom field is a **Text** field (not Hidden, unless you adjust the script), and that the value is not the placeholder `PASTE_TOKEN_HERE`.

## Contributing

Issues and pull requests are welcome. Please open an issue first for major changes.

## License

[MIT](LICENSE)
