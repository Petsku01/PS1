<#
.SYNOPSIS
Prevents system sleep by toggling Scroll Lock at regular intervals.

.DESCRIPTION
This Finnish-language script keeps a computer awake by simulating keyboard input through
Scroll Lock toggles. Useful for maintaining connectivity during long-running tasks or
presentations. The toggle interval is user-configurable.

.PARAMETER None
This script does not accept parameters directly. It prompts the user for the toggle interval.

.EXAMPLE
.\Intune_stay_awake.ps1
(Then enter interval in seconds when prompted)

.NOTES
Stop execution with Ctrl+C at any time.
No administrator privileges required.

.LINK
https://docs.microsoft.com/en-us/previous-versions/windows/desktop/legacy/ms646304(v=vs.85)
#>

# Intune koneille skripti, joka pit tietokoneen hereill vaihtamalla Scroll Lock -nppimen tilaa
# NOTE: If you encounter execution policy errors, run this ONCE as administrator:
#       Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Tyhjenn nytt siistin aloituksen vuoksi
Clear-Host

# Nyt aloitusohjeet
Write-Host "------------------------------------------------------" -ForegroundColor Red
Write-Host "PIT HEREILL -SKRIPTI" -ForegroundColor Cyan
Write-Host "Tm skripti vaihtaa Scroll Lock -nppimen tilaa estkseen tietokoneen menemisen lepotilaan tai lukittumisen." -ForegroundColor Cyan
Write-Host "------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""
Write-Host "AJA SKRIPTI SUORAAN OMALTA TYASEMALTASI." -ForegroundColor Red
Write-Host ""
Write-Host "Lopeta skripti painamalla Ctrl+C milloin tahansa." -ForegroundColor Yellow
Write-Host ""

# Kysy vaihtovli (oletus on 10 sekuntia, jos ei sytet arvoa)
$oletusVali = 10
$valiSyote = Read-Host "Syt vaihtovli sekunneissa (oletus on $oletusVali)"

# Validoi syte
if ([string]::IsNullOrWhiteSpace($valiSyote)) {
    $vali = $oletusVali
} elseif ($valiSyote -match '^\d+$') {
    $vali = [int]$valiSyote
    if ($vali -lt 1) {
        Write-Warning "Vlin on oltava vhintn 1 sekunti. Kytetn oletusarvoa $oletusVali sekuntia."
        $vali = $oletusVali
    }
} else {
    Write-Warning "Virheellinen syte. Kytetn oletusarvoa $oletusVali sekuntia."
    $vali = $oletusVali
}

# Alusta Wscript.Shell COM-objekti
$myshell = $null
try {
    $myshell = New-Object -ComObject "Wscript.Shell" -ErrorAction Stop
} catch {
    Write-Error "Wscript.Shell COM-objektin alustaminen eponnistui. Virhe: $_"
    Write-Host "Paina mit tahansa nppint poistuaksesi..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Psilmukka Scroll Lock -nppimen vaihtamiseen
Write-Host "Aloitetaan Scroll Lock -nppimen vaihto $vali sekunnin vlein..." -ForegroundColor Green
Write-Host ""

try {
    while ($true) {
        # Tarkista ett COM-objekti on edelleen kytettviss
        if ($null -eq $myshell) {
            throw "COM-objekti ei ole en kytettviss"
        }
        
        # Vaihda Scroll Lock -nppimen tila
        $myshell.SendKeys("{SCROLLLOCK}")
        Start-Sleep -Milliseconds 100  # Pieni viive varmistaaksesi nppinpainalluksen rekisteritymisen
        $myshell.SendKeys("{SCROLLLOCK}")  # Vaihda takaisin
        
        # Nyt aikaleimattu viesti
        $aika = Get-Date
        $lyhytAika = $aika.ToString("HH:mm:ss")
        Write-Host "$lyhytAika - Vaihdettiin Scroll Lock -nppimen tilaa, jotta tietokone pysyy hereill."
        
        # Odota mritetty vli
        Start-Sleep -Seconds $vali
    }
} catch {
    Write-Error "Skriptin suorituksessa tapahtui virhe. Virhe: $_"
} finally {
    # Vapauta COM-objekti
    if ($null -ne $myshell) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($myshell) | Out-Null
        $myshell = $null
    }
    
    Write-Host ""
    Write-Host "Skripti pysytetty. Paina mit tahansa nppint poistuaksesi..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

