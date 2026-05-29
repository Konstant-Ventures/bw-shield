<#
.SYNOPSIS
    Launches bw-shield in a new interactive PowerShell window.

.DESCRIPTION
    This is the reliable way to start bw-shield from a non-interactive shell
    (e.g. an AI agent, CI runner, or scheduled task). It uses cmd /c start
    to create a brand-new interactive console that does NOT inherit the parent
    shell's NonInteractive flag, so Read-Host works correctly.

    After the window opens, the user types their master password. The session
    key and access token are set in that new window's environment.

    If you need the AI to authenticate directly (without an interactive window),
    use bw-shield.ps1 with -PasswordFile instead.

.PARAMETER ServerUrl
.PARAMETER VaultItemName
.PARAMETER AccessTokenFieldName
.PARAMETER ConfigPath
    Forwarded to bw-shield.ps1.
#>
param(
    [string]$ServerUrl,
    [string]$VaultItemName,
    [string]$AccessTokenFieldName,
    [string]$ConfigPath
)

$scriptDir = Split-Path -Parent $PSCommandPath
$targetScript = Join-Path $scriptDir 'bw-shield.ps1'

# Build pwsh argument string
$pwshArgs = "-Interactive -NoProfile -NoExit -File `"$targetScript`""
if ($ServerUrl)             { $pwshArgs += " -ServerUrl `"$ServerUrl`"" }
if ($VaultItemName)         { $pwshArgs += " -VaultItemName `"$VaultItemName`"" }
if ($AccessTokenFieldName)  { $pwshArgs += " -AccessTokenFieldName `"$AccessTokenFieldName`"" }
if ($ConfigPath)            { $pwshArgs += " -ConfigPath `"$ConfigPath`"" }

# The proven working launcher: cmd /c start "" pwsh <args>
Start-Process -FilePath 'cmd' -ArgumentList '/c', 'start', '""', 'pwsh', $pwshArgs

Write-Host 'bw-shield launched in a new interactive window.' -ForegroundColor Green
Write-Host 'Please enter your master password when prompted.' -ForegroundColor Yellow
