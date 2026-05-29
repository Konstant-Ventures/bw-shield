<#
.SYNOPSIS
    Launches secret-gate for authentication.
.DESCRIPTION
    Runs secret-gate.ps1 which pops up a GUI password dialog on the desktop.
    The user types their master password, authentication happens in the
    current session, and BW_SESSION / BWS_ACCESS_TOKEN are exported so
    AI agents can use bw and bws commands immediately.
#>
$scriptDir = Split-Path -Parent $PSCommandPath
. $scriptDir\secret-gate.ps1 @args
