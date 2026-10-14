<#
.SYNOPSIS
  AllInOne-Build für MMUnblock Pro (Firefox, Chrome, Edge + Windows-Installer).

.DESCRIPTION
  1. Prüft Voraussetzungen (.NET SDK, Inno Setup, web-ext, signtool)
  2. Erzeugt aus mmunblockplugin\manifest.base.json je Browser ein eigenes Manifest
     (build\firefox, build\chrome, build\edge) - ohne browserfremde Schlüssel
  3. web-ext lint (Firefox), ZIPs für Chrome Web Store / Edge Add-ons / AMO, Uploads (oder mit -Publish Einreichung)
  4. dotnet publish für mmunblock + mmunblockhost, EXEs signieren (falls nötig)
  5. Inno-Setup-Installer kompilieren
  Ergebnis: dist\<Version>\

  AMO-Zugangsdaten werden aus den Umgebungsvariablen 'AMO-Key' und 'AMO-Secret' gelesen
  (Benutzerebene). Werte werden nie ausgegeben und nur dem web-ext-Aufruf übergeben.

.PARAMETER Dev
  Nur die drei Erweiterungs-Ordner unter build\ erzeugen (zum Laden im Browser).
.PARAMETER SkipExeBuild
  dotnet publish überspringen (vorhandene publish-Ordner verwenden).
.PARAMETER SkipExeSign
  EXE-Signierung überspringen.
.PARAMETER SkipInstaller
  Inno-Setup-Build überspringen.
.PARAMETER SkipUpload
  Keine Uploads in Chrome Web Store und AMO (nur lokal bauen).
.PARAMETER Publish
  Veröffentlichen: Chrome-Version zur Prüfung einreichen und AMO-Version einreichen (beide gehen in die Prüfung).
  Ohne -Publish wird nur hochgeladen (Chrome als Entwurf, AMO nur validiert).
#>
[CmdletBinding()]
param(
    [switch]$Dev,
    [switch]$SkipExeBuild,
    [switch]$SkipExeSign,
    [switch]$SkipInstaller,
    [switch]$SkipUpload,
    [switch]$Publish
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($SkipUpload -and $Publish) { throw '-SkipUpload und -Publish schließen sich aus.' }

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
$ChromePublisherId = '5227114b-09bf-4a3c-a47f-50613a1b7f0c'  # Publisher-ID aus dem Dashboard
$ChromeItemId   = 'fppeblmghlphmkpllialjpchhmpgagio'  # Extension-ID
$ProjectsToPublish = @(
    @{ Name = 'mmunblock';     Proj = 'mmunblock\mmunblock.csproj';         Exe = 'mmunblock\bin\Release\net8.0\win-x64\publish\mmunblock.exe' },
    @{ Name = 'mmunblockhost'; Proj = 'mmunblockhost\mmunblockhost.csproj'; Exe = 'mmunblockhost\bin\Release\net8.0\win-x64\publish\mmunblockhost.exe' }
)
# Öffentlicher Schlüssel aus dem Chrome-Web-Store-Dashboard (Reiter 'Paket'). Er gilt auch für die Sideload-Ordner
# (build\chrome, build\edge), damit die Extension-ID überall gleich ist.
# ID: fppeblmghlphmkpllialjpchhmpgagio (muss zu ChromeExtId in MMUnBlockPro.iss passen)
$DevKey = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA8Pi8m62v0h7ZWJJhgWb30lOBOKNjIGIDPCxuTtKvl9hsh7US0CWIxAqmLlxPuzYmzDS8HUE9hCHcM7xQQ4JDow8q66jF8l0BFRXyEZJaTXcDlOZImsIW5UFtiB336lws0wNvo/UWYgQ6ZqL65MWUmYnP+Ub6dBS6M76NpS38HH2jGO7M5bcpjx0qytTV7M1R5p4YPjZfV52pQ593B6Nw2TtK1Fyd5Uvj8V3peqQncZmCgPun51ghZFGVLXkLigan3mcTLH/mkfHg8wB0vYy0yDp8hNezW4lU1GB1T62mEtbRYqEvGM3FOxSPwP253sdG1KtXsMO2eqCfvu97O4BSXQIDAQAB'

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

# ── Chrome Web Store: Upload und optional Veröffentlichung ───────────────────
function Get-ChromeStoreToken {
    foreach ($n in 'GC-Client', 'GC-Key', 'GC-Refresh') {
        if (-not (Get-EnvValue $n)) { throw "Umgebungsvariable '$n' ist nicht gesetzt." }
    }
    $resp = Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' -Body @{
        client_id     = (Get-EnvValue 'GC-Client')
        client_secret = (Get-EnvValue 'GC-Key')
        refresh_token = (Get-EnvValue 'GC-Refresh')
        grant_type    = 'refresh_token'
    }
    return $resp.access_token
}

function Publish-ChromeStore {
    param([string]$ZipPath, [switch]$Publish)
    if (-not (Test-Path $ZipPath)) { throw "ZIP fehlt: $ZipPath" }
    $headers = @{ Authorization = 'Bearer ' + (Get-ChromeStoreToken) }
    $api = 'https://chromewebstore.googleapis.com'

    Write-Step 'Chrome Web Store: hochladen (Entwurf)'
    try {
        $up = Invoke-RestMethod -Method Post -Uri "$api/upload/v2/publishers/$ChromePublisherId/items/${ChromeItemId}:upload" -Headers $headers -InFile $ZipPath -ContentType 'application/zip'
    } catch {
        $msg = [string]$_.Exception.Message + ' ' + [string]$_.ErrorDetails.Message
        if ($msg -match 'in review|NOT_UPDATEABLE') {
            Write-Warn2 'Chrome Web Store: Der Artikel ist aktuell in der Prüfung. Upload und Veröffentlichung sind erst wieder möglich, wenn die Prüfung abgeschlossen ist. Chrome wird übersprungen.'
            return
        }
        throw
    }
    if ($up.uploadState -eq 'FAILED') { throw ("Chrome-Upload fehlgeschlagen: " + ($up | ConvertTo-Json -Depth 6 -Compress)) }
    Write-Ok ("Upload: " + $up.uploadState)

    if ($Publish) {
        Write-Step 'Chrome Web Store: veröffentlichen (geht in die Prüfung)'
        $pub = Invoke-RestMethod -Method Post -Uri "$api/v2/publishers/$ChromePublisherId/items/${ChromeItemId}:publish" -Headers $headers -ContentType 'application/json' -Body '{}'
        Write-Ok ("Veröffentlichung eingereicht: " + ($pub | ConvertTo-Json -Depth 6 -Compress))
    } else {
        Write-Warn2 'Nicht veröffentlicht (ohne -Publish). Der Upload liegt im Dashboard als Entwurf.'
    }
}

# ── AMO (listed): Paket validieren, optional als neue Version einreichen ─────
$AmoSlug = 'mmunblock-pro'
$AmoApi  = 'https://addons.mozilla.org/api/v5/addons'
$AmoApprovalNotes = 'Benötigt eine kleine Windows-Komponente (Native Messaging Host, Installer auf GitHub Releases). Ohne sie zeigt die Erweiterung einen Hinweis mit Link zum Installer. Test: Installer ausführen, dann eine beliebige Datei aus dem Internet herunterladen. Die Erweiterung fragt per Benachrichtigung, ob sie entsperrt werden soll.'

function New-AmoJwt {
    $key = (Get-EnvValue 'AMO-Key').Trim()
    if ($key -notmatch '^user:') { $key = "user:$key" }
    $secret = (Get-EnvValue 'AMO-Secret').Trim()
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $b64url = { param([string]$t) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($t)).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
    $header  = & $b64url '{"alg":"HS256","typ":"JWT"}'
    $payload = & $b64url (@{ iss = $key; jti = [guid]::NewGuid().ToString(); iat = $now; exp = $now + 60 } | ConvertTo-Json -Compress)
    $unsigned = "$header.$payload"
    $hmac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList @(, [Text.Encoding]::UTF8.GetBytes($secret))
    $sig = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($unsigned))).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    return "$unsigned.$sig"
}

function Publish-AmoListed {
    param([string]$ZipPath, [switch]$Publish)
    if (-not (Test-Path $ZipPath)) { throw "ZIP fehlt: $ZipPath" }

    Write-Step 'AMO: Paket hochladen (listed, Validierung)'
    $raw = & curl.exe -s -S -X POST -H ("Authorization: JWT " + (New-AmoJwt)) -F "upload=@$ZipPath" -F 'channel=listed' "$AmoApi/upload/"
    if ($LASTEXITCODE -ne 0) { throw "AMO-Upload fehlgeschlagen (curl Exitcode $LASTEXITCODE)." }
    $up = $raw | ConvertFrom-Json
    if (-not $up.uuid) { throw "AMO-Upload ohne UUID: $raw" }
    $uuid = $up.uuid

    $st = $null
    $done = $false
    for ($i = 0; $i -lt 60 -and -not $done; $i++) {
        Start-Sleep -Seconds 5
        $st = Invoke-RestMethod -Method Get -Uri "$AmoApi/upload/$uuid/" -Headers @{ Authorization = 'JWT ' + (New-AmoJwt) }
        if ($st.processed) { $done = $true }
    }
    if (-not $done) { throw 'AMO: Validierung dauert zu lange (Timeout).' }
    if (-not $st.valid) { throw ('AMO-Validierung fehlgeschlagen: ' + ($st | ConvertTo-Json -Depth 8 -Compress)) }
    Write-Ok 'AMO: Paket ist valide'

    if (-not $Publish) {
        Write-Warn2 'AMO nur validiert (ohne -Publish). Keine Einreichung.'
        return
    }
    Write-Step 'AMO: Version einreichen (geht in die Prüfung)'
    $body = @{ upload = $uuid; approval_notes = $AmoApprovalNotes } | ConvertTo-Json -Compress
    $null = Invoke-RestMethod -Method Post -Uri "$AmoApi/addon/$AmoSlug/versions/" -Headers @{ Authorization = 'JWT ' + (New-AmoJwt) } -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
    Write-Ok 'AMO: Version eingereicht (wartet auf Prüfung durch Mozilla)'
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

    if (-not $SkipUpload) {
        foreach ($n in 'AMO-Key', 'AMO-Secret', 'GC-Client', 'GC-Key', 'GC-Refresh') {
            if (-not (Get-EnvValue $n)) { throw "Umgebungsvariable '$n' ist nicht gesetzt (oder -SkipUpload verwenden)." }
        }
        Write-Ok 'Store-Zugangsdaten (AMO, Chrome) gesetzt'
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

if (-not $SkipUpload) {
    Publish-ChromeStore -ZipPath (Join-Path $DistDir "MMUnblockPro-$Version-chrome.zip") -Publish:$Publish
}

if (-not $SkipUpload) {
    Publish-AmoListed -ZipPath (Join-Path $DistDir "MMUnblockPro-$Version-firefox.zip") -Publish:$Publish
} else {
    Write-Warn2 'AMO-Upload übersprungen (-SkipUpload)'
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
