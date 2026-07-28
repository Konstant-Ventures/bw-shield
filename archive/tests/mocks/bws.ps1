# Mock Bitwarden Secrets Manager CLI for end-to-end testing
if ($args -contains 'config' -and $args -contains 'server-base') {
    'Profile updated successfully.'
    exit 0
}

exit 0
