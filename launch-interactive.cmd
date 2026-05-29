@echo off
:: Launch bw-shield in a visible interactive PowerShell window.
:: This is the reliable way to open the script when starting from a
:: non-interactive shell (e.g. an AI agent or CI runner).
::
:: Usage:
::   launch-interactive.cmd
::
:: Why not Start-Process pwsh ...?
::   PowerShell started via Start-Process inherits NonInteractive mode
::   from the parent shell, which blocks Read-Host and causes the window
::   to close immediately. Using "cmd /c start" guarantees a truly
::   interactive console.
pwsh -Interactive -NoProfile -NoExit -File "%~dp0bw-shield.ps1"
