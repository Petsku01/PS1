<#
.SYNOPSIS
    Simple PowerShell script checker for common issues

.DESCRIPTION
    Lightweight script analyzer that checks for common PowerShell issues
    Designed for everyday use in normal environments (not enterprise/FAANG)

.PARAMETER ScriptPath
    Path to the script or folder to check

.PARAMETER ShowReport
    Generate HTML report

.EXAMPLE
    .\Check-Script.ps1 -ScriptPath .\MyScript.ps1
    
.EXAMPLE
    .\Check-Script.ps1 -ScriptPath .\scripts -ShowReport

.NOTES
    Author: -pk
    Version: 1.1
    Simple version - checks essential issues only
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({
        if (-not (Test-Path $_)) {
            throw "Path does not exist: $_"
        }
        $true
    })]
    [string]$ScriptPath,
    
    [Parameter()]
    [switch]$ShowReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$script:Issues = @()

function Write-Console {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [object[]]$Object,
        [ConsoleColor]$ForegroundColor,
        [ConsoleColor]$BackgroundColor,
        [switch]$NoNewline,
        [object]$Separator
    )

    Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
}

function Test-ScriptSyntax {
    param([string]$FilePath, [string]$Content)
    
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return
    }
    
    $parseErrors = @()
    try {
        $null = [System.Management.Automation.Language.Parser]::ParseInput(
            $Content,
            [ref]$null,
            [ref]$parseErrors
        )
        
        if ($parseErrors.Count -gt 0) {
            foreach ($err in $parseErrors) {
                $script:Issues += [PSCustomObject]@{
                    File = $FilePath
                    Line = $err.Extent.StartLineNumber
                    Severity = 'HIGH'
                    Issue = 'Syntax Error'
                    Description = $err.Message
                    Fix = 'Correct the syntax error'
                }
            }
        }
    }
    catch {
        Write-Warning "Parse error for ${FilePath}: $($_.Exception.Message)"
        $script:Issues += [PSCustomObject]@{
            File = $FilePath
            Line = 1
            Severity = 'HIGH'
            Issue = 'Parse Failed'
            Description = $_.Exception.Message
            Fix = 'Fix syntax errors'
        }
    }
}

function Test-CommonIssues {
    param([string]$FilePath, [string]$Content)
    
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return
    }
    
    $lines = $Content -split "`n"
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNum = $i + 1
        
        # Check for hardcoded passwords
        if ($line -match '\$password\s*=\s*["'']|ConvertTo-SecureString.*-AsPlainText') {
            $script:Issues += [PSCustomObject]@{
                File = $FilePath
                Line = $lineNum
                Severity = 'HIGH'
                Issue = 'Hardcoded Password'
                Description = 'Password appears to be hardcoded in script'
                Fix = 'Use Get-Credential or secure credential storage'
            }
        }
        
        # Check for execution policy bypass
        if ($line -match 'Set-ExecutionPolicy.*Bypass' -and $line -notmatch '^\s*#') {
            $script:Issues += [PSCustomObject]@{
                File = $FilePath
                Line = $lineNum
                Severity = 'MEDIUM'
                Issue = 'Execution Policy Bypass'
                Description = 'Script tries to bypass execution policy'
                Fix = 'Remove bypass or add proper signing'
            }
        }
        
        # Check for hardcoded paths
        if ($line -match '[A-Za-z]:\\[^"''`$\s]+' -and $line -notmatch '^\s*#' -and $line -notmatch 'TEMP|TMP|SystemRoot') {
            if ($line -match '(C:\\Users\\[^\\]+|C:\\Windows\\System32)') {
                $script:Issues += [PSCustomObject]@{
                    File = $FilePath
                    Line = $lineNum
                    Severity = 'LOW'
                    Issue = 'Hardcoded Path'
                    Description = 'Path is hardcoded and may not work on other systems'
                    Fix = 'Use environment variables or parameters'
                }
            }
        }
        
        # Check for silent error suppression
        if ($line -match '-ErrorAction\s+SilentlyContinue' -and $line -notmatch '^\s*#') {
            $script:Issues += [PSCustomObject]@{
                File = $FilePath
                Line = $lineNum
                Severity = 'LOW'
                Issue = 'Silent Error Suppression'
                Description = 'Errors are silently ignored'
                Fix = 'Add proper error handling or use -ErrorAction Stop with try/catch'
            }
        }
        
        # Check for missing error handling in critical operations
        if ($line -match '(Remove-Item|Delete|Drop|Truncate)' -and $line -notmatch 'try|catch|\-ErrorAction|\-WhatIf' -and $line -notmatch '^\s*#') {
            $script:Issues += [PSCustomObject]@{
                File = $FilePath
                Line = $lineNum
                Severity = 'MEDIUM'
                Issue = 'Risky Operation Without Error Handling'
                Description = 'Destructive operation without error handling'
                Fix = 'Wrap in try/catch or add -WhatIf/-Confirm support'
            }
        }
        
        # Check for Write-Host (should use Write-Output)
        if ($line -match 'Write-Host' -and $line -notmatch '^\s*#') {
            $script:Issues += [PSCustomObject]@{
                File = $FilePath
                Line = $lineNum
                Severity = 'LOW'
                Issue = 'Write-Host Usage'
                Description = 'Write-Host cannot be captured in pipeline'
                Fix = 'Use Write-Output for data or Write-Verbose for messages'
            }
        }
    }
}

function Test-BestPractices {
    param([string]$FilePath, [string]$Content)
    
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return
    }
    
    # Check for comment-based help
    if ($Content -notmatch '<#[\s\S]*?\.SYNOPSIS[\s\S]*?#>') {
        $script:Issues += [PSCustomObject]@{
            File = $FilePath
            Line = 1
            Severity = 'LOW'
            Issue = 'Missing Help'
            Description = 'Script lacks comment-based help'
            Fix = 'Add .SYNOPSIS, .DESCRIPTION, .EXAMPLE'
        }
    }
    
    # Check for param block
    if ($Content -notmatch 'param\s*\(') {
        $script:Issues += [PSCustomObject]@{
            File = $FilePath
            Line = 1
            Severity = 'LOW'
            Issue = 'No Parameters'
            Description = 'Script has no param block (may be intentional)'
            Fix = 'Add param() block for reusability'
        }
    }
    
    # Check for cmdlet binding
    if ($Content -match 'param\s*\(' -and $Content -notmatch '\[CmdletBinding\(\)\]') {
        $script:Issues += [PSCustomObject]@{
            File = $FilePath
            Line = 1
            Severity = 'LOW'
            Issue = 'No CmdletBinding'
            Description = 'Param block without [CmdletBinding()]'
            Fix = 'Add [CmdletBinding()] for advanced features'
        }
    }
}

function New-SimpleReport {
    param([array]$AllIssues)
    
    try {
        # Create Reports folder if it doesn't exist
        $reportsFolder = Join-Path $PSScriptRoot "Reports"
        if (-not (Test-Path $reportsFolder)) {
            New-Item -ItemType Directory -Path $reportsFolder -Force -ErrorAction Stop | Out-Null
        }
        
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $reportPath = Join-Path $reportsFolder "ScriptCheck_$timestamp.html"
    
    $criticalCount = @($AllIssues | Where-Object { $_.Severity -eq 'CRITICAL' }).Count
    $highCount = @($AllIssues | Where-Object { $_.Severity -eq 'HIGH' }).Count
    $mediumCount = @($AllIssues | Where-Object { $_.Severity -eq 'MEDIUM' }).Count
    $lowCount = @($AllIssues | Where-Object { $_.Severity -eq 'LOW' }).Count
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Script Check Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #4CAF50; padding-bottom: 10px; }
        .summary { display: flex; gap: 15px; margin: 20px 0; }
        .stat-box { flex: 1; padding: 15px; border-radius: 5px; text-align: center; }
        .stat-box h3 { margin: 0; font-size: 32px; }
        .stat-box p { margin: 5px 0 0 0; color: #666; }
        .critical { background: #ffebee; border-left: 4px solid #d32f2f; }
        .high { background: #fff3e0; border-left: 4px solid #f57c00; }
        .medium { background: #fff9c4; border-left: 4px solid #fbc02d; }
        .low { background: #e8f5e9; border-left: 4px solid #388e3c; }
        .issue { margin: 15px 0; padding: 15px; border-left: 4px solid #ccc; background: #fafafa; }
        .issue.critical { border-left-color: #d32f2f; }
        .issue.high { border-left-color: #f57c00; }
        .issue.medium { border-left-color: #fbc02d; }
        .issue.low { border-left-color: #388e3c; }
        .issue h3 { margin: 0 0 5px 0; color: #333; }
        .issue .meta { color: #666; font-size: 0.9em; margin: 5px 0; }
        .issue .fix { margin-top: 10px; padding: 10px; background: #e3f2fd; border-radius: 3px; }
        .no-issues { text-align: center; padding: 40px; color: #4CAF50; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Script Check Report</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        
        <div class="summary">
            <div class="stat-box critical">
                <h3>$criticalCount</h3>
                <p>Critical</p>
            </div>
            <div class="stat-box high">
                <h3>$highCount</h3>
                <p>High</p>
            </div>
            <div class="stat-box medium">
                <h3>$mediumCount</h3>
                <p>Medium</p>
            </div>
            <div class="stat-box low">
                <h3>$lowCount</h3>
                <p>Low</p>
            </div>
        </div>
        
        <h2>Issues Found: $($AllIssues.Count)</h2>
"@
    
    if ($AllIssues.Count -eq 0) {
        $html += '<div class="no-issues"><h2>No Issues Found!</h2><p>Your script looks good.</p></div>'
    }
    else {
        foreach ($issue in $AllIssues | Sort-Object Severity, File, Line) {
            $severityClass = $issue.Severity.ToLower()
            $encodedFile = [System.Web.HttpUtility]::HtmlEncode($issue.File)
            $encodedIssue = [System.Web.HttpUtility]::HtmlEncode($issue.Issue)
            $encodedDesc = [System.Web.HttpUtility]::HtmlEncode($issue.Description)
            $encodedFix = [System.Web.HttpUtility]::HtmlEncode($issue.Fix)
            
            $html += @"
        <div class="issue $severityClass">
            <h3>[$($issue.Severity)] $encodedIssue</h3>
            <div class="meta">
                <strong>File:</strong> $encodedFile<br>
                <strong>Line:</strong> $($issue.Line)
            </div>
            <p>$encodedDesc</p>
            <div class="fix"><strong>Fix:</strong> $encodedFix</div>
        </div>
"@
        }
    }
    
    $html += @"
    </div>
</body>
</html>
"@
    
        $html | Out-File $reportPath -Encoding UTF8 -ErrorAction Stop
        Write-Console "`nReport saved: $reportPath" -ForegroundColor Green
        
        try {
            Start-Process $reportPath -ErrorAction Stop
        }
        catch {
            Write-Warning "Report created but could not be opened automatically: $reportPath"
        }
    }
    catch {
        Write-Error "Failed to generate report: $($_.Exception.Message)"
        throw
    }
}

# Main execution
Write-Console "Simple Script Checker v1.1" -ForegroundColor Cyan
Write-Console "Author: -pk" -ForegroundColor Gray
Write-Console "==========================`n" -ForegroundColor Cyan

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Path not found: $ScriptPath"
    exit 1
}

$scriptsToCheck = @()

if (Test-Path $ScriptPath -PathType Container) {
    Write-Console "Scanning folder: $ScriptPath" -ForegroundColor Yellow
    $scriptsToCheck = @(Get-ChildItem -Path $ScriptPath -Include "*.ps1","*.psm1" -Recurse -File -ErrorAction SilentlyContinue)
    if ($scriptsToCheck.Count -eq 0) {
        Write-Console "No PowerShell scripts found" -ForegroundColor Red
        exit 1
    }
}
else {
    if ($ScriptPath -notlike "*.ps1" -and $ScriptPath -notlike "*.psm1") {
        Write-Console "Error: File must be a .ps1 or .psm1 script" -ForegroundColor Red
        exit 1
    }
    $scriptsToCheck = @(Get-Item $ScriptPath -ErrorAction Stop)
}

$scriptCount = @($scriptsToCheck).Count
Write-Console "Found $scriptCount script(s) to check`n" -ForegroundColor Cyan

foreach ($script in $scriptsToCheck) {
    Write-Console "Checking: $($script.Name)" -ForegroundColor White
    
    try {
        $content = Get-Content $script.FullName -Raw -ErrorAction Stop
        
        # Run checks
        Test-ScriptSyntax -FilePath $script.FullName -Content $content
        Test-CommonIssues -FilePath $script.FullName -Content $content
        Test-BestPractices -FilePath $script.FullName -Content $content
        
        $scriptIssues = @($script:Issues | Where-Object { $_.File -eq $script.FullName })
        if ($scriptIssues.Count -eq 0) {
            Write-Console "  No issues found" -ForegroundColor Green
        }
        else {
            Write-Console "  ! Found $($scriptIssues.Count) issue(s)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Failed to check $($script.Name): $_"
    }
}

# Summary
Write-Console "`n=== Summary ===" -ForegroundColor Cyan
Write-Console "Scripts checked: $($scriptsToCheck.Count)" -ForegroundColor White
Write-Console "Total issues: $($script:Issues.Count)" -ForegroundColor White

if ($script:Issues.Count -gt 0) {
    $grouped = $script:Issues | Group-Object Severity
    foreach ($group in $grouped | Sort-Object Name) {
        $color = switch ($group.Name) {
            'CRITICAL' { 'Red' }
            'HIGH' { 'DarkYellow' }
            'MEDIUM' { 'Yellow' }
            'LOW' { 'Gray' }
        }
        Write-Console "  $($group.Name): $($group.Count)" -ForegroundColor $color
    }
    
    if ($ShowReport) {
        New-SimpleReport -AllIssues $script:Issues
    }
    else {
        Write-Console "`nTip: Use -ShowReport to generate HTML report" -ForegroundColor Gray
    }
}
else {
    Write-Console "`nAll scripts look good!" -ForegroundColor Green
}

