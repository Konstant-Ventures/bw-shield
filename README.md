# bw-shield

**bw-shield** is a secure-session wrapper for the Bitwarden CLI (`bw`) and Bitwarden Secrets Manager CLI (`bws`). It ensures that your master password, session key, and machine-account access token are never exposed to the parent terminal, shell history, or any AI coding assistants running in the parent session.

## The Problem

When you run Bitwarden CLI commands directly in your terminal (or in a terminal shared with an AI agent), the agent can observe:

- Your master password when you type it
- The `BW_SESSION` token after unlock
- The `BWS_ACCESS_TOKEN` after retrieval

These secrets may end up in shell history, environment dumps, or AI agent logs.

## The Solution

`bw-shield` spawns a **fully isolated child PowerShell process**. Inside that process:

1. You type your master password interactively (secure input, hidden from parent)
2. `bw-shield` authenticates to Bitwarden Password Manager
3. It retrieves your Secrets Manager machine-account token from the vault
4. Both `BW_SESSION` and `BWS_ACCESS_TOKEN` are set **only** in the child process memory

The parent process (and any AI agent attached to it) never sees these values.

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

# Run directly
.\bw-shield\bw-shield.ps1
```

### Optional: Add to PATH

Add the repository folder to your `PATH` so you can run `bw-shield` from anywhere:

```powershell
# Windows (User PATH)
$target = "D:\01 - Workspace\01 - Infrastructure\secrets\bw-shield"
[Environment]::SetEnvironmentVariable("Path", "$target;$env:Path", "User")
```

Then restart your terminal and run:

```powershell
bw-shield.ps1
```

## Usage

```powershell
.\bw-shield.ps1
```

A new PowerShell window opens. Enter your Bitwarden master password. The session is ready when you see the **Session ready** banner.

### Command-line Options

| Parameter | Description |
|-----------|-------------|
| `-ServerUrl` | Bitwarden server (default: `https://vault.bitwarden.eu`) |
| `-VaultItemName` | Vault item containing the machine token |
| `-AccessTokenFieldName` | Custom field name that holds the token |
| `-ConfigPath` | Path to a JSON config file with defaults |
| `-NoProfile` | Skip loading your PowerShell profile in the child session |

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

```
Parent Terminal (AI agent can see here)
  |
  |-- starts --> Child PowerShell Process (isolated window)
                      |
                      |-- Read-Host master password (secure, hidden)
                      |-- bw unlock (session key stays in child env)
                      |-- bw list items (retrieve access token)
                      |-- Set env vars in child ONLY
                      |-- Interactive shell ready
```

### Security Properties

- **No disk persistence**: Secrets are never written to files.
- **No parent exposure**: Environment variables exist only in the child process.
- **No command-line leakage**: The master password is read via secure prompt and piped to `bw` via stdin, never appearing in process arguments.
- **Clean teardown**: When you close the child window, all secrets are gone from memory (process termination).

## Vault Setup

Before running `bw-shield`, create a Password Manager vault item:

1. Open the Bitwarden web vault.
2. Create a new item named `Bitwarden SM - ops-bootstrap Access Token` (or whatever you configure in `vaultItemName`).
3. Add a **Custom Text Field** named `Access Token` (or your configured `accessTokenFieldName`).
4. Paste your Secrets Manager machine-account access token into that field.
5. Save the item.

## Troubleshooting

### "bw was not found in PATH"

Install the Bitwarden CLI and ensure it is on your system PATH.

### "You are not logged in to Bitwarden on this device"

Run `bw login` in any terminal first. `bw-shield` only performs `bw unlock`; it does not handle the initial device login.

### "Vault item not found"

Check that the vault item name exactly matches your config. You can verify with:

```powershell
bw list items --search "ops-bootstrap" | ConvertFrom-Json | Select-Object name
```

### "Access Token field is empty"

Make sure the custom field is a **Text** field (not Hidden, unless you adjust the script), and that the value is not the placeholder `PASTE_TOKEN_HERE`.

## Contributing

Issues and pull requests are welcome. Please open an issue first for major changes.

## License

[MIT](LICENSE)
