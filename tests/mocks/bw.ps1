# Mock Bitwarden CLI for end-to-end testing
if ($args -contains 'status' -and $args -contains '--raw') {
    '{"serverUrl":"https://vault.bitwarden.eu","status":"locked"}'
    exit 0
}

if ($args -contains 'config' -and $args -contains 'server') {
    exit 0
}

if ($args -contains 'unlock' -and $args -contains '--raw') {
    $password = $input | Out-String
    if ($password -match 'CorrectPassword123!') {
        'mock-bw-session-key-abc123'
        exit 0
    }
    exit 1
}

if ($args -contains 'sync') {
    exit 0
}

if ($args -contains 'list' -and $args -contains 'items') {
    $result = @(
        [PSCustomObject]@{
            name   = 'Bitwarden SM - ops-bootstrap Access Token'
            fields = @(
                [PSCustomObject]@{ name = 'Access Token'; value = 'mock-bws-token-xyz789' }
            )
        }
    ) | ConvertTo-Json -Depth 3 -AsArray
    $result
    exit 0
}

exit 0
