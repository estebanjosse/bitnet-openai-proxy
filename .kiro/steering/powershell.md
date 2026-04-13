# Shell Environment

This project is developed on Windows using PowerShell.

## Command Guidelines

- Always use PowerShell syntax for shell commands
- Use `;` as command separator (not `&&`)
- Use `New-Item`, `Remove-Item`, `Copy-Item` instead of `mkdir`, `rm`, `cp`
- Use `Get-Content` instead of `cat`
- Use `Select-String` instead of `grep`
- Never suggest bash-only syntax (e.g. `&&`, `||` chaining, `$(...)` subshells in bash style)
- For running scripts, use `.\script.ps1` syntax
- Environment variables are accessed as `$env:VAR_NAME`

## Notes

- The shell scripts in this project (e.g. `entrypoint.sh`) are intended to run **inside Linux Docker containers**, not on the host. They use POSIX sh syntax intentionally.
- Host-side commands (building Docker images, running tests, etc.) must use PowerShell syntax.
