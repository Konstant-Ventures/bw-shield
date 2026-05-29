#requires -version 7

<#
.SYNOPSIS
    Initializes a secure Bitwarden session in an isolated terminal window.

.DESCRIPTION
    Opens a new PowerShell window and:
    1. Prompts for the master password (secure input, never exposed to parent terminal)
    2. Authenticates to Bitwarden Password Manager (bw) and stores the session key
       as $env:BW_SESSION in the child process only
    3. Retrieves the ops-bootstrap machine account access token from the vault
       and stores it as $env:BWS_ACCESS_TOKEN in the child process only
    4. Configures bws (Secrets Manager CLI) for the correct server
    5. Leaves you in a ready-to-use shell

    Neither the master password, session key, nor access token are ever written
    to disk or visible outside the child process.

.EXAMPLE
    .\bw-init.ps1
#>

# ── Detect if we're already in the child session ──────────────────────────────
if (-not $env:BW_INIT_CHILD) {
    $env:BW_INIT_CHILD = "1"
    $child = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoExit -Command `"& '$($PSCommandPath)'`"" -PassThru -WindowStyle Normal
    exit
}

# ── Server configuration ─────────────────────────────────────────────────────
$serverUrl = "https://vault.bitwarden.eu"
bw config server $serverUrl 2>&1 | Out-Null
bws config server-base $serverUrl 2>&1 | Out-Null

# ── Step 1: Authenticate to Password Manager ─────────────────────────────────
Clear-Host
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Bitwarden Session Initializer               ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 1: Password Manager Authentication" -ForegroundColor Yellow
Write-Host "────────────────────────────────────────" -ForegroundColor DarkYellow

$securePassword = Read-Host "Enter your Bitwarden master password" -AsSecureString
$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)

try {
    $raw = $plainPassword | bw unlock --raw 2>&1
    if (-not $raw -or $raw -is [System.Management.Automation.ErrorRecord]) {
        throw "Authentication failed. Check your master password."
    }
    $env:BW_SESSION = "$raw".Trim()
    Write-Host "  ✓ Password Manager authenticated" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
finally {
    $plainPassword = $null
    [System.GC]::Collect()
}

# ── Step 2: Retrieve machine account access token ────────────────────────────
Write-Host ""
Write-Host "Step 2: Retrieving Machine Account Token" -ForegroundColor Yellow
Write-Host "────────────────────────────────────────" -ForegroundColor DarkYellow

try {
    bw sync --session $env:BW_SESSION 2>$null | Out-Null
    $items = bw list items --search "ops-bootstrap" --session $env:BW_SESSION 2>$null | ConvertFrom-Json
    $item = $items | Where-Object { $_.name -eq "Bitwarden SM - ops-bootstrap Access Token" } | Select-Object -First 1

    if (-not $item) {
        Write-Host "  ✗ 'Bitwarden SM - ops-bootstrap Access Token' not found in vault" -ForegroundColor Red
        Write-Host "    Create it first via the Bitwarden web vault or add it to your vault." -ForegroundColor Yellow
    }
    else {
        $tokenField = $item.fields | Where-Object { $_.name -eq "Access Token" }
        if (-not $tokenField -or -not $tokenField.value -or $tokenField.value -eq "PASTE_TOKEN_HERE") {
            Write-Host "  ✗ Access Token field is empty or not yet configured" -ForegroundColor Red
            Write-Host "    Open the vault item and paste the access token into the 'Access Token' field." -ForegroundColor Yellow
        }
        else {
            $env:BWS_ACCESS_TOKEN = $tokenField.value
            Write-Host "  ✓ Machine account token loaded" -ForegroundColor Green
        }
    }
}
catch {
    Write-Host "  ✗ Failed to retrieve token: $_" -ForegroundColor Red
}

# ── Ready ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Session ready                                   ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  BW_SESSION      │ Password Manager session     ║" -ForegroundColor Cyan
Write-Host "║  BWS_ACCESS_TOKEN │ Secrets Manager access      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Available commands:" -ForegroundColor White
Write-Host "  bws project list     List Secrets Manager projects" -ForegroundColor Gray
Write-Host "  bws secret list      List Secrets Manager secrets" -ForegroundColor Gray
Write-Host "  bws project create   Create a new project" -ForegroundColor Gray
Write-Host "  bws secret create    Create a new secret" -ForegroundColor Gray
Write-Host "  exit                 Close this session" -ForegroundColor Gray
Write-Host ""
Write-Host "Type 'bws --help' for full command reference." -ForegroundColor DarkGray
