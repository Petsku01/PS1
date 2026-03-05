<#
.SYNOPSIS
    Tests the new automation features of Update-Scripts.ps1

.DESCRIPTION
    This script demonstrates:
    1. Creating a baseline
    2. Detecting new scripts
    3. Running continuous analysis (briefly)
#>

param(
    [ValidateSet('test-checknew', 'test-watch', 'full-demo')]
    [string]$TestMode = 'full-demo'
)

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

$ScriptPath = $PSScriptRoot

Write-Console "=== PowerShell Script Automation Test ===" -ForegroundColor Cyan
Write-Console "Test Mode: $TestMode`n" -ForegroundColor Yellow

switch ($TestMode) {
    'test-checknew' {
        Write-Console "1. Creating a new test script..." -ForegroundColor Green
        @"
<#
.SYNOPSIS
    Test automation script
.DESCRIPTION
    This is a test script for automation
#>
Write-Console 'Test'
"@ | Out-File -FilePath "$ScriptPath\AutomationTest_New.ps1" -Encoding UTF8
        
        Write-Console "2. Running CheckNew to detect it..." -ForegroundColor Green
        & "$ScriptPath\Update-Scripts.ps1" -ScriptPath $ScriptPath -CheckNew
        
        Write-Console "`n3. Cleaning up..." -ForegroundColor Green
        Remove-Item "$ScriptPath\AutomationTest_New.ps1" -Force
        
        Write-Console " CheckNew test completed!" -ForegroundColor Green
    }
    
    'test-watch' {
        Write-Console "1. Starting Watch mode (5 second interval)..." -ForegroundColor Green
        Write-Console "   Press Ctrl+C to stop after 10 seconds`n" -ForegroundColor Yellow
        
        $watchJob = Start-Job -ScriptBlock {
            Set-Location $args[0]
            & ".\Update-Scripts.ps1" -ScriptPath . -Watch -Interval 5
        } -ArgumentList $ScriptPath
        
        Start-Sleep -Seconds 3
        
        Write-Console "2. Creating new test script..." -ForegroundColor Green
        @"
<#
.SYNOPSIS
    Watch mode test script
#>
Write-Console 'Watch Test'
"@ | Out-File -FilePath "$ScriptPath\AutomationTest_Watch.ps1" -Encoding UTF8
        
        Write-Console "3. Waiting for Watch to detect it (10 seconds)..." -ForegroundColor Green
        Start-Sleep -Seconds 10
        
        Write-Console "4. Stopping Watch..." -ForegroundColor Green
        Stop-Job -Job $watchJob -ErrorAction SilentlyContinue | Out-Null
        Get-Job | Remove-Job -ErrorAction SilentlyContinue | Out-Null
        
        Remove-Item "$ScriptPath\AutomationTest_Watch.ps1" -Force -ErrorAction SilentlyContinue
        
        Write-Console " Watch test completed!" -ForegroundColor Green
    }
    
    'full-demo' {
        Write-Console "Phase 1: Creating baseline of existing scripts" -ForegroundColor Cyan
        & "$ScriptPath\Update-Scripts.ps1" -ScriptPath $ScriptPath -Baseline
        
        Write-Console "`nPhase 2: Verifying no new scripts (CheckNew)" -ForegroundColor Cyan
        & "$ScriptPath\Update-Scripts.ps1" -ScriptPath $ScriptPath -CheckNew
        
        Write-Console "`nPhase 3: Adding a new test script" -ForegroundColor Cyan
        @"
<#
.SYNOPSIS
    Demo automation test script
.DESCRIPTION
    This demonstrates the new automation features
#>
Write-Console 'Demo Complete'
"@ | Out-File -FilePath "$ScriptPath\AutomationTest_Demo.ps1" -Encoding UTF8
        
        Write-Console "`nPhase 4: CheckNew detects the new script" -ForegroundColor Cyan
        & "$ScriptPath\Update-Scripts.ps1" -ScriptPath $ScriptPath -CheckNew
        
        Write-Console "`nPhase 5: Full analysis with report" -ForegroundColor Cyan
        & "$ScriptPath\Update-Scripts.ps1" -ScriptPath $ScriptPath -Report | Where-Object { $_ -match 'Summary|Total|Tip' }
        
        Write-Console "`nPhase 6: Cleaning up test script" -ForegroundColor Cyan
        Remove-Item "$ScriptPath\AutomationTest_Demo.ps1" -Force
        
        Write-Console "`n Full automation demo completed!" -ForegroundColor Green
        Write-Console "`nFeatures tested:" -ForegroundColor Cyan
        Write-Console "   Baseline creation (-Baseline)" -ForegroundColor Green
        Write-Console "   New script detection (-CheckNew)" -ForegroundColor Green
        Write-Console "   Analysis reporting (-Report)" -ForegroundColor Green
        Write-Console "   Watch mode ready (-Watch)" -ForegroundColor Green
    }
}

Write-Console ""


