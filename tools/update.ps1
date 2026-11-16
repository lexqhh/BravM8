# Installe ou met à jour l'add-on BravM8 dans WoW: Forever.
# Lancé par BravM8.bat (double-clic) ou au démarrage de Windows (mode silencieux).
# Migre aussi les anciennes installations nommées FlyMedia.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'

$Name    = 'BravM8'
$OldName = 'FlyMedia'

# les anciens scripts (FlyMedia.bat, silent.ps1) passent encore les variables FLYMEDIA_*
$Repo = if ($env:BRAVM8_REPO) { $env:BRAVM8_REPO } else { $env:FLYMEDIA_REPO }
if ($Repo) { $Repo = $Repo -replace "/$OldName$", "/$Name" }
$Silent = ($env:BRAVM8_SILENT -eq '1') -or ($env:FLYMEDIA_SILENT -eq '1')

$Base       = "https://github.com/$Repo/releases/latest/download"
$ConfigDir  = Join-Path $env:APPDATA $Name
$ConfigFile = Join-Path $ConfigDir 'config.json'
$Desktop    = [Environment]::GetFolderPath('Desktop')
$Startup    = [Environment]::GetFolderPath('Startup')
$DesktopLnk = Join-Path $Desktop "Mettre à jour $Name.lnk"
$StartupLnk = Join-Path $Startup "$Name.lnk"

function Say([string]$msg, [string]$color = 'Gray') {
    if (-not $Silent) { Write-Host $msg -ForegroundColor $color }
}

function Finish([int]$code) {
    if (-not $Silent) {
        Write-Host ''
        Read-Host 'Appuie sur Entrée pour fermer' | Out-Null
    }
    exit $code
}

function Load-Config {
    if (Test-Path $ConfigFile) {
        try { return Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    return [pscustomobject]@{ forever = ''; setupDone = $false }
}

function Save-Config($cfg) {
    New-Item -ItemType Directory -Force $ConfigDir | Out-Null
    $cfg | ConvertTo-Json | Set-Content $ConfigFile -Encoding UTF8
}

# Renvoie le dossier _forever_ à partir d'un dossier WoW (racine ou sous-dossier _xxx_).
function Resolve-Forever([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Container)) { return $null }
    $dir = Get-Item -LiteralPath $path
    if ($dir.Name -match 'forever') { return $dir.FullName }
    if ($dir.Name -match '^_.+_$' -and $dir.Parent) { $dir = $dir.Parent }
    $hit = Get-ChildItem -LiteralPath $dir.FullName -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^_.*forever.*_$' } | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

function Find-Forever($cfg) {
    $candidates = @()
    if ($cfg.forever) { $candidates += $cfg.forever }

    $keys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
        'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\World of Warcraft',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\World of Warcraft'
    )
    foreach ($k in $keys) {
        $item = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if ($item) {
            if ($item.InstallPath) { $candidates += $item.InstallPath }
            if ($item.InstallLocation) { $candidates += $item.InstallLocation }
        }
    }

    foreach ($drive in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue) {
        foreach ($sub in 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft',
                         'World of Warcraft', 'Games\World of Warcraft', 'Jeux\World of Warcraft',
                         'Battle.net\World of Warcraft') {
            $candidates += Join-Path $drive.Root $sub
        }
    }

    foreach ($c in $candidates) {
        $found = Resolve-Forever $c.TrimEnd('\')
        if ($found) { return $found }
    }
    return $null
}

function Ask-Forever {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Sélectionne ton dossier "World of Warcraft" (celui qui contient _forever_)'
    $dlg.ShowNewFolderButton = $false
    while ($true) {
        if ($dlg.ShowDialog() -ne 'OK') { return $null }
        $found = Resolve-Forever $dlg.SelectedPath
        if ($found) { return $found }
        Say "Pas de dossier WoW: Forever dans « $($dlg.SelectedPath) ». Réessaie." Yellow
    }
}

function New-Shortcut([string]$lnk, [string]$target, [string]$arguments = '') {
    $shell = New-Object -ComObject WScript.Shell
    $s = $shell.CreateShortcut($lnk)
    $s.TargetPath = $target
    $s.Arguments = $arguments
    $s.WorkingDirectory = $ConfigDir
    $s.Save()
}

# Raccourci du bureau vers une copie locale du .bat
function Install-DesktopShortcut {
    New-Item -ItemType Directory -Force $ConfigDir | Out-Null
    $bat = Join-Path $ConfigDir "$Name.bat"
    (New-Object Net.WebClient).DownloadFile("$Base/$Name.bat", $bat)
    New-Shortcut $DesktopLnk $bat
}

# Mise à jour silencieuse au démarrage de Windows
function Install-Startup {
    New-Item -ItemType Directory -Force $ConfigDir | Out-Null
    $silentScript = Join-Path $ConfigDir 'silent.ps1'
    @"
Start-Sleep -Seconds 30
`$env:BRAVM8_SILENT = '1'
`$env:BRAVM8_REPO = '$Repo'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
`$p = Join-Path `$env:TEMP 'bravm8-update.ps1'
try { (New-Object Net.WebClient).DownloadFile('https://github.com/$Repo/releases/latest/download/update.ps1', `$p); & `$p } catch { }
"@ | Set-Content $silentScript -Encoding UTF8
    New-Shortcut $StartupLnk 'powershell.exe' `
        "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$silentScript`""
}

# Ancienne installation FlyMedia : on reprend sa config et ses raccourcis sous le nouveau nom.
function Migrate-OldInstall {
    $oldDir = Join-Path $env:APPDATA $OldName
    $oldDesktop = Join-Path $Desktop "Mettre à jour $OldName.lnk"
    $oldStartup = Join-Path $Startup "$OldName.lnk"
    $hadDesktop = Test-Path -LiteralPath $oldDesktop
    $hadStartup = Test-Path -LiteralPath $oldStartup
    if (-not ((Test-Path $oldDir) -or $hadDesktop -or $hadStartup)) { return }

    New-Item -ItemType Directory -Force $ConfigDir | Out-Null
    $oldConfig = Join-Path $oldDir 'config.json'
    if ((Test-Path $oldConfig) -and -not (Test-Path $ConfigFile)) {
        Copy-Item $oldConfig $ConfigFile
    }
    if ($hadDesktop) {
        Remove-Item -LiteralPath $oldDesktop -Force -ErrorAction SilentlyContinue
        Install-DesktopShortcut
    }
    if ($hadStartup) {
        Remove-Item -LiteralPath $oldStartup -Force -ErrorAction SilentlyContinue
        Install-Startup
    }
    Remove-Item -LiteralPath $oldDir -Recurse -Force -ErrorAction SilentlyContinue
    Say "Ancienne version renommée en $Name." Green
}

function First-Setup($cfg) {
    Install-DesktopShortcut
    Say "Raccourci « Mettre à jour $Name » ajouté sur le bureau." Green

    Write-Host ''
    $answer = Read-Host "Mettre à jour $Name tout seul à chaque démarrage de Windows ? (O/N)"
    if ($answer -match '^\s*[oOyY]') {
        Install-Startup
        Say 'OK : la mise à jour se fera toute seule au démarrage.' Green
    } else {
        Say 'OK : utilise le raccourci du bureau quand il y a du nouveau.'
    }
    $cfg.setupDone = $true
}

# ---------------------------------------------------------------------------

try {
    if (-not $Repo) { throw "Lance plutôt $Name.bat." }
    Say "=== $Name ===" Cyan

    Migrate-OldInstall

    $cfg = Load-Config
    $forever = Find-Forever $cfg
    if (-not $forever) {
        if ($Silent) { exit 0 }
        Say "Je n'ai pas trouvé WoW: Forever tout seul, une fenêtre va s'ouvrir pour que tu choisisses le dossier." Yellow
        $forever = Ask-Forever
        if (-not $forever) { Say 'Annulé.' Yellow; Finish 1 }
    }
    $cfg.forever = $forever
    Say "WoW: Forever : $forever"

    $addons = Join-Path $forever 'Interface\AddOns'
    $target = Join-Path $addons $Name
    New-Item -ItemType Directory -Force $addons | Out-Null

    # l'ancien dossier d'add-on ne doit pas rester, sinon tout s'afficherait en double
    $oldAddon = Join-Path $addons $OldName
    if (Test-Path -LiteralPath $oldAddon) {
        Remove-Item -LiteralPath $oldAddon -Recurse -Force -ErrorAction SilentlyContinue
    }

    $localVer = ''
    if (Test-Path (Join-Path $target 'version.txt')) {
        $localVer = (Get-Content (Join-Path $target 'version.txt') -Raw).Trim()
    }

    $wc = New-Object Net.WebClient
    $wc.Encoding = [Text.Encoding]::UTF8
    $remoteVer = $wc.DownloadString("$Base/version.txt").Trim()

    if ($localVer -eq $remoteVer) {
        Say "Déjà à jour (version $localVer)." Green
    } else {
        $tmp = Join-Path $env:TEMP ('bravm8-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $tmp | Out-Null
        try {
            $zip = Join-Path $tmp "$Name.zip"
            Say "Téléchargement de la version $remoteVer..."
            $wc.DownloadFile("$Base/$Name.zip", $zip)
            Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
            $src = Join-Path $tmp $Name
            if (-not (Test-Path (Join-Path $src "$Name.toc"))) { throw 'Archive téléchargée invalide.' }

            # on vide l'ancien dossier (si WoW bloque un fichier, on écrase par-dessus)
            if (Test-Path $target) {
                try { Remove-Item -LiteralPath $target -Recurse -Force } catch { }
            }
            New-Item -ItemType Directory -Force $target | Out-Null
            Copy-Item -Path (Join-Path $src '*') -Destination $target -Recurse -Force
        } finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($localVer) {
            Say "Mis à jour : version $localVer -> $remoteVer." Green
        } else {
            Say "$Name installé (version $remoteVer)." Green
        }

        $root = Split-Path $forever -Parent
        $wowOpen = Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -and $_.Path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) }
        if ($wowOpen) {
            Say 'WoW est ouvert : relance le jeu pour voir les nouveautés.' Yellow
        }
    }

    if (-not $cfg.setupDone -and -not $Silent) { First-Setup $cfg }
    Save-Config $cfg
    Finish 0
} catch {
    Say "Erreur : $($_.Exception.Message)" Red
    Finish 1
}
