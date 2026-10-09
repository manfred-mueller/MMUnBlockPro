<#
.SYNOPSIS
  AllInOne-Build für MMUnblock Pro (Firefox, Chrome, Edge + Windows-Installer).

.DESCRIPTION
  1. Prüft Voraussetzungen (.NET SDK, Inno Setup, web-ext, signtool)
  2. Erzeugt aus mmunblockplugin\manifest.base.json je Browser ein eigenes Manifest
     (build\firefox, build\chrome, build\edge) - ohne browserfremde Schlüssel
  3. web-ext lint (Firefox), ZIPs für Chrome Web Store / Edge Add-ons / AMO, signiertes XPI
  4. dotnet publish für mmunblock + mmunblockhost, EXEs signieren (falls nötig)
  5. Inno-Setup-Installer kompilieren
  Ergebnis: dist\<Version>\

  AMO-Zugangsdaten werden aus den Umgebungsvariablen 'AMO-Key' und 'AMO-Secret' gelesen
  (Benutzerebene). Werte werden nie ausgegeben und nur dem web-ext-Aufruf übergeben.

.PARAMETER Dev
  Nur die drei Erweiterungs-Ordner unter build\ erzeugen (zum Laden im Browser).
.PARAMETER SkipFirefoxSign
  Firefox-XPI nicht bei AMO signieren (Lint und ZIP laufen trotzdem).
.PARAMETER SkipExeBuild
  dotnet publish überspringen (vorhandene publish-Ordner verwenden).
.PARAMETER SkipExeSign
  EXE-Signierung überspringen.
.PARAMETER SkipInstaller
  Inno-Setup-Build überspringen.
#>
[CmdletBinding()]
param(
    [switch]$Dev,
    [switch]$SkipFirefoxSign,
    [switch]$SkipExeBuild,
    [switch]$SkipExeSign,
    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── Konfiguration ─────────────────────────────────────────────────────────────
$Root          = $PSScriptRoot
$PluginSrc     = Join-Path $Root 'mmunblockplugin'
$BaseManifest  = Join-Path $PluginSrc 'manifest.base.json'
$IssFile       = Join-Path $Root 'MMUnBlockPro.iss'
$BuildDir      = Join-Path $Root 'build'
$GeckoId       = '@mmunblockpro'
$SignSubject   = 'Open Source Developer, Mueller Manfred'
$SignTimestamp = 'http://time.certum.pl/'
$SignToolPath  = 'D:\Tools\signtool.exe'   # Fallback: signtool.exe aus dem PATH
$ExtFiles      = @('background.js', 'popup.html', 'popup.js')
$ExtDirs       = @('icons')
$ProjectsToPublish = @(
    @{ Name = 'mmunblock';     Proj = 'mmunblock\mmunblock.csproj';         Exe = 'mmunblock\bin\Release\net8.0\win-x64\publish\mmunblock.exe' },
    @{ Name = 'mmunblockhost'; Proj = 'mmunblockhost\mmunblockhost.csproj'; Exe = 'mmunblockhost\bin\Release\net8.0\win-x64\publish\mmunblockhost.exe' }
)
# Öffentlicher Schlüssel (nur für Sideload-Ordner von Chrome/Edge -> stabile Extension-ID).
# ID: eddbjbojbganmlifplgbgjfjgggofmip (muss zu ChromeExtId in MMUnBlockPro.iss passen)
$DevKey = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqhlCz8aoU5qY0JsEWqZXLvpDxUwGU7Yg4f89XhY1F/Ajpv41j8UdzvU5GI79/R2vL/uCNwi0LeOtPw1IRMdMU1oqbS2yCvn8vWv4sdKGnGWy7sHiG9TV8xd1bMLxdiPOfI7mbe+rwh5jedyoxZWL263oAw8xl95lvoYgRzt0HjgPSdb5EM1czvarHpudWUFRwYgUHAKgToIzsXkrQCbcc7VIujHlzD0iSYYJTZz2Or6YClqUYx2dRrQmb0pNywp4Bcv63EK1PdzHsQ/rE0zWQ3jsTqAsfsm/KE9hO1fiUrxAmmU0jtpIx0OhN9rvmIZt9cvunknFhDpbIjWuzs7vgQIDAQAB'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ── Hilfsfunktionen ───────────────────────────────────────────────────────────
function Write-Step($Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok($Text)   { Write-Host "    OK  $Text" -ForegroundColor Green }
function Write-Warn2($Text){ Write-Host "    !!  $Text" -ForegroundColor Yellow }

function Invoke-Native {
    param([string]$File, [string[]]$Arguments)
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$File wurde mit Exitcode $LASTEXITCODE beendet." }
}

function Get-EnvValue([string]$Name) {
    foreach ($scope in 'Process', 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable($Name, $scope)
        if (-not [string]::IsNullOrWhiteSpace($v)) { return $v }
    }
    return $null
}

function Find-Iscc {
    $cmd = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function New-ZipForwardSlash([string]$SourceDir, [string]$ZipPath) {
    # Compress-Archive (Windows PowerShell 5.1) schreibt Backslashes in Pfade - Stores lehnen das ab.
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    $base = (Resolve-Path $SourceDir).Path.TrimEnd('\')
    $zip  = [System.IO.Compression.ZipFile]::Open($ZipPath, 'Create')
    try {
        Get-ChildItem $base -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($base.Length + 1).Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $_.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $zip.Dispose() }
}

function New-ExtensionDir {
    param(
        [ValidateSet('firefox', 'chrome', 'edge')][string]$Target,
        [string]$OutDir,
        [bool]$WithKey
    )
    if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
    New-Item -ItemType Directory -Path $OutDir | Out-Null
    foreach ($f in $ExtFiles) { Copy-Item (Join-Path $PluginSrc $f) $OutDir }
    foreach ($d in $ExtDirs)  { Copy-Item (Join-Path $PluginSrc $d) (Join-Path $OutDir $d) -Recurse }

    $base = Get-Content $BaseManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($forbidden in 'key', 'background', 'browser_specific_settings') {
        if ($base.PSObject.Properties.Name -contains $forbidden) {
            throw "manifest.base.json darf '$forbidden' nicht enthalten (wird pro Browser eingefügt)."
        }
    }

    $m = [ordered]@{}
    foreach ($p in $base.PSObject.Properties) {
        $m[$p.Name] = $p.Value
        if ($p.Name -eq 'version' -and $WithKey -and $Target -ne 'firefox') { $m['key'] = $DevKey }
    }
    switch ($Target) {
        'firefox' {
            $m['browser_specific_settings'] = [ordered]@{
                gecko = [ordered]@{
                    id = $GeckoId
                    data_collection_permissions = [ordered]@{ required = @('none') }
                }
            }
            $m['background'] = [ordered]@{ scripts = @('background.js') }
        }
        default {
            $m['background'] = [ordered]@{ service_worker = 'background.js' }
        }
    }
    $json = ConvertTo-Json -InputObject $m -Depth 10
    Write-Utf8NoBom (Join-Path $OutDir 'manifest.json') $json
}

# ── 1. Voraussetzungen ────────────────────────────────────────────────────────
Write-Step 'Voraussetzungen prüfen'
if (-not (Test-Path $BaseManifest)) { throw "Basis-Manifest fehlt: $BaseManifest" }
$Version = (Get-Content $BaseManifest -Raw -Encoding UTF8 | ConvertFrom-Json).version
if (-not $Version) { throw 'manifest.base.json enthält keine version.' }
Write-Ok "Version $Version"

$DistDir = Join-Path $Root "dist\$Version"
$webExt  = $null
$script:SignTool = $null
$iscc    = $null

if (-not $Dev) {
    if (-not $SkipExeBuild) {
        if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw '.NET SDK (dotnet) nicht gefunden.' }
        Write-Ok ("dotnet " + (& dotnet --version))
    }
    if (-not $SkipInstaller) {
        $iscc = Find-Iscc
        if (-not $iscc) { throw 'Inno Setup (ISCC.exe) nicht gefunden.' }
        Write-Ok "ISCC: $iscc"
    }
    $webExt = Get-Command web-ext -ErrorAction SilentlyContinue
    if (-not $webExt) { throw 'web-ext nicht gefunden (npm install --global web-ext).' }
    Write-Ok 'web-ext vorhanden'

    if (-not $SkipFirefoxSign) {
        foreach ($n in 'AMO-Key', 'AMO-Secret') {
            if (-not (Get-EnvValue $n)) { throw "Umgebungsvariable '$n' ist nicht gesetzt (oder -SkipFirefoxSign verwenden)." }
        }
        Write-Ok 'AMO-Key und AMO-Secret gesetzt'
    }
    if (-not $SkipExeSign -and -not $SkipExeBuild) {
        if (Test-Path $SignToolPath) {
            $script:SignTool = $SignToolPath
        } else {
            $st = Get-Command signtool.exe -ErrorAction SilentlyContinue
            if (-not $st) { throw "signtool.exe nicht gefunden ($SignToolPath / PATH) - oder -SkipExeSign verwenden." }
            $script:SignTool = $st.Source
        }
        Write-Ok "signtool: $script:SignTool"
    }
}

# ── 2. Erweiterungs-Ordner je Browser ─────────────────────────────────────────
Write-Step 'Erweiterungs-Ordner erzeugen (build\firefox, build\chrome, build\edge)'
foreach ($t in 'firefox', 'chrome', 'edge') {
    New-ExtensionDir -Target $t -OutDir (Join-Path $BuildDir $t) -WithKey $true
    Write-Ok "build\$t"
}

if ($Dev) {
    Write-Host ''
    Write-Host 'Dev-Modus: fertig. Zum Testen den jeweiligen Ordner unter build\ laden.' -ForegroundColor Green
    return
}

New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

# ── 3. Store-Pakete, Lint, XPI ────────────────────────────────────────────────
Write-Step 'Firefox: Lint'
Invoke-Native $webExt.Source @('lint', '--source-dir', (Join-Path $BuildDir 'firefox'))
Write-Ok 'web-ext lint ohne Fehler'

Write-Step 'Store-Pakete (ZIP) erzeugen'
New-ZipForwardSlash (Join-Path $BuildDir 'firefox') (Join-Path $DistDir "MMUnblockPro-$Version-firefox.zip")
Write-Ok "MMUnblockPro-$Version-firefox.zip (AMO-Upload)"
foreach ($t in 'chrome', 'edge') {
    # Store-Variante ohne 'key'
    $stage = Join-Path $BuildDir "store\$t"
    New-ExtensionDir -Target $t -OutDir $stage -WithKey $false
    New-ZipForwardSlash $stage (Join-Path $DistDir "MMUnblockPro-$Version-$t.zip")
    Write-Ok "MMUnblockPro-$Version-$t.zip"
}

if (-not $SkipFirefoxSign) {
    Write-Step 'Firefox: XPI bei AMO signieren (unlisted)'
    $env:WEB_EXT_API_KEY    = Get-EnvValue 'AMO-Key'
    $env:WEB_EXT_API_SECRET = Get-EnvValue 'AMO-Secret'
    try {
        Invoke-Native $webExt.Source @(
            'sign',
            '--source-dir', (Join-Path $BuildDir 'firefox'),
            '--artifacts-dir', $DistDir,
            '--channel', 'unlisted')
    } finally {
        Remove-Item Env:\WEB_EXT_API_KEY    -ErrorAction SilentlyContinue
        Remove-Item Env:\WEB_EXT_API_SECRET -ErrorAction SilentlyContinue
    }
    Write-Ok 'signiertes XPI erstellt'
} else {
    Write-Warn2 'Firefox-Signierung übersprungen (-SkipFirefoxSign)'
}

# ── 4. .NET-Komponenten ───────────────────────────────────────────────────────
if (-not $SkipExeBuild) {
    foreach ($p in $ProjectsToPublish) {
        Write-Step "dotnet publish: $($p.Name)"
        Invoke-Native 'dotnet' @(
            'publish', (Join-Path $Root $p.Proj),
            '-c', 'Release', '-r', 'win-x64', '--self-contained', 'false',
            '-p:PublishSingleFile=true', '--nologo')
        Write-Ok $p.Name
    }
}

foreach ($p in $ProjectsToPublish) {
    $exe = Join-Path $Root $p.Exe
    if (-not (Test-Path $exe)) { throw "Fehlt: $exe (dotnet publish nötig)." }
    $sig = Get-AuthenticodeSignature $exe
    if ($sig.Status -eq 'Valid') {
        Write-Ok "$($p.Name).exe bereits signiert"
        continue
    }
    if ($SkipExeSign) {
        Write-Warn2 "$($p.Name).exe ist NICHT signiert (Status: $($sig.Status))"
        continue
    }
    Write-Step "Signieren: $($p.Name).exe"
    Invoke-Native $script:SignTool @('sign', '/a', '/n', $SignSubject, '/t', $SignTimestamp, '/fd', 'sha256', '/v', $exe)
    $sig = Get-AuthenticodeSignature $exe
    if ($sig.Status -ne 'Valid') { throw "$($p.Name).exe: Signatur nach dem Signieren nicht gültig ($($sig.Status))." }
    Write-Ok "$($p.Name).exe signiert"
}

# ── 5. Installer ──────────────────────────────────────────────────────────────
if (-not $SkipInstaller) {
    Write-Step 'Inno-Setup-Installer kompilieren'
    # Das Sign-Tool 'Certum' (SignTool=Certum in der .iss) muss in Inno Setup konfiguriert sein.
    Invoke-Native $iscc @("/DAppVer=$Version", "/O$DistDir", $IssFile)
    Write-Ok 'MMUnblockPro_Setup.exe'
}

# ── 6. Zusammenfassung ────────────────────────────────────────────────────────
Write-Step "Ergebnis: $DistDir"
Get-ChildItem $DistDir -File | ForEach-Object {
    $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.Substring(0, 16)
    '{0,-42} {1,10:N0} Bytes  SHA256 {2}...' -f $_.Name, $_.Length, $h
}
Write-Host ''
Write-Host 'Fertig.' -ForegroundColor Green
