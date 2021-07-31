ECHO Calling: SetPageFileSize.ps1 -MinimumSize %1 -MaximumSize %2 -DiskRoot %3
SET ThisScriptsDirectory=%~dp0
SET PowerShellScriptPath=%ThisScriptsDirectory%SetPageFileSize.ps1
:: assumes this file is colocated with SetPageFileSize.ps1
:: arguments need to be passed in order
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '%PowerShellScriptPath%' -MinimumSize %1 -MaximumSize %2 -DiskRoot %3"
