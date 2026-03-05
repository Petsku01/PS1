<#
.SYNOPSIS
Cleans temporary files from system and user Temp directories.

.DESCRIPTION
Safely removes temporary files and directories from both system Temp folder
and user-specific Temp locations. Provides feedback on cleaned items and
gracefully handles locked files. Finnish language interface.

.PARAMETER None
This script does not accept parameters.

.EXAMPLE
.\Temp_delete.ps1

.NOTES
Requires Administrator privileges for full system Temp access.
Locked files are skipped with notification.
Performs recursive cleanup of all temp subdirectories.

.LINK
https://docs.microsoft.com/en-us/windows/win32/fileio/temp
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

# Vliaikaistiedostojen siivous
# Poistaa tiedostoja ja kansioita kyttjn Temp-kansiosta

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

Clear-Host
Write-Console "=== VLIAIKAISTIEDOSTOJEN SIIVOUS ===" -ForegroundColor Cyan
Write-Console ""

# Tarkista jrjestelmnvalvojan oikeudet
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Console "[OK] Jrjestelmnvalvojan oikeudet" -ForegroundColor Green
} else {
    Write-Console "[!] Rajoitetut oikeudet - kaikki tiedostot eivt vlttmtt poistu" -ForegroundColor Yellow
}

Write-Console "`nEtsitn Temp-kansioita..." -ForegroundColor Yellow

# Ker kaikki temp-kansiot
$tempPaths = @()

# Kyttjn temp-kansio
if ($env:TEMP) {
    $tempPaths += $env:TEMP
}
if ($env:TMP) {
    $tempPaths += $env:TMP
}
if ($env:LOCALAPPDATA) {
    $localTemp = Join-Path $env:LOCALAPPDATA "Temp"
    if (Test-Path $localTemp) {
        $tempPaths += $localTemp
    }
}

# Windows temp-kansio (vaatii admin-oikeudet)
$windowsTemp = "$env:SystemRoot\Temp"
if ($isAdmin -and (Test-Path $windowsTemp)) {
    $tempPaths += $windowsTemp
}

# Poista duplikaatit
$tempPaths = $tempPaths | Select-Object -Unique | Where-Object { Test-Path $_ }

if ($tempPaths.Count -eq 0) {
    Write-Console "`nVirhe: Temp-kansioita ei lytynyt!" -ForegroundColor Red
    Write-Console "Paina Enter poistuaksesi..."
    Read-Host
    exit 1
}

Write-Console "`nLydettiin $($tempPaths.Count) temp-kansio(ta):" -ForegroundColor Green
foreach ($path in $tempPaths) {
    Write-Console "  - $path" -ForegroundColor Cyan
}

# Laske tiedostojen mr ja koko
Write-Console "`nAnalysoidaan tiedostoja..." -ForegroundColor Yellow
$totalSize = 0
$totalCount = 0
$allItems = @()

foreach ($tempPath in $tempPaths) {
    try {
        $items = Get-ChildItem -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
        if ($items) {
            $allItems += $items
            $totalCount += $items.Count
            # Laske vain tiedostojen koko, ei kansioiden
            $files = $items | Where-Object { $_.GetType().Name -eq "FileInfo" }
            if ($files) {
                $totalSize += ($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            }
        }
    } catch {
        Write-Verbose "Could not enumerate items in folder: $($_.Exception.Message)"
    }
}

if ($totalCount -eq 0) {
    Write-Console "`nTemp-kansiot ovat jo tyhji!" -ForegroundColor Green
    Write-Console "Paina Enter poistuaksesi..."
    Read-Host
    exit 0
}

# Nyt yhteenveto
$sizeInMB = [math]::Round($totalSize / 1MB, 2)
Write-Console "`n=== YHTEENVETO ===" -ForegroundColor Cyan
Write-Console "Poistettavia kohteita: $totalCount" -ForegroundColor White
Write-Console "Vapautettava tila: $sizeInMB MB" -ForegroundColor White

# Kysy vahvistus
Write-Console "`nHaluatko jatkaa siivousta? (k/e)" -ForegroundColor Yellow
$confirm = Read-Host

if ($confirm -ne "k" -and $confirm -ne "K") {
    Write-Console "`nSiivous peruutettu." -ForegroundColor Yellow
    Write-Console "Paina Enter poistuaksesi..."
    Read-Host
    exit 0
}

# Suorita siivous
Write-Console "`nSiivotaan tiedostoja..." -ForegroundColor Green
$deletedCount = 0
$failedCount = 0
$freedSpace = 0
$failedItems = @()

foreach ($tempPath in $tempPaths) {
    Write-Console "`nSiivotaan: $tempPath" -ForegroundColor Cyan
    
    # Yrit poistaa tiedostot yksitellen
    $items = @()
    try {
        $items = Get-ChildItem -Path $tempPath -Force -ErrorAction SilentlyContinue
    } catch {
        continue  # Siirry seuraavaan kansioon jos tm ei toimi
    }
    
    foreach ($item in $items) {
        try {
            $itemSize = 0
            # Tarkista onko tiedosto vai kansio turvallisesti
            if ($item) {
                if ($item.GetType().Name -eq "FileInfo") {
                    $itemSize = $item.Length
                }
            }
            
            Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
            $deletedCount++
            $freedSpace += $itemSize
            
            # Nyt edistyminen suuremmissa siivouksissa
            if ($deletedCount % 100 -eq 0) {
                Write-Console "  Poistettu $deletedCount/$totalCount..." -ForegroundColor Gray
            }
        } catch {
            $failedCount++
            $failedItems += @{
                Path = $item.FullName
                Error = $_.Exception.Message
            }
        }
    }
}

# Nyt tulokset
Write-Console "`n=== SIIVOUS VALMIS ===" -ForegroundColor Cyan
Write-Console ""

if ($deletedCount -gt 0) {
    $freedSpaceMB = [math]::Round($freedSpace / 1MB, 2)
    Write-Console "Poistettu onnistuneesti:" -ForegroundColor Green
    Write-Console "  - Tiedostoja/kansioita: $deletedCount" -ForegroundColor White
    Write-Console "  - Vapautettu tilaa: $freedSpaceMB MB" -ForegroundColor White
}

if ($failedCount -gt 0) {
    Write-Console "`nEi voitu poistaa:" -ForegroundColor Red
    Write-Console "  - Lukittuja/suojattuja kohteita: $failedCount" -ForegroundColor Yellow
    
    if ($failedCount -le 10) {
        Write-Console "`nEponnistuneet kohteet:" -ForegroundColor Yellow
        foreach ($failed in $failedItems | Select-Object -First 10) {
            $fileName = Split-Path $failed.Path -Leaf
            Write-Console "  - $fileName" -ForegroundColor Gray
        }
    }
    
    Write-Console "`nVinkki: Sulje kaikki ohjelmat ja yrit uudelleen." -ForegroundColor Yellow
    if (-not $isAdmin) {
        Write-Console "Vinkki: Suorita jrjestelmnvalvojana poistaaksesi enemmn tiedostoja." -ForegroundColor Yellow
    }
}

# Yrit tyhjent mys Roskakorin sislt
Write-Console "`nHaluatko tyhjent mys Roskakorin? (k/e)" -ForegroundColor Cyan
$recycleConfirm = Read-Host

if ($recycleConfirm -eq "k" -or $recycleConfirm -eq "K") {
    try {
        Write-Console "Tyhjennetn Roskakori..." -ForegroundColor Yellow
        
        # Tarkista onko Clear-RecycleBin kytettviss (PowerShell 5.0+)
        if (Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue) {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Console "Roskakori tyhjennetty!" -ForegroundColor Green
        } else {
            # Kyt vanhempaa COM-menetelm
            $shell = New-Object -ComObject Shell.Application
            $recycleBin = $shell.Namespace(0xA)
            $size = 0
            $recycleBin.Items() | ForEach-Object { $size++ }
            if ($size -gt 0) {
                $recycleBin.Items() | ForEach-Object { 
                    $_.InvokeVerb("delete")
                }
                Write-Console "Roskakori tyhjennetty!" -ForegroundColor Green
            } else {
                Write-Console "Roskakori on jo tyhj." -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Console "Roskakorin tyhjennys eponnistui: $_" -ForegroundColor Red
    }
}

# Nyt yhteenveto
Write-Console "`n================================" -ForegroundColor Cyan
if ($deletedCount -gt 0) {
    Write-Console "Siivous suoritettu onnistuneesti!" -ForegroundColor Green
    $successRate = [math]::Round(($deletedCount / $totalCount) * 100, 1)
    Write-Console "Onnistumisprosentti: $successRate%" -ForegroundColor White
} else {
    Write-Console "Ei tiedostoja poistettavaksi." -ForegroundColor Yellow
}

Write-Console "`nPaina Enter poistuaksesi..."
Read-Host


