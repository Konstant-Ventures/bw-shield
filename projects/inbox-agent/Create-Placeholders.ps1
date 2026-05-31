# Create Inbox Agent Placeholder Secrets

#Requires -Version 7.2

<#
.SYNOPSIS
    Create placeholder secrets in Bitwarden Secrets Manager for the Inbox Agent.

.DESCRIPTION
    Run this after authenticating via secret-gate. It creates all placeholder
    secrets the Inbox Agent needs. You must then replace the placeholders in
    the Bitwarden web UI.

    Prerequisites:
    - secret-gate authenticated (BW_SESSION and BWS_ACCESS_TOKEN set)
    - bws CLI available
#>

$ErrorActionPreference = 'Stop'

# Resolve the project
$projectName = 'workspaces'
$projects = & bws project list 2>$null | ConvertFrom-Json
$project = $projects | Where-Object { $_.name -eq $projectName } | Select-Object -First 1

if (-not $project) {
    throw "Project '$projectName' not found in Bitwarden Secrets Manager."
}

$projectId = $project.id

$secrets = @(
    @{ name = 'INBOX_TELEGRAM_BOT_TOKEN';      note = 'Telegram Bot token from @BotFather. Replace placeholder in Bitwarden web UI.' }
    @{ name = 'INBOX_OWNER_USER_ID';           note = 'Numeric Telegram user ID. Replace placeholder in Bitwarden web UI.' }
    @{ name = 'INBOX_TELEGRAM_GROUP_CHAT_ID';  note = 'Telegram group chat ID (optional). Replace placeholder in Bitwarden web UI.' }
    @{ name = 'INBOX_GMAIL_CLIENT_ID';         note = 'Google Cloud OAuth client ID. Replace placeholder in Bitwarden web UI.' }
    @{ name = 'INBOX_GMAIL_CLIENT_SECRET';     note = 'Google Cloud OAuth client secret. Replace placeholder in Bitwarden web UI.' }
    @{ name = 'INBOX_OPENCODE_API_KEY';        note = 'OpenCode API key for LLM calls. Replace placeholder in Bitwarden web UI.' }
)

foreach ($secret in $secrets) {
    try {
        & bws secret create `
            $secret.name `
            "TODO_REPLACE_IN_BITWARDEN_WEB_UI" `
            $projectId `
            --note $secret.note `
            --output none
        Write-Host "[OK] Created placeholder: $($secret.name)" -ForegroundColor Green
    }
    catch {
        if ($_ -match 'already exists') {
            Write-Host "[SKIP] $($secret.name) already exists" -ForegroundColor DarkGray
        } else {
            Write-Host "[ERR] $($secret.name): $_" -ForegroundColor Red
        }
    }
}

Write-Host ''
Write-Host 'All placeholders created. Update them here:' -ForegroundColor Cyan
Write-Host 'https://vault.bitwarden.eu/#/sm' -ForegroundColor White
