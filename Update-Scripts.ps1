<#
.SYNOPSIS
    Analyzes PowerShell scripts for quality, security, and best practices

.DESCRIPTION
    This script analyzes PowerShell scripts in a directory and detects:
    - Security issues (execution policy bypass, credentials)
    - Path handling problems (hard-coded paths)
    - Error handling gaps
    - Admin privilege checks
    - Documentation completeness
    - Usage of CommonFunctions module

.PARAMETER ScriptPath
    Path to script file or directory to analyze. Default: current directory

.PARAMETER Fix
    Automatically apply safe fixes (backup created)

.PARAMETER Report
    Generate detailed HTML report

.PARAMETER Watch
    Monitor directory for new scripts and report issues automatically

.PARAMETER Baseline
    Create/update baseline of analyzed scripts

.PARAMETER CheckNew
    Only analyze scripts not in baseline

.EXAMPLE
    .\Update-Scripts.ps1 -ScriptPath . -Report
    Analyze all scripts in current directory and generate report
    
.EXAMPLE
    .\Update-Scripts.ps1 -ScriptPath . -Baseline
    Create baseline of all scripts for tracking new additions
    
.EXAMPLE
    .\Update-Scripts.ps1 -ScriptPath . -CheckNew
    Analyze only newly added scripts since last baseline

.EXAMPLE
    .\Update-Scripts.ps1 -ScriptPath . -Watch -Interval 60
    Monitor directory for new scripts every 60 seconds
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [ValidateScript({
        if (-not (Test-Path $_)) {
            throw "Path '$_' does not exist"
        }
        $item = Get-Item $_
        if (-not ($item -is [System.IO.DirectoryInfo] -or $item.Extension -in @('.ps1', '.psm1'))) {
            throw "Path must be a directory or PowerShell file (.ps1/.psm1)"
        }
        $true
    })]
    [string]$ScriptPath = ".",
    
    [Parameter()]
    [switch]$Fix,
    
    [Parameter()]
    [switch]$Report,
    
    [Parameter()]
    [switch]$Watch,
    
    [Parameter()]
    [switch]$Baseline,
    
    [Parameter()]
    [switch]$CheckNew,
    
    [Parameter()]
    [ValidateRange(10, 3600)]
    [int]$Interval = 300,
    
    [Parameter()]
    [switch]$Parallel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Issues = @()

# Import required modules with error handling
try {
    Import-Module "$PSScriptRoot\\CommonFunctions.psm1" -Force -ErrorAction Stop
    Write-Verbose "Loaded CommonFunctions module"
} catch {
    Write-Error "Failed to load CommonFunctions.psm1: $_"
    exit 1
}

# Load AstAnalyzer if available
$astAnalyzerPath = Join-Path $PSScriptRoot "src\\Analyzers\\AstAnalyzer.ps1"
if (Test-Path $astAnalyzerPath) {
    try {
        . $astAnalyzerPath
        $script:UseAstAnalyzer = $true
        Write-Verbose "Loaded AstAnalyzer for enhanced analysis"
    } catch {
        Write-Warning "Failed to load AstAnalyzer: $_. Using basic analysis."
        $script:UseAstAnalyzer = $false
    }
} else {
    $script:UseAstAnalyzer = $false
}

# Load AnalysisResult if available
$analysisResultPath = Join-Path $PSScriptRoot "src\\Core\\AnalysisResult.ps1"
if (Test-Path $analysisResultPath) {
    try {
        . $analysisResultPath
        $script:UseAnalysisResult = $true
        Write-Verbose "Loaded AnalysisResult for thread-safe processing"
    } catch {
        Write-Warning "Failed to load AnalysisResult: $_"
        $script:UseAnalysisResult = $false
    }
} else {
    $script:UseAnalysisResult = $false
}

# Import required modules with error handling
try {
    Import-Module "$PSScriptRoot\CommonFunctions.psm1" -Force -ErrorAction Stop
    Write-Verbose "Loaded CommonFunctions module"
} catch {
    Write-Error "Failed to load CommonFunctions.psm1: $_"
    exit 1
}

# Load AstAnalyzer if available
$astAnalyzerPath = Join-Path $PSScriptRoot "src\Analyzers\AstAnalyzer.ps1"
if (Test-Path $astAnalyzerPath) {
    try {
        . $astAnalyzerPath
        $script:UseAstAnalyzer = $true
        Write-Verbose "Loaded AstAnalyzer for enhanced analysis"
    } catch {
        Write-Warning "Failed to load AstAnalyzer: $_. Using basic analysis."
        $script:UseAstAnalyzer = $false
    }
} else {
    $script:UseAstAnalyzer = $false
}

# Load AnalysisResult if available
$analysisResultPath = Join-Path $PSScriptRoot "src\Core\AnalysisResult.ps1"
if (Test-Path $analysisResultPath) {
    try {
        . $analysisResultPath
        $script:UseAnalysisResult = $true
        Write-Verbose "Loaded AnalysisResult for thread-safe processing"
    } catch {
        Write-Warning "Failed to load AnalysisResult: $_"
        $script:UseAnalysisResult = $false
    }
} else {
    $script:UseAnalysisResult = $false
}
$baselineFile = Join-Path $PSScriptRoot ".script-baseline.json"

function Test-ScriptSecurity {
    <#
    .SYNOPSIS
        Checks for security issues with optional AST analysis
    #>
    param([string]$FilePath, [string]$Content)
    
    $issues = @()
    
    try {
        # Use AstAnalyzer if available for better accuracy
        if ($script:UseAstAnalyzer) {
            try {
                $analyzer = [AstAnalyzer]::new($Content, $FilePath)
                
                # Check execution policy bypass with AST
                $bypassCommands = $analyzer.FindExecutionPolicyBypass()
                if ($bypassCommands.Count -gt 0) {
                    foreach ($cmd in $bypassCommands) {
                        $issues += [PSCustomObject]@{
                            File = $FilePath
                            Severity = 'CRITICAL'
                            Category = 'Security'
                            Issue = 'Execution Policy Bypass'
                            Line = $cmd.StartLineNumber
                            Description = 'Script sets execution policy to Bypass - security risk'
                            Recommendation = 'Remove Set-ExecutionPolicy command. Users should set their own policy.'
                            AutoFix = $true
                        }
                    }
                }
                
                # Check for hardcoded credentials with AST
                $credCommands = $analyzer.FindCredentialAssignments()
                if ($credCommands.Count -gt 0) {
                    foreach ($cred in $credCommands) {
                        $issues += [PSCustomObject]@{
                            File = $FilePath
                            Severity = 'HIGH'
                            Category = 'Security'
                            Issue = 'Plain Text Password'
                            Line = $cred.StartLineNumber
                            Description = 'Password stored in plain text'
                            Recommendation = 'Use Get-Credential or secure string'
                            AutoFix = $false
                        }
                    }
                }
                
                return $issues
            } catch {
                Write-Verbose "AST analysis failed for $FilePath, falling back to regex: $_"
                # Fall through to regex-based checks
            }
        }
        
        # Fallback regex-based checks
        # Check for execution policy bypass (real code lines only)
        if ([System.Text.RegularExpressions.Regex]::IsMatch($Content, '^[\t ]*Set-ExecutionPolicy\b.*Bypass', [System.Text.RegularExpressions.RegexOptions]::Multiline)) {
            $issues += [PSCustomObject]@{
                File = $FilePath
                Severity = 'CRITICAL'
                Category = 'Security'
                Issue = 'Execution Policy Bypass'
                Line = ($Content -split "`n" | Select-String -Pattern '^[\t ]*Set-ExecutionPolicy\b.*Bypass' -SimpleMatch).LineNumber
                Description = 'Script sets execution policy to Bypass - security risk'
                Recommendation = 'Remove Set-ExecutionPolicy command. Users should set their own policy.'
                AutoFix = $true
            }
        }
        
        # Check for plain text passwords
        if ($Content -match '\$password\s*=\s*[''"].*[''"]') {
            $issues += [PSCustomObject]@{
                File = $FilePath
                Severity = 'HIGH'
                Category = 'Security'
                Issue = 'Plain Text Password'
                Description = 'Password stored in plain text'
                Recommendation = 'Use Get-Credential or secure string'
                AutoFix = $false
            }
        }
    } catch {
        Write-Warning "Error in Test-ScriptSecurity for ${FilePath}: $($_.Exception.Message)"
    }
    
    return $issues
}

function Test-PathHandling {
    <#
    .SYNOPSIS
        Checks for hard-coded paths
    #>
    param([string]$FilePath, [string]$Content)
    
    $issues = @()
    
    # Check for hard-coded C:\ paths
    if ($Content -match '[''"]C:\\[^''">]+[''"]') {
        $pathMatches = [regex]::Matches($Content, '[\'']C:\\[^\''">]+[\'']')
        foreach ($match in $pathMatches) {
            $issues += [PSCustomObject]@{
                File = $FilePath
                Severity = 'MEDIUM'
                Category = 'Portability'
                Issue = 'Hard-coded Path'
                Value = $match.Value
                Description = "Hard-coded path: $($match.Value)"
                Recommendation = 'Use parameters with $env:SystemDrive or Join-Path'
                AutoFix = $false
            }
        }
    }
    
    return $issues
}

function Test-ErrorHandling {
    <#
    .SYNOPSIS
        Checks error handling patterns
    #>
    param([string]$FilePath, [string]$Content)
    
    $issues = @()
    
    # Check for -ErrorAction SilentlyContinue without try/catch (real code lines only)
    if ([System.Text.RegularExpressions.Regex]::IsMatch($Content, '^[\t ]*(?!#).*?-ErrorAction\s+SilentlyContinue', [System.Text.RegularExpressions.RegexOptions]::Multiline) -and $Content -notmatch 'try\s*{') {
        $issues += [PSCustomObject]@{
            File = $FilePath
            Severity = 'MEDIUM'
            Category = 'Error Handling'
            Issue = 'Silent Error Suppression'
            Description = 'Errors silently suppressed without try/catch'
            Recommendation = 'Use try/catch with -ErrorAction Stop for explicit error handling'
            AutoFix = $false
        }
    }
    
    return $issues
}

function Test-AdminPrivileges {
    <#
    .SYNOPSIS
        Checks admin privilege handling
    #>
    param([string]$FilePath, [string]$Content)
    
    $issues = @()
    
    # Check for old-style admin check
    if ($Content -match '\[Security\.Principal\.WindowsIdentity\]' -and 
        $Content -notmatch '#Requires -RunAsAdministrator') {
        $issues += [PSCustomObject]@{
            File = $FilePath
            Severity = 'LOW'
            Category = 'Code Quality'
            Issue = 'Manual Admin Check'
            Description = 'Uses manual admin check instead of #Requires'
            Recommendation = 'Add #Requires -RunAsAdministrator or use Test-AdministratorPrivilege'
            AutoFix = $true
        }
    }
    
    return $issues
}

function Test-CommonFunctionsUsage {
    <#
    .SYNOPSIS
        Checks if script uses CommonFunctions module
    #>
    param([string]$FilePath, [string]$Content)
    
    $issues = @()
    
    if ($Content -notmatch 'Import-Module.*CommonFunctions') {
        # Check if it has custom logging function
        if ($Content -match 'function Write-Log') {
            $issues += [PSCustomObject]@{
                File = $FilePath
                Severity = 'LOW'
                Category = 'Code Duplication'
                Issue = 'Custom Write-Log Function'
                Description = 'Script has its own Write-Log function'
                Recommendation = 'Use CommonFunctions module Write-StandardLog instead'
                AutoFix = $false
            }
        }
    }
    
    return $issues
}

function Get-ScriptBaseline {
    <#
    .SYNOPSIS
        Loads baseline of previously analyzed scripts
    #>
    if (Test-Path $baselineFile) {
        try {
            [PSCustomObject]$baseline = Get-Content $baselineFile | ConvertFrom-Json
            return $baseline
        }
        catch {
            Write-Host "Warning: Could not read baseline file: $_" -ForegroundColor Yellow
            return @{Scripts = @(); LastUpdate = $null}
        }
    }
    return @{Scripts = @(); LastUpdate = $null}
}

function Save-ScriptBaseline {
    <#
    .SYNOPSIS
        Saves current script inventory as baseline
    #>
    param([array]$ScriptFiles)
    
    $baseline = @{
        Scripts = $ScriptFiles | ForEach-Object { @{Name = $_.Name; Path = $_.FullName; Hash = (Get-FileHash $_.FullName -Algorithm MD5).Hash}}
        LastUpdate = Get-Date
    }
    
    $baseline | ConvertTo-Json | Set-Content $baselineFile
    Write-Host "Baseline saved: $baselineFile" -ForegroundColor Green
    Write-Host "Tracked scripts: $($baseline.Scripts.Count)" -ForegroundColor Cyan
}

function Get-NewScripts {
    <#
    .SYNOPSIS
        Compares current scripts against baseline
    #>
    param([array]$CurrentScripts, [array]$BaselineScripts)
    
    $baselineNames = @($BaselineScripts | ForEach-Object {$_.Name})
    $newScripts = $CurrentScripts | Where-Object { $_.Name -notin $baselineNames }
    
    return $newScripts
}

function Invoke-ContinuousAnalysis {
    <#
    .SYNOPSIS
        Watches directory and analyzes new scripts
    #>
    Write-Host "Starting continuous analysis (interval: $Interval seconds)..." -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Yellow
    
    $baselineData = Get-ScriptBaseline
    
    while ($true) {
        $scripts = Get-ChildItem $ScriptPath -Filter "*.ps1" -Recurse | Where-Object { $_.Name -ne "Update-Scripts.ps1" }
        $newScripts = Get-NewScripts $scripts $baselineData.Scripts
        
        if ($newScripts.Count -gt 0) {
            Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Found $($newScripts.Count) new script(s):" -ForegroundColor Yellow
            
            foreach ($script in $newScripts) {
                Write-Host "  + $($script.Name)" -ForegroundColor Green
                
                $content = Get-Content $script.FullName -Raw
                $scriptIssues = @()
                
                # Run all tests
                $scriptIssues += Test-ScriptSecurity -FilePath $script.FullName -Content $content
                $scriptIssues += Test-PathHandling -FilePath $script.FullName -Content $content
                $scriptIssues += Test-ErrorHandling -FilePath $script.FullName -Content $content
                $scriptIssues += Test-AdminPrivileges -FilePath $script.FullName -Content $content
                $scriptIssues += Test-CommonFunctionsUsage -FilePath $script.FullName -Content $content
                $scriptIssues += Test-Documentation -FilePath $script.FullName -Content $content
                
                if ($scriptIssues.Count -gt 0) {
                    Write-Host "    Issues found: $($scriptIssues.Count)" -ForegroundColor Red
                    foreach ($issue in $scriptIssues | Sort-Object Severity) {
                        Write-Host "      [$($issue.Severity)] $($issue.Issue)" -ForegroundColor $(
                            switch ($issue.Severity) {
                                'CRITICAL' { 'Red' }
                                'HIGH' { 'DarkRed' }
                                'MEDIUM' { 'Yellow' }
                                default { 'Green' }
                            }
                        )
                    }
                } else {
                    Write-Host "    No issues found!" -ForegroundColor Green
                }
                
                $script:Issues += $scriptIssues
            }
            
            # Update baseline
            $baseline = @{Scripts = @(); LastUpdate = (Get-Date)}
            $baseline.Scripts = $scripts | ForEach-Object { @{Name = $_.Name; Path = $_.FullName; Hash = (Get-FileHash $_.FullName -Algorithm MD5).Hash}}
            $baseline | ConvertTo-Json | Set-Content $baselineFile
        }
        
        Start-Sleep -Seconds $Interval
    }
}

function Test-Documentation {
    <#
    .SYNOPSIS
        Checks script documentation
    #>
    param([string]$FilePath, [string]$Content)
    
    $issues = @()
    
    if ($Content -notmatch '<#[\s\S]*?\.SYNOPSIS[\s\S]*?#>') {
        $issues += [PSCustomObject]@{
            File = $FilePath
            Severity = 'LOW'
            Category = 'Documentation'
            Issue = 'Missing Help'
            Description = 'Script lacks comment-based help'
            Recommendation = 'Add .SYNOPSIS, .DESCRIPTION, and .EXAMPLE sections'
            AutoFix = $false
        }
    }
    
    return $issues
}

function Invoke-AutoFix {
    <#
    .SYNOPSIS
        Applies automatic fixes to script
    #>
    param([string]$FilePath, [array]$Issues)
    
    $content = Get-Content $FilePath -Raw
    $modified = $false
    
    foreach ($issue in $Issues | Where-Object { $_.AutoFix }) {
        switch ($issue.Issue) {
            'Execution Policy Bypass' {
                Write-Host "  Fixing: Removing execution policy bypass..." -ForegroundColor Yellow
                $content = $content -replace 'Set-ExecutionPolicy[^\n]+\n', "# Removed dangerous execution policy bypass`n"
                $modified = $true
            }
            'Manual Admin Check' {
                Write-Host "  Fixing: Adding #Requires statement..." -ForegroundColor Yellow
                if ($content -notmatch '^#Requires') {
                    $content = "#Requires -RunAsAdministrator`n#Requires -Version 5.1`n`n" + $content
                    $modified = $true
                }
            }
        }
    }
    
    if ($modified) {
        # Create backup
        $backupPath = "$FilePath.backup"
        Copy-Item $FilePath $backupPath -Force
        Write-Host "  Backup created: $backupPath" -ForegroundColor Cyan
        
        # Write fixed content
        Set-Content $FilePath $content -NoNewline
        Write-Host "  Fixed: $FilePath" -ForegroundColor Green
    }
}

function New-IssueReport {
    <#
    .SYNOPSIS
        Generates HTML report
    #>
    param([array]$AllIssues)
    
    # Create Reports folder if it doesn't exist
    $reportsFolder = Join-Path $PSScriptRoot "Reports"
    if (-not (Test-Path $reportsFolder)) {
        New-Item -ItemType Directory -Path $reportsFolder -Force | Out-Null
    }
    
    $reportPath = Join-Path $reportsFolder "ScriptAnalysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Script Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .summary { background: #f0f0f0; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .issue { margin: 10px 0; padding: 10px; border-left: 4px solid #ddd; }
        .critical { border-color: #d32f2f; background: #ffebee; }
        .high { border-color: #f57c00; background: #fff3e0; }
        .medium { border-color: #fbc02d; background: #fffde7; }
        .low { border-color: #388e3c; background: #e8f5e9; }
        .file { font-weight: bold; color: #1976d2; }
        .category { color: #666; font-size: 0.9em; }
        .recommendation { margin-top: 5px; padding: 5px; background: #f5f5f5; }
    </style>
</head>
<body>
    <h1>Script Analysis Report</h1>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Issues:</strong> $($AllIssues.Count)</p>
        <p><strong>Critical:</strong> $(($AllIssues | Where-Object Severity -eq 'CRITICAL').Count)</p>
        <p><strong>High:</strong> $(($AllIssues | Where-Object Severity -eq 'HIGH').Count)</p>
        <p><strong>Medium:</strong> $(($AllIssues | Where-Object Severity -eq 'MEDIUM').Count)</p>
        <p><strong>Low:</strong> $(($AllIssues | Where-Object Severity -eq 'LOW').Count)</p>
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    </div>
    <h2>Issues</h2>
"@
    
    foreach ($issue in $AllIssues | Sort-Object Severity, File) {
        # Validate severity is one of allowed values (whitelist)
        $validSeverities = @('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')
        $severity = $issue.Severity
        if ($severity -notin $validSeverities) {
            Write-Warning "Invalid severity '$severity', using 'MEDIUM'"
            $severity = 'MEDIUM'
        }
        $severityClass = $severity.ToLower()
        
        # HTML-encode all user-provided content to prevent XSS
        $encodedFile = [System.Web.HttpUtility]::HtmlEncode($issue.File)
        $encodedIssue = [System.Web.HttpUtility]::HtmlEncode($issue.Issue)
        $encodedCategory = [System.Web.HttpUtility]::HtmlEncode($issue.Category)
        $encodedDescription = [System.Web.HttpUtility]::HtmlEncode($issue.Description)
        $encodedRecommendation = [System.Web.HttpUtility]::HtmlEncode($issue.Recommendation)
        
        $html += @"
    <div class="issue $severityClass">
        <div class="file">$encodedFile</div>
        <div><strong>[$($issue.Severity)] $encodedIssue</strong> <span class="category">($encodedCategory)</span></div>
        <div>$encodedDescription</div>
        <div class="recommendation"><strong>Recommendation:</strong> $encodedRecommendation</div>
        $(if ($issue.AutoFix) { "<div><em>[Auto-fix available]</em></div>" })
    </div>
"@
    }
    
    $html += @"
</body>
</html>
"@
    
    $html | Out-File $reportPath -Encoding UTF8
    Write-Host "`nReport generated: $reportPath" -ForegroundColor Green
    Start-Process $reportPath
}

# Main execution
Write-Host "Analyzing PowerShell scripts..." -ForegroundColor Cyan
Write-Host "Path: $ScriptPath`n" -ForegroundColor Cyan

# Handle baseline operations
if ($Baseline) {
    Write-Host "Creating baseline of existing scripts..." -ForegroundColor Cyan
    $scripts = Get-ChildItem $ScriptPath -Filter "*.ps1" -Recurse | Where-Object { $_.Name -ne "Update-Scripts.ps1" }
    Save-ScriptBaseline $scripts
    exit 0
}

if ($Watch) {
    Invoke-ContinuousAnalysis
    exit 0
}

# Get script files
if (Test-Path $ScriptPath -PathType Container) {
    $scripts = Get-ChildItem $ScriptPath -Filter "*.ps1" -Recurse | Where-Object { $_.Name -ne "Update-Scripts.ps1" }
} else {
    $scripts = @(Get-Item $ScriptPath)
}

# Filter to only new scripts if requested
if ($CheckNew) {
    $baselineData = Get-ScriptBaseline
    $scripts = Get-NewScripts $scripts $baselineData.Scripts
    if ($scripts.Count -eq 0) {
        Write-Host "No new scripts found since last baseline." -ForegroundColor Green
        exit 0
    }
}

Write-Host "Found $($scripts.Count) script(s) to analyze`n" -ForegroundColor White

if ($Parallel -and $PSVersionTable.PSVersion.Major -ge 7 -and $scripts.Count -gt 3) {
    Write-Host "Using parallel processing..." -ForegroundColor Cyan
    
    $allIssues = $scripts | ForEach-Object -Parallel {
        $script = $_
        $scriptPath = $using:PSScriptRoot
        
        # Import required functions in parallel context
        . "$scriptPath\CommonFunctions.psm1"
        
        $content = Get-Content $script.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { return @() }
        
        $scriptIssues = @()
        
        # Run all tests (simplified for parallel execution)
        try {
            # Basic security checks
            if ($content -match 'Set-ExecutionPolicy.*Bypass') {
                $scriptIssues += [PSCustomObject]@{
                    File = $script.FullName
                    Severity = 'CRITICAL'
                    Category = 'Security'
                    Issue = 'Execution Policy Bypass'
                    Description = 'Script sets execution policy to Bypass'
                }
            }
            
            if ($content -match '\$password\s*=\s*[\''"]') {
                $scriptIssues += [PSCustomObject]@{
                    File = $script.FullName
                    Severity = 'HIGH'
                    Category = 'Security'
                    Issue = 'Plain Text Password'
                    Description = 'Password stored in plain text'
                }
            }
            
            # Path handling
            if ($content -match 'C:\\\\|D:\\\\') {
                $scriptIssues += [PSCustomObject]@{
                    File = $script.FullName
                    Severity = 'MEDIUM'
                    Category = 'Portability'
                    Issue = 'Hard-coded Path'
                    Description = 'Script contains hard-coded drive paths'
                }
            }
            
            # Error handling
            if ($content -match '-ErrorAction\s+SilentlyContinue') {
                $scriptIssues += [PSCustomObject]@{
                    File = $script.FullName
                    Severity = 'MEDIUM'
                    Category = 'ErrorHandling'
                    Issue = 'Silent Error Suppression'
                    Description = 'Errors are being silently suppressed'
                }
            }
        } catch {
            Write-Warning "Error analyzing $($script.Name): $_"
        }
        
        return $scriptIssues
    } -ThrottleLimit 4
    
    $script:Issues = @($allIssues | Where-Object { $_ })
    
    Write-Host "`nParallel analysis complete" -ForegroundColor Green
} else {
    # Sequential processing
    if ($Parallel -and $PSVersionTable.PSVersion.Major -lt 7) {
        Write-Warning "Parallel processing requires PowerShell 7+. Using sequential processing."
    }
    
    foreach ($script in $scripts) {
        Write-Host "Analyzing: $($script.Name)" -ForegroundColor Yellow
        
        try {
            $content = Get-Content $script.FullName -Raw -ErrorAction Stop
        } catch {
            Write-Warning "Failed to read $($script.Name): $_"
            continue
        }
        
        $scriptIssues = @()
        
        # Run all tests with error handling
        try {
            $scriptIssues += Test-ScriptSecurity -FilePath $script.FullName -Content $content
            $scriptIssues += Test-PathHandling -FilePath $script.FullName -Content $content
            $scriptIssues += Test-ErrorHandling -FilePath $script.FullName -Content $content
            $scriptIssues += Test-AdminPrivileges -FilePath $script.FullName -Content $content
            $scriptIssues += Test-CommonFunctionsUsage -FilePath $script.FullName -Content $content
            $scriptIssues += Test-Documentation -FilePath $script.FullName -Content $content
        } catch {
            Write-Warning "Error during analysis of $($script.Name): $_"
        }
        
        if ($scriptIssues.Count -gt 0) {
            Write-Host "  Found $($scriptIssues.Count) issue(s):" -ForegroundColor Red
            foreach ($issue in $scriptIssues) {
                Write-Host "    [$($issue.Severity)] $($issue.Issue)" -ForegroundColor $(
                    switch ($issue.Severity) {
                        'CRITICAL' { 'Red' }
                        'HIGH' { 'DarkRed' }
                        'MEDIUM' { 'Yellow' }
                        default { 'Gray' }
                    }
                )
            }
            
            if ($Fix) {
                Invoke-AutoFix -FilePath $script.FullName -Issues $scriptIssues
            }
            
            $script:Issues += $scriptIssues
        } else {
            Write-Host "  [OK] No issues found" -ForegroundColor Green
        }
        
        Write-Host ""
    }
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Total scripts analyzed: $($scripts.Count)" -ForegroundColor White
Write-Host "Total issues found: $($script:Issues.Count)" -ForegroundColor White

if ($script:Issues.Count -gt 0) {
    $grouped = $script:Issues | Group-Object Severity
    foreach ($group in $grouped) {
        Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor $(
            switch ($group.Name) {
                'CRITICAL' { 'Red' }
                'HIGH' { 'DarkRed' }
                'MEDIUM' { 'Yellow' }
                default { 'Gray' }
            }
        )
    }
    
    if ($Report) {
        New-IssueReport -AllIssues $script:Issues
    }
    
    if (-not $Fix) {
        Write-Host "`nTip: Run with -Fix to automatically apply safe fixes" -ForegroundColor Cyan
        Write-Host "Tip: Run with -Report to generate detailed HTML report" -ForegroundColor Cyan
    }
} else {
    Write-Host "All scripts look good!" -ForegroundColor Green
}
