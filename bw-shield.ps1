#requires -Version 7.2

<#
.SYNOPSIS
    Authenticates to Bitwarden and makes the session available to the current shell.

.DESCRIPTION
    bw-shield authenticates to Bitwarden Password Manager and retrieves the
    Secrets Manager machine-account token, then exports both credentials as
    environment variables in the current session.

    The master password is collected with Read-Host -AsSecureString so it never
    appears in terminal output or scrollback.

    By default everything runs in the current PowerShell session so AI agents
    and automation can use 'bw' and 'bws' immediately after authentication.

    Use -Isolate to spawn a separate window where credentials stay confined to
    that child process (AI agents in the parent will not be able to use the CLIs).

    IMPORTANT: If you are running this from a non-interactive shell (e.g. an AI
    agent), Read-Host will be blocked. Use launch-interactive.cmd instead.

.PARAMETER ServerUrl
    Bitwarden server URL. Defaults to https://vault.bitwarden.eu.

.PARAMETER VaultItemName
    Password Manager vault item that stores the machine account token.

.PARAMETER AccessTokenFieldName
    Custom field name inside the vault item that holds the access token.

.PARAMETER ConfigPath
    Path to a JSON configuration file.

.PARAMETER Isolate
    Spawn a new isolated PowerShell window. The session key and access token will
    NOT be available in the current session.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ServerUrl,

    [Parameter()]
    [string]$VaultItemName,

    [Parameter()]
    [string]$AccessTokenFieldName,

    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [switch]$Isolate,

    [Parameter()]
    [string]$PasswordFile
)

$ErrorActionPreference = 'Stop'

# ── Configuration resolution ─────────────────────────────────────────────────
$scriptDir = Split-Path -Parent $PSCommandPath
$defaultConfigPath = Join-Path $scriptDir 'config' 'defaults.json'

$config = @{
    serverUrl            = 'https://vault.bitwarden.eu'
    vaultItemName        = 'Bitwarden SM - ops-bootstrap Access Token'
    accessTokenFieldName = 'Access Token'
}

if (Test-Path $defaultConfigPath) {
    $defaults = Get-Content $defaultConfigPath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in $defaults.Keys) { $config[$key] = $defaults[$key] }
}

if ($ConfigPath -and (Test-Path $ConfigPath)) {
    $user = Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in $user.Keys) { $config[$key] = $user[$key] }
}

if ($ServerUrl)             { $config['serverUrl'] = $ServerUrl }
if ($VaultItemName)         { $config['vaultItemName'] = $VaultItemName }
if ($AccessTokenFieldName)  { $config['accessTokenFieldName'] = $AccessTokenFieldName }

# ── Isolate mode ──────────────────────────────────────────────────────────────
if ($Isolate) {
    $argList = @('-NoExit', '-File', $PSCommandPath, '-ServerUrl', $config['serverUrl'],
                '-VaultItemName', $config['vaultItemName'],
                '-AccessTokenFieldName', $config['accessTokenFieldName'])
    Start-Process -FilePath 'pwsh' -ArgumentList $argList -WindowStyle Normal
    Write-Host 'Isolated session launched in a new window.' -ForegroundColor Green
    return
}

# ── Prerequisite checks ───────────────────────────────────────────────────────
$required = @('bw', 'bws')
foreach ($tool in $required) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "'$tool' was not found in PATH. Install the Bitwarden CLI and ensure it is on your PATH."
    }
}

# ── Status & server configuration ─────────────────────────────────────────────
$statusJson = & bw status --raw 2>$null
if ($LASTEXITCODE -ne 0 -or -not $statusJson) {
    throw "Unable to query Bitwarden status. Ensure 'bw' is working."
}

$status = $statusJson | ConvertFrom-Json

if ($status.status -eq 'unauthenticated') {
    throw "You are not logged in to Bitwarden on this device. Run 'bw login' first, then re-run bw-shield."
}

# bw config server requires logout first, so only run when necessary
if ($status.serverUrl -ne $config['serverUrl']) {
    & bw config server $config['serverUrl'] 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to switch Bitwarden server. Run 'bw logout' first if you need to change servers."
    }
}

& bws config server-base $config['serverUrl'] 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Failed to configure Secrets Manager server-base." }

# ── Authentication ──────────────────────────────────────────────────────────────
if ($Host.Name -eq 'ConsoleHost') { try { Clear-Host } catch { } }
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '                     bw-shield v1.0.0                           ' -ForegroundColor Cyan
Write-Host '        Isolated Bitwarden Session for Secure Workflows         ' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ''

if ($status.status -eq 'locked') {
    Write-Host 'Bitwarden vault is locked.' -ForegroundColor Yellow

    if ($PasswordFile -and (Test-Path $PasswordFile)) {
        Write-Host "Using password from file (will be deleted after unlock)..." -ForegroundColor DarkGray
        $env:BW_SESSION = (& bw unlock --passwordfile $PasswordFile --raw 2>$null).Trim()
        Remove-Item -LiteralPath $PasswordFile -Force
        if ($LASTEXITCODE -ne 0 -or -not $env:BW_SESSION) {
            throw "Authentication failed. Check your master password in the file."
        }
    }
    else {
        $securePassword = Read-Host 'Enter your Bitwarden master password' -AsSecureString

        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)

        try {
            $env:BW_SESSION = ($plain | bw unlock --raw 2>$null).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $env:BW_SESSION) {
                throw "Authentication failed. Check your master password."
            }
        }
        finally {
            $plain = $null
            [System.GC]::Collect()
        }
    }
    Write-Host '[OK] Password Manager authenticated' -ForegroundColor Green
}
elseif ($status.status -eq 'unlocked') {
    Write-Host '[OK] Vault already unlocked' -ForegroundColor Green
}

# ── Retrieve machine account access token ─────────────────────────────────────
Write-Host ''
Write-Host 'Retrieving Machine Account Token...' -ForegroundColor Yellow

try {
    & bw sync --session $env:BW_SESSION 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Vault sync failed (exit: $LASTEXITCODE)" }

    $itemsJson = & bw list items --search $config['vaultItemName'] --session $env:BW_SESSION 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Failed to list vault items (exit: $LASTEXITCODE)" }
    if (-not $itemsJson) { throw "No items returned from vault search." }

    $items = $itemsJson | ConvertFrom-Json
    $item = $items | Where-Object { $_.name -eq $config['vaultItemName'] } | Select-Object -First 1

    if (-not $item) {
        throw "'$($config['vaultItemName'])' not found in vault. Create it via the Bitwarden web vault."
    }

    $tokenField = $item.fields | Where-Object { $_.name -eq $config['accessTokenFieldName'] }
    if (-not $tokenField -or -not $tokenField.value -or $tokenField.value -eq 'PASTE_TOKEN_HERE') {
        throw "Access Token field is empty or not yet configured. Open the vault item and paste the token."
    }

    $env:BWS_ACCESS_TOKEN = $tokenField.value
    Write-Host '[OK] Machine account token loaded' -ForegroundColor Green
}
catch {
    Write-Host "[WARN] $_" -ForegroundColor Red
}

# ── Ready ─────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '  Session ready                                                ' -ForegroundColor Cyan
Write-Host '  BW_SESSION        | Password Manager session key             ' -ForegroundColor Cyan
Write-Host '  BWS_ACCESS_TOKEN  | Secrets Manager machine account token     ' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Available commands:' -ForegroundColor White
Write-Host '  bw list items          List Password Manager items' -ForegroundColor Gray
Write-Host '  bw get item <name>     Retrieve a specific item' -ForegroundColor Gray
Write-Host '  bws project list       List Secrets Manager projects' -ForegroundColor Gray
Write-Host '  bws secret list        List Secrets Manager secrets' -ForegroundColor Gray
Write-Host '  bws secret get <id>    Retrieve a specific secret' -ForegroundColor Gray
Write-Host ''
Write-Host "Type 'bw --help' or 'bws --help' for full command reference." -ForegroundColor DarkGray
