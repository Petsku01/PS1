<#
.SYNOPSIS
Monitors remote service status with periodic checks (Finnish).

.DESCRIPTION
Monitors the status of a specified Windows service on a remote computer.
Performs connectivity validation and provides periodic status updates every 30 seconds.
Useful for troubleshooting and automated service monitoring.

.PARAMETER ComputerName
Target computer name (prompted if not specified).

.PARAMETER ServiceName
Windows service name to monitor (prompted if not specified).

.EXAMPLE
.\tarkista_palvelu.ps1
(Then enter computer and service names when prompted)

.NOTES
Checks target computer connectivity before querying.
Updates status approximately every 30 seconds.
Press Ctrl+C to exit monitoring.

.LINK
https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-service
#>

#Requires -Version 5.1

# Mrit kohdekone ja palvelun nimi
$computerName = Read-Host "Anna kohdekoneen nimi"
$serviceName = Read-Host "Anna palvelun nimi"

# Ilmoita kyttjlle skriptin toiminnasta
Write-Output "Tm skripti tarkistaa $serviceName-palvelun tilan koneella $computerName noin 30 sekunnin vlein."
Write-Output "Paina Enter tarkistaaksesi tilan vlittmsti tai Ctrl+C pysyttksesi skriptin."

# Funktio palvelun tarkistamiseen
function Test-ServiceStatus {
    try {
        # Tarkista, onko kohdekone tavoitettavissa
        if (Test-Connection -ComputerName $computerName -Count 1 -Quiet) {
            # Hae palvelun tila
            $service = Get-Service -ComputerName $computerName -Name $serviceName -ErrorAction Stop
            
            # Tulosta palvelun tila
            if ($service.Status -eq "Running") {
                Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): TOIMII ($serviceName-palvelu on kynniss)."
            } else {
                Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): EI TOIMI ($serviceName-palvelu ei ole kynniss, tila: $($service.Status))."
            }
        } else {
            Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): VIRHE: Kone $computerName ei ole tavoitettavissa."
        }
    }
    catch {
        # Tulosta virheviesti
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): VIRHE: $serviceName-palvelun tarkistus eponnistui koneella $computerName. Virhe: $($_.Exception.Message)"
    }
}

# retn silmukka palvelun jatkuvaan tarkistamiseen
while ($true) {
    # Tarkista, onko nppin painettu
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Enter) {
            Test-ServiceStatus
        }
    } else {
        # Suorita automaattinen tarkistus
        Test-ServiceStatus
    }
    # Odota 30 sekuntia, mutta tarkista nppimist sekunnin vlein
    for ($i = 0; $i -lt 30; $i++) {
        if ([Console]::KeyAvailable) {
            break
        }
        Start-Sleep -Seconds 1
    }
}

