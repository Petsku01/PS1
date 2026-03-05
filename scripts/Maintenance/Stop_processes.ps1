<#
.SYNOPSIS
Interactive process listing and termination utility (Finnish).

.DESCRIPTION
Displays a formatted list of running processes with CPU and memory usage.
Allows safe termination of selected processes with confirmation. Excludes
system critical processes.

.PARAMETER None
This script does not accept parameters.

.EXAMPLE
.\Stop_processes.ps1
(Then select process number to terminate)

.NOTES
Filters out Idle and System processes for safety.
Requires confirmation before terminating.

.LINK
https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/stop-process
#>

#Requires -Version 5.1

# Prosessien hallinta
# PowerShell Process Manager - Simplified & Fixed

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
Write-Console "=== PROSESSIEN HALLINTA ===" -ForegroundColor Cyan
Write-Console "`nListataan kynniss olevat prosessit..." -ForegroundColor Yellow

# Nyt prosessit jrjestettyn nimen mukaan
$processes = Get-Process | Where-Object {$_.ProcessName -ne "Idle" -and $_.ProcessName -ne "System"} | 
    Sort-Object Name

# Nyt prosessit taulukossa
$processes | Format-Table -Property Name, Id, 
    @{Name="CPU(s)"; Expression={
        if($_.CPU) {
            [math]::Round($_.CPU, 2)
        } else {
            0
        }
    }}, 
    @{Name="WorkingSet(MB)"; Expression={
        [math]::Round($_.WorkingSet/1MB, 2)
    }} -AutoSize

Write-Console "Yhteens: $($processes.Count) prosessia" -ForegroundColor Green
Write-Console "`nVaroitus: Ole varovainen pysyttesssi prosesseja!" -ForegroundColor Red
Write-Console "Jrjestelmprosessien pysyttminen voi kaataa tietokoneen." -ForegroundColor Red

$prosessi = Read-Host "`nSyt prosessin nimi, jonka haluat pysytt (esim. notepad), tai paina Enter ohittaaksesi"

if ($prosessi -and $prosessi.Trim() -ne "") {
    $prosessi = $prosessi.Trim()
    
    # Tarkista onko prosessi olemassa
    $loytyneetProsessit = $null
    try {
        $loytyneetProsessit = @(Get-Process -Name $prosessi -ErrorAction SilentlyContinue)
    } catch {
        Write-Verbose "Process '$prosessi' not found by exact name, trying wildcard search"
    }
    
    # Jos ei lytynyt, kokeile osittaista hakua
    if (-not $loytyneetProsessit -or $loytyneetProsessit.Count -eq 0) {
        $loytyneetProsessit = @(Get-Process | Where-Object { $_.ProcessName -like "*$prosessi*" })
    }
    
    if ($loytyneetProsessit -and $loytyneetProsessit.Count -gt 0) {
        Write-Console "`nLydettiin $($loytyneetProsessit.Count) prosessia:" -ForegroundColor Yellow
        $loytyneetProsessit | Format-Table -Property Name, Id, 
            @{Name="WorkingSet(MB)"; Expression={[math]::Round($_.WorkingSet/1MB, 2)}} -AutoSize
        
        # Varoita kriittisist prosesseista
        $kriittisetProsessit = @("explorer", "winlogon", "csrss", "smss", "services", 
                                  "lsass", "svchost", "wininit", "dwm", "system", "registry")
        
        $prosessinNimi = $loytyneetProsessit[0].ProcessName
        $onKriittinen = $false
        
        foreach ($kriittinen in $kriittisetProsessit) {
            if ($prosessinNimi.ToLower() -eq $kriittinen.ToLower()) {
                $onKriittinen = $true
                break
            }
        }
        
        if ($onKriittinen) {
            Write-Console "`n!!! VAROITUS !!!" -ForegroundColor Red -BackgroundColor DarkRed
            Write-Console "'$prosessinNimi' on KRIITTINEN jrjestelmprosessi!" -ForegroundColor Red
            Write-Console "Sen pysyttminen voi kaataa tietokoneen!" -ForegroundColor Red
            Write-Console ""
            $vahvistus = Read-Host "Oletko TYSIN varma? (kirjoita 'KYLL' vahvistaaksesi)"
            
            if ($vahvistus -ne "KYLL") {
                Write-Console "`nToiminto peruutettu." -ForegroundColor Yellow
                pause
                exit
            }
        }
        
        $vahvistus = Read-Host "`nHaluatko varmasti pysytt nm prosessit? (k/e)"
        
        if ($vahvistus -eq "k" -or $vahvistus -eq "K") {
            $onnistuneet = 0
            $epaonnistuneet = 0
            
            foreach ($p in $loytyneetProsessit) {
                try {
                    $prosessiNimi = "$($p.ProcessName) (PID: $($p.Id))"
                    Stop-Process -Id $p.Id -Force -ErrorAction Stop
                    Write-Console "Prosessi $prosessiNimi pysytetty." -ForegroundColor Green
                    $onnistuneet++
                } catch {
                    Write-Console "Prosessia $prosessiNimi ei voitu pysytt: $_" -ForegroundColor Red
                    $epaonnistuneet++
                }
            }
            
            Write-Console "`nYhteenveto:" -ForegroundColor Cyan
            if ($onnistuneet -gt 0) {
                Write-Console "  Pysytetty: $onnistuneet prosessia" -ForegroundColor Green
            }
            if ($epaonnistuneet -gt 0) {
                Write-Console "  Eponnistui: $epaonnistuneet prosessia" -ForegroundColor Red
                Write-Console "`nVinkki: Kokeile suorittaa PowerShell jrjestelmnvalvojana." -ForegroundColor Yellow
            }
        } else {
            Write-Console "`nToiminto peruutettu." -ForegroundColor Yellow
        }
    } else {
        Write-Console "`nVirhe: Prosessia nimell '$prosessi' ei lytynyt." -ForegroundColor Red
        Write-Console "Tarkista prosessin nimi yll olevasta listasta." -ForegroundColor Yellow
        Write-Console "Huom: l kyt .exe-ptett" -ForegroundColor Yellow
    }
} else {
    Write-Console "`nProsessia ei pysytetty." -ForegroundColor Yellow
}

Write-Console "`nPaina mit tahansa nppint poistuaksesi..."
pause


