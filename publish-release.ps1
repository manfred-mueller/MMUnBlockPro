<#
.SYNOPSIS
    Legt ein GitHub-Release für MMUnBlock Pro an und lädt den signierten Installer hoch.

.DESCRIPTION
    Der Installer (dist\<Version>\MMUnblockPro_Setup.exe) wird lokal mit Build-All.ps1
    gebaut und signiert. Dieses Script veröffentlicht nur das fertige Paket als
    Release-Asset. Es baut nichts neu.

    Mit -Commit werden uncommittete Änderungen interaktiv committet und gepusht.
    Dateien werden nur nach ausdrücklicher Auswahl gestaged, nie automatisch alle.
    Commit und Push brauchen jeweils eine Bestätigung.

.NOTES
    Voraussetzung: GitHub CLI installiert und angemeldet (gh auth login).
    Die Version kommt aus mmunblockplugin\manifest.base.json.

.EXAMPLE
    .\publish-release.ps1 -DryRun       # Prüfen, nichts anlegen oder committen
    .\publish-release.ps1 -Commit       # Änderungen interaktiv committen/pushen, dann Release
    .\publish-release.ps1               # Release anlegen (Stand muss bereits gepusht sein)
    .\publish-release.ps1 -PreRelease   # Als Vorabversion anlegen
#>

[CmdletBinding()]
param(
    [switch] $DryRun,
    [switch] $PreRelease,
    # Vorhandenes Release mit gleichem Tag ersetzen (sonst Abbruch)
    [switch] $Replace,
    # Uncommittete Änderungen interaktiv committen und pushen
    [switch] $Commit,
    # Release-Notizen (Freitext)
    [string] $Notes = ''
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot
$Repo = 'manfred-mueller/mmunblockpro'

function Read-YesNo([string] $Question) {
    return ((Read-Host "$Question [j/N]") -match '^(j|ja|y|yes)$')
}

# --- 0. Werkzeuge prüfen ----------------------------------------------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI nicht gefunden. Installieren mit: winget install --id GitHub.cli"
}
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
gh auth status 2>&1 | Out-Null
$authed = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prevEap
if (-not $authed) { throw "GitHub CLI ist nicht angemeldet. Bitte 'gh auth login' ausführen." }

# --- 1. Version und Installer ----------------------------------------------
$version = (Get-Content 'mmunblockplugin\manifest.base.json' -Raw -Encoding UTF8 | ConvertFrom-Json).version
if ([string]::IsNullOrWhiteSpace($version)) { throw 'Keine Version in manifest.base.json gefunden.' }

$tag   = "v$version"
$setup = "dist\$version\MMUnblockPro_Setup.exe"
Write-Host "Version: $version" -ForegroundColor Cyan
Write-Host "Tag:     $tag"     -ForegroundColor Cyan

if (-not (Test-Path $setup)) {
    throw "Installer fehlt: $setup. Bitte zuerst .\Build-All.ps1 ausführen."
}

# Signatur prüfen: Ein unsigniertes Paket soll nicht als Release erscheinen.
$sig = Get-AuthenticodeSignature $setup
if ($sig.Status -ne 'Valid') {
    throw "Installer ist nicht gültig signiert (Status: $($sig.Status))."
}
Write-Host "Signatur OK: $($sig.SignerCertificate.Subject)" -ForegroundColor Green

# --- 2. Git-Stand prüfen (ggf. interaktiv committen und pushen) -------------
$branch = (git rev-parse --abbrev-ref HEAD).Trim()

$lines = @(git status --porcelain)
if ($lines.Count -gt 0 -and $DryRun) {
    Write-Host "`nDryRun: Uncommittete Änderungen (ein echter Lauf würde hier abbrechen):" -ForegroundColor Yellow
    $lines | ForEach-Object { Write-Host "  $_" }
}
elseif ($lines.Count -gt 0) {
    if (-not $Commit -or $DryRun) {
        Write-Host "`nNicht committete Änderungen:" -ForegroundColor Yellow
        $lines | ForEach-Object { Write-Host "  $_" }
        throw 'Bitte erst committen und pushen (oder mit -Commit interaktiv), sonst zeigt das Release auf veralteten Quellcode.'
    }

    Write-Host "`nUncommittete Änderungen:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $lines.Count; $i++) {
        Write-Host ("  {0,2}) {1}" -f ($i + 1), $lines[$i])
    }
    $sel = Read-Host "`nNummern der Dateien zum Committen (z. B. 1,3,4) oder 'alle'"
    if ($sel.Trim() -match '^(alle|a)$') {
        $indices = @(1..$lines.Count)
    }
    else {
        $indices = @($sel -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    }
    if ($indices.Count -eq 0) { throw 'Keine Dateien ausgewählt. Abgebrochen.' }

    $files = @()
    foreach ($n in $indices) {
        if ($n -lt 1 -or $n -gt $lines.Count) { throw "Ungültige Nummer: $n" }
        $files += $lines[$n - 1].Substring(3)
    }

    $msg = Read-Host 'Commit-Nachricht'
    if ([string]::IsNullOrWhiteSpace($msg)) { throw 'Keine Commit-Nachricht. Abgebrochen.' }

    Write-Host "`nDateien: $($files -join ', ')" -ForegroundColor Cyan
    if (-not (Read-YesNo "Diese $($files.Count) Datei(en) mit der Nachricht committen?")) {
        throw 'Commit abgebrochen. Nichts verändert.'
    }
    git add -- $files
    git commit -m $msg
    if ($LASTEXITCODE -ne 0) { throw "git commit ist mit Code $LASTEXITCODE fehlgeschlagen." }
    Write-Host 'Commit erstellt.' -ForegroundColor Green
}

git fetch --quiet origin $branch 2>$null
$ahead = (git rev-list --count "origin/$branch..HEAD" 2>$null)
if ($ahead -and [int]$ahead -gt 0 -and $DryRun) {
    Write-Host "$ahead Commit(s) noch nicht gepusht (Dry-Run, kein Abbruch)." -ForegroundColor Yellow
}
elseif ($ahead -and [int]$ahead -gt 0) {
    if (-not $Commit -or $DryRun) {
        throw "$ahead Commit(s) noch nicht gepusht. Bitte erst 'git push' ausführen oder -Commit verwenden."
    }
    if (-not (Read-YesNo "$ahead Commit(s) auf origin/$branch pushen?")) {
        throw 'Push abgebrochen. Kein Release angelegt.'
    }
    git push origin $branch
    if ($LASTEXITCODE -ne 0) { throw "git push ist mit Code $LASTEXITCODE fehlgeschlagen." }
    Write-Host 'Gepusht.' -ForegroundColor Green
}

# --- 3. Vorhandenes Release -------------------------------------------------
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
gh release view $tag --repo $Repo 2>&1 | Out-Null
$exists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prevEap
if ($exists -and -not $Replace) {
    throw "Release $tag existiert bereits. Mit -Replace ersetzen oder Version erhöhen."
}

if ($DryRun) {
    Write-Host "`n-DryRun: Kein Release angelegt." -ForegroundColor Yellow
    exit 0
}

# --- 4. Release anlegen -----------------------------------------------------
if ($exists) {
    Write-Host "`nRelease $tag wird ersetzt." -ForegroundColor Yellow
    gh release delete $tag --repo $Repo --yes --cleanup-tag
}

if ([string]::IsNullOrWhiteSpace($Notes)) { $Notes = "MMUnBlock Pro $version" }
$notesFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $notesFile -Value $Notes -Encoding utf8

$ghArgs = @('release', 'create', $tag, $setup, '--repo', $Repo, '--title', "MMUnBlock Pro $tag", '--notes-file', $notesFile)
if ($PreRelease) { $ghArgs += '--prerelease' }

gh @ghArgs
$ghExit = $LASTEXITCODE
Remove-Item $notesFile -Force -ErrorAction SilentlyContinue
if ($ghExit -ne 0) { throw "gh release create ist mit Code $ghExit fehlgeschlagen." }

Write-Host "`nFertig: https://github.com/$Repo/releases/tag/$tag" -ForegroundColor Green
