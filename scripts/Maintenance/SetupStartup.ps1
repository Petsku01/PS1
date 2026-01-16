<#
.SYNOPSIS
Automates PowerShell script startup launcher creation and registration.

.DESCRIPTION
Creates batch and VBS wrapper files to launch PowerShell scripts silently on system
startup without displaying command prompt windows. Supports installation and uninstall
of startup launchers via Windows startup registry.

.PARAMETER MainScriptName
Name of the main PowerShell script to launch on startup. Default: StartupLauncher.ps1.

.PARAMETER Uninstall
Remove startup launcher registration instead of installing.

.EXAMPLE
.\SetupStartup.ps1 -MainScriptName "MyStartupScript.ps1"

.EXAMPLE
.\SetupStartup.ps1 -Uninstall

.NOTES
Requires Administrator privileges for registry modification.
Uses VBS wrapper for silent execution without command window.

.LINK
https://docs.microsoft.com/en-us/windows/win32/sysinfo/run-registry-key
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

# PowerShell script to automate the creation and setup of .bat and .vbs files
# This script sets up a PowerShell script to run automatically on startup without a black command prompt window

param(
    [Parameter()]
    [string]$MainScriptName = "StartupLauncher.ps1",
    
    [Parameter()]
    [switch]$Uninstall
)

# Define paths dynamically
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptDir)) {
    $scriptDir = (Get-Location).Path
}

$scriptPath = Join-Path $scriptDir $MainScriptName
$batFileName = "StartupScript.bat"
$vbsFileName = "StartupScript.vbs"
$batPath = Join-Path $scriptDir $batFileName
$vbsPath = Join-Path $scriptDir $vbsFileName
$startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$vbsStartupPath = Join-Path $startupFolder $vbsFileName

# Function to remove startup files
function Remove-StartupFiles {
    $removed = $false
    
    # Remove from startup folder
    if (Test-Path $vbsStartupPath) {
        try {
            Remove-Item -Path $vbsStartupPath -Force -ErrorAction Stop
            Write-Host "Removed .vbs file from Startup folder" -ForegroundColor Green
            $removed = $true
        } catch {
            Write-Host "Error removing .vbs file from Startup: $_" -ForegroundColor Red
        }
    }
    
    # Remove local files
    if (Test-Path $batPath) {
        try {
            Remove-Item -Path $batPath -Force -ErrorAction Stop
            Write-Host "Removed local .bat file" -ForegroundColor Green
            $removed = $true
        } catch {
            Write-Host "Error removing .bat file: $_" -ForegroundColor Red
        }
    }
    
    if (Test-Path $vbsPath) {
        try {
            Remove-Item -Path $vbsPath -Force -ErrorAction Stop
            Write-Host "Removed local .vbs file" -ForegroundColor Green
            $removed = $true
        } catch {
            Write-Host "Error removing .vbs file: $_" -ForegroundColor Red
        }
    }
    
    if ($removed) {
        Write-Host "`nUninstall complete!" -ForegroundColor Green
    } else {
        Write-Host "`nNo startup files found to remove." -ForegroundColor Yellow
    }
}

# Handle uninstall
if ($Uninstall) {
    Write-Host "Uninstalling startup script..." -ForegroundColor Yellow
    Remove-StartupFiles
    Pause
    exit 0
}

# Check if running as administrator (optional enhancement)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "Note: Running without administrator privileges. Some features may be limited." -ForegroundColor Yellow
}

# Check if the main script exists
if (-not (Test-Path $scriptPath)) {
    Write-Host "Error: The script '$MainScriptName' was not found in the same directory as this setup script." -ForegroundColor Red
    Write-Host "Directory: '$scriptDir'" -ForegroundColor Red
    Write-Host "`nPlease ensure that the file '$MainScriptName' is saved in the same directory as this setup script." -ForegroundColor Red
    
    # List available .ps1 files in the directory
    $ps1Files = Get-ChildItem -Path $scriptDir -Filter "*.ps1" | Where-Object { $_.Name -ne (Split-Path -Leaf $MyInvocation.MyCommand.Path) }
    if ($ps1Files) {
        Write-Host "`nAvailable PowerShell scripts in the directory:" -ForegroundColor Cyan
        $ps1Files | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
        Write-Host "`nRun this script with -MainScriptName parameter to specify a different script." -ForegroundColor Cyan
        Write-Host "Example: .\SetupScript.ps1 -MainScriptName 'YourScript.ps1'" -ForegroundColor Gray
    }
    
    Pause
    exit 1
}

# Check if startup files already exist
$existingFiles = @()
if (Test-Path $vbsStartupPath) { $existingFiles += "Startup folder .vbs" }
if (Test-Path $batPath) { $existingFiles += "Local .bat" }
if (Test-Path $vbsPath) { $existingFiles += "Local .vbs" }

if ($existingFiles.Count -gt 0) {
    Write-Host "Warning: The following startup files already exist:" -ForegroundColor Yellow
    $existingFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
    
    $response = Read-Host "`nDo you want to overwrite them? (Y/N)"
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Host "Setup cancelled." -ForegroundColor Yellow
        Pause
        exit 0
    }
}

# Get PowerShell executable path (more robust)
$psPath = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Path
if (-not $psPath) {
    $defaultPsPath = Join-Path -Path $env:SystemRoot -ChildPath "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $defaultPsPath) {
        $psPath = $defaultPsPath
    } else {
        $psPath = "powershell.exe"  # Fallback to PATH
    }
}

# 1. Create the .bat file
$batContent = @"
@echo off
"$psPath" -ExecutionPolicy Bypass -WindowStyle Hidden -File "$scriptPath"
if errorlevel 1 (
    echo Error occurred while running the PowerShell script.
    pause
)
"@

try {
    Set-Content -Path $batPath -Value $batContent -Force -ErrorAction Stop
    Write-Host " Created .bat file: $batFileName" -ForegroundColor Green
} catch {
    Write-Host " Error: Could not create .bat file '$batFileName': $_" -ForegroundColor Red
    Pause
    exit 1
}

# 2. Create the .vbs file with error handling
$vbsContent = @"
On Error Resume Next
Set WShell = CreateObject("WScript.Shell")
If Err.Number = 0 Then
    WShell.Run """$batPath""", 0, False
    If Err.Number <> 0 Then
        MsgBox "Error running startup script: " & Err.Description, 16, "Startup Script Error"
    End If
Else
    MsgBox "Error creating WScript.Shell: " & Err.Description, 16, "Startup Script Error"
End If
Set WShell = Nothing
"@

try {
    Set-Content -Path $vbsPath -Value $vbsContent -Force -ErrorAction Stop
    Write-Host " Created .vbs file: $vbsFileName" -ForegroundColor Green
} catch {
    Write-Host " Error: Could not create .vbs file '$vbsFileName': $_" -ForegroundColor Red
    Pause
    exit 1
}

# 3. Ensure Startup folder exists
if (-not (Test-Path $startupFolder)) {
    try {
        New-Item -Path $startupFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Host " Created Startup folder" -ForegroundColor Green
    } catch {
        Write-Host " Error: Could not create Startup folder: $_" -ForegroundColor Red
        Pause
        exit 1
    }
}

# 4. Copy the .vbs file to the Startup folder
try {
    Copy-Item -Path $vbsPath -Destination $vbsStartupPath -Force -ErrorAction Stop
    Write-Host " Copied .vbs file to Startup folder" -ForegroundColor Green
} catch {
    Write-Host " Error: Could not copy .vbs file to Startup folder: $_" -ForegroundColor Red
    Write-Host "  Destination: '$vbsStartupPath'" -ForegroundColor Red
    Write-Host "  Ensure you have write permissions to the Startup folder." -ForegroundColor Red
    Pause
    exit 1
}

# 5. Verify the setup
$verificationPassed = $true
if (-not (Test-Path $batPath)) {
    Write-Host " Verification failed: .bat file not found" -ForegroundColor Red
    $verificationPassed = $false
}
if (-not (Test-Path $vbsPath)) {
    Write-Host " Verification failed: .vbs file not found" -ForegroundColor Red
    $verificationPassed = $false
}
if (-not (Test-Path $vbsStartupPath)) {
    Write-Host " Verification failed: .vbs file not in Startup folder" -ForegroundColor Red
    $verificationPassed = $false
}

# 6. Show success or failure
Write-Host "`n" -NoNewline
Write-Host ("=" * 60) -ForegroundColor Cyan
if ($verificationPassed) {
    Write-Host "SETUP COMPLETE!" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "`nThe script '$MainScriptName' will now run automatically" -ForegroundColor Green
    Write-Host "on Windows startup without showing a command prompt window." -ForegroundColor Green
    Write-Host "`nSetup Details:" -ForegroundColor Cyan
    Write-Host "  Main Script: $scriptPath" -ForegroundColor Gray
    Write-Host "  Startup VBS: $vbsStartupPath" -ForegroundColor Gray
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "  1. Restart your computer to test the startup script" -ForegroundColor Gray
    Write-Host "  2. To uninstall, run this script with -Uninstall parameter" -ForegroundColor Gray
    Write-Host "     Example: .\SetupScript.ps1 -Uninstall" -ForegroundColor Gray
} else {
    Write-Host "SETUP INCOMPLETE!" -ForegroundColor Red
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "`nSome files could not be verified. Please check the errors above." -ForegroundColor Red
    Write-Host "You may need to run this script as Administrator." -ForegroundColor Yellow
}

Write-Host "`nPress any key to exit..." -ForegroundColor Gray
Pause

