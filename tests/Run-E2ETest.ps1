<#
.SYNOPSIS
    End-to-end test for secret-gate using mocked CLIs.
#>
$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path -Parent $PSScriptRoot
$mockDir    = Join-Path $repoRoot 'tests' 'mocks'
$scriptPath = Join-Path $repoRoot 'secret-gate.ps1'

# Override Read-Host so the script never blocks interactively
function Read-Host {
    param([string]$Prompt, [switch]$AsSecureString)
    $pass = 'CorrectPassword123!'
    if ($AsSecureString) {
        return ConvertTo-SecureString $pass -AsPlainText -Force
    }
    return $pass
}

# Override Clear-Host so the test output stays readable
function Clear-Host { }

# Set test mode so the GUI dialog is skipped (Read-Host mock handles it)
$env:SECRET_GATE_TEST = '1'

# Prepend mocks to PATH so the fake bw/bws are resolved first
$originalPath = $env:PATH
$env:PATH = "$mockDir;$env:PATH"

# Clean any leftover env vars from a previous run
$env:BW_SESSION      = $null
$env:BWS_ACCESS_TOKEN = $null

try {
    Write-Host '--- Running secret-gate end-to-end test ---' -ForegroundColor Cyan

    & $scriptPath

    # Assertions
    if ($env:BW_SESSION -ne 'mock-bw-session-key-abc123') {
        throw "Assertion failed: BW_SESSION = '$($env:BW_SESSION)' (expected 'mock-bw-session-key-abc123')"
    }
    Write-Host "[PASS] BW_SESSION is correct" -ForegroundColor Green

    if ($env:BWS_ACCESS_TOKEN -ne 'mock-bws-token-xyz789') {
        throw "Assertion failed: BWS_ACCESS_TOKEN = '$($env:BWS_ACCESS_TOKEN)' (expected 'mock-bws-token-xyz789')"
    }
    Write-Host "[PASS] BWS_ACCESS_TOKEN is correct" -ForegroundColor Green

    Write-Host ''
    Write-Host '--- ALL TESTS PASSED ---' -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host "--- TEST FAILED ---" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    exit 1
}
finally {
    $env:PATH = $originalPath
    $env:BW_SESSION = $null
    $env:BWS_ACCESS_TOKEN = $null
    $env:SECRET_GATE_TEST = $null
}
