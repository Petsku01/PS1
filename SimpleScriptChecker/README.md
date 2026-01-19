# Simple Script Checker

A lightweight PowerShell script analyzer for everyday use. Checks for common issues without enterprise complexity.

**Author:** -pk

## Quick Start

```powershell
# Check a single script
.\Check-Script.ps1 -ScriptPath .\MyScript.ps1

# Check all scripts in a folder
.\Check-Script.ps1 -ScriptPath .\MyScripts

# Generate HTML report
.\Check-Script.ps1 -ScriptPath .\MyScripts -ShowReport
```

## What It Checks

### High Priority
- **Syntax Errors** - Parse errors that prevent execution
- **Hardcoded Passwords** - Plaintext passwords in code
- **Risky Operations** - Destructive commands without error handling

### Medium Priority
- **Execution Policy Bypass** - Attempts to bypass security
- **Missing Error Handling** - Operations that should have try/catch

### Low Priority
- **Hardcoded Paths** - Non-portable file paths
- **Silent Errors** - ErrorAction SilentlyContinue usage
- **Write-Host Usage** - Non-pipeline-friendly output
- **Missing Documentation** - No comment-based help
- **Missing Parameters** - Scripts without param blocks

## Example Output

```
Simple Script Checker v1.0
==========================

Scanning folder: .\MyScripts
Found 5 script(s) to check

Checking: Deploy.ps1
  ! Found 3 issue(s)
Checking: Backup.ps1
  No issues
Checking: Report.ps1
  ! Found 1 issue(s)

=== Summary ===
Scripts checked: 5
Total issues: 4
  HIGH: 1
  MEDIUM: 1
  LOW: 2

Tip: Use -ShowReport to generate HTML report
```

## Features

- **Simple** - One file, no dependencies  
- **Fast** - Lightweight checks only  
- **Practical** - Focused on real issues  
- **HTML Reports** - Visual issue tracking  
- **XSS Safe** - All output properly encoded  

## Differences from Enterprise Version

| Feature | Simple | Enterprise |
|---------|--------|-----------|
| Size | 1 file (~400 lines) | Multiple modules |
| Checks | 8 essential | 20+ comprehensive |
| AST Analysis | No | Yes |
| Baseline Tracking | No | Yes |
| Auto-Fix | No | Yes |
| Parallel Processing | No | Yes |
| Setup Time | 0 minutes | 10+ minutes |
| Target Audience | Individual devs | Teams/Enterprise |

## When to Use This Version

- Quick checks on personal scripts  
- Learning PowerShell best practices  
- Small teams without strict standards  
- One-off script validation  
- CI/CD basic quality gates  

## When to Use Enterprise Version

- FAANG-level code review  
- Compliance requirements  
- Large codebases (100+ scripts)  
- Complex security auditing  
- Automated remediation  

## Requirements

- PowerShell 5.1 or later
- No external dependencies

## License

Use freely for any purpose.

## Tips

1. Run before committing scripts to version control
2. Use `-ShowReport` for team reviews
3. Fix HIGH issues first, LOW issues are optional
4. Add to your PowerShell profile for quick access:
   ```powershell
   function Check { .\path\to\Check-Script.ps1 @args }
   ```

## Common Issues & Fixes

**"Hardcoded Password"**
```powershell
# Bad
$password = "Secret123"

# Good
$cred = Get-Credential
```

**"Hardcoded Path"**
```powershell
# Bad
$path = "C:\Users\John\Documents"

# Good
$path = Join-Path $env:USERPROFILE "Documents"
```

**"Missing Error Handling"**
```powershell
# Bad
Remove-Item $file

# Good
try {
    Remove-Item $file -ErrorAction Stop
} catch {
    Write-Error "Failed to delete: $_"
}
```

---

**Version**: 1.0  
**Author**: -pk 
**Updated**: January 2026
