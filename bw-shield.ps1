#requires -Version 7.2

<#
.SYNOPSIS
    Initializes an isolated, secure Bitwarden session shielded from the parent environment.

.DESCRIPTION
    bw-shield spawns a new PowerShell window where you authenticate to Bitwarden
    Password Manager and Secrets Manager. The master password, session key, and
    machine account access token are confined to the child process and are never
    exposed to the parent terminal, shell history, or any AI assistants running
    in the parent session.

    Secrets are never written to disk. All credentials live only in memory
    inside the isolated child process.

.PARAMETER ServerUrl
    Bitwarden server URL. Defaults to the value in the config file
    or https://vault.bitwarden.eu.

.PARAMETER VaultItemName
    Name of the Password Manager vault item that stores the machine account token.
    Defaults to the value in the config file.

.PARAMETER AccessTokenFieldName
    Name of the custom field within the vault item that holds the access token.
    Defaults to the value in the config file.

.PARAMETER ConfigPath
    Path to a JSON configuration file.

.PARAMETER NoProfile
    Do not load the PowerShell profile in the child session.

.PARAMETER Child
    Internal flag. Indicates this instance is the isolated child session.
    Do not use manually.
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
    [switch]$NoProfile,

    [Parameter()]
    [switch]$Child
)

$ErrorActionPreference = 'Stop'

# Resolve configuration precedence: CLI > config file > defaults
$scriptDir = Split-Path -Parent $PSCommandPath
$defaultConfigPath = Join-Path $scriptDir 'config' 'defaults.json'

$config = @{}
if (Test-Path $defaultConfigPath) {
    $config = Get-Content $defaultConfigPath -Raw | ConvertFrom-Json -AsHashtable
}

if ($ConfigPath -and (Test-Path $ConfigPath)) {
    $userConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in $userConfig.Keys) {
        $config[$key] = $userConfig[$key]
    }
}

# Apply CLI overrides last
if ($ServerUrl) { $config['serverUrl'] = $ServerUrl }
if ($VaultItemName) { $config['vaultItemName'] = $VaultItemName }
if ($AccessTokenFieldName) { $config['accessTokenFieldName'] = $AccessTokenFieldName }

# Ensure defaults exist
if (-not $config['serverUrl']) { $config['serverUrl'] = 'https://vault.bitwarden.eu' }
if (-not $config['vaultItemName']) { $config['vaultItemName'] = 'Bitwarden SM - ops-bootstrap Access Token' }
if (-not $config['accessTokenFieldName']) { $config['accessTokenFieldName'] = 'Access Token' }

# ── Spawn child session if this is the parent ─────────────────────────────────
if (-not $Child) {
    $argList = @('-NoExit')
    if ($NoProfile) { $argList += '-NoProfile' }
    $argList += '-File', $PSCommandPath, '-Child'

    # Forward resolved config so the child doesn't re-read (avoids file races)
    $argList += '-ServerUrl', $config['serverUrl']
    $argList += '-VaultItemName', $config['vaultItemName']
    $argList += '-AccessTokenFieldName', $config['accessTokenFieldName']

    Start-Process -FilePath 'pwsh' -ArgumentList $argList -WindowStyle Normal
    exit
}

# ── Child session logic ───────────────────────────────────────────────────────

# Verify CLI tools
$requiredTools = @('bw', 'bws')
foreach ($tool in $requiredTools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: '$tool' was not found in PATH." -ForegroundColor Red
        Write-Host "       Install the Bitwarden CLI and ensure it is on your PATH." -ForegroundColor Yellow
        Read-Host "`nPress Enter to exit"
        exit 1
    }
}

# Configure server
try {
    & bw config server $config['serverUrl'] 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "bw config server failed (exit: $LASTEXITCODE)" }

    & bws config server-base $config['serverUrl'] 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "bws config server-base failed (exit: $LASTEXITCODE)" }
}
catch {
    Write-Host "ERROR: Failed to configure Bitwarden server ($($config['serverUrl']))." -ForegroundColor Red
    Write-Host "       $_" -ForegroundColor DarkGray
    Read-Host "`nPress Enter to exit"
    exit 1
}

Clear-Host

Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '                     bw-shield v1.0.0                           ' -ForegroundColor Cyan
Write-Host '        Isolated Bitwarden Session for Secure Workflows         ' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ''

# ── Step 1: Check login status ────────────────────────────────────────────────
$statusJson = & bw status --raw 2>$null
if ($LASTEXITCODE -ne 0 -or -not $statusJson) {
    Write-Host "ERROR: Unable to query Bitwarden status. Ensure 'bw' is working." -ForegroundColor Red
    Read-Host "`nPress Enter to exit"
    exit 1
}

$status = $statusJson | ConvertFrom-Json
if ($status.status -eq 'unauthenticated') {
    Write-Host "ERROR: You are not logged in to Bitwarden on this device." -ForegroundColor Red
    Write-Host "       Run 'bw login' first, then re-run bw-shield." -ForegroundColor Yellow
    Read-Host "`nPress Enter to exit"
    exit 1
}

# ── Step 2: Unlock / authenticate ─────────────────────────────────────────────
Write-Host 'Step 1: Password Manager Authentication' -ForegroundColor Yellow
Write-Host '────────────────────────────────────────' -ForegroundColor DarkYellow

$securePassword = Read-Host 'Enter your Bitwarden master password' -AsSecureString
$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)

try {
    $env:BW_SESSION = ($plainPassword | bw unlock --raw 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $env:BW_SESSION) {
        throw "Authentication failed. Check your master password."
    }
    Write-Host "  [OK] Password Manager authenticated" -ForegroundColor Green
}
catch {
    Write-Host "  [FAIL] $_" -ForegroundColor Red
    Read-Host "`nPress Enter to exit"
    exit 1
}
finally {
    $plainPassword = $null
    [System.GC]::Collect()
}

# ── Step 3: Retrieve machine account access token ─────────────────────────────
Write-Host ''
Write-Host 'Step 2: Retrieving Machine Account Token' -ForegroundColor Yellow
Write-Host '─────────────────────────────────────────' -ForegroundColor DarkYellow

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
    Write-Host "  [OK] Machine account token loaded" -ForegroundColor Green
}
catch {
    Write-Host "  [FAIL] $_" -ForegroundColor Red
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
Write-Host '  bws project list     List Secrets Manager projects' -ForegroundColor Gray
Write-Host '  bws secret list      List Secrets Manager secrets' -ForegroundColor Gray
Write-Host '  bws project create   Create a new project' -ForegroundColor Gray
Write-Host '  bws secret create    Create a new secret' -ForegroundColor Gray
Write-Host '  exit                 Close this isolated session' -ForegroundColor Gray
Write-Host ''
Write-Host "Type 'bws --help' for full command reference." -ForegroundColor DarkGray
