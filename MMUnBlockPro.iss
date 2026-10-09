; ─── Inno Setup Definition für MMUnblockPro ──────────────────────────────────

; Extension-IDs fuer Chrome/Edge (allowed_origins im Host-Manifest).
; ChromeExtId = ID aus dem Manifest-"key" (Sideload + Chrome Web Store, wenn mit key hochgeladen).
; EdgeExtId   = ID nach Veroeffentlichung im Edge-Add-ons-Store eintragen (leer = nicht verwendet).
#ifndef AppVer
#define AppVer "1.4.1"
#endif
#define ChromeExtId "eddbjbojbganmlifplgbgjfjgggofmip"
#define EdgeExtId ""

; Store-Links fuer den Abschlussdialog des Installers. Leer = Eintrag entfaellt.
; Chrome/Edge: nach der Veroeffentlichung (nicht gelistet/hidden) die direkte Store-URL eintragen.
#define FirefoxStoreUrl "https://addons.mozilla.org/de/firefox/addon/mmunblock-pro/"
#define ChromeStoreUrl ""
#define EdgeStoreUrl ""

[Setup]
AppId={{F9B000EB-33B8-4250-B957-C153B1948945}}
AppName=MMUnblockPro
AppVersion={#AppVer}
AppPublisher=Open Source Developer, Mueller Manfred
DefaultDirName={localappdata}\MMUnblockPro
DefaultGroupName=MMUnblockPro
; Der Installer benötigt KEINE Admin-Rechte, da er im Benutzerverzeichnis installiert
PrivilegesRequired=lowest
OutputDir=.
OutputBaseFilename=MMUnblockPro_Setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=D:\Bilder\nass-ek.ico
UninstallDisplayIcon={uninstallexe}
;Begin adjustments for showing the logo
DisableWelcomePage=False
WizardImageFile=D:\Bilder\wz_nass-ek.bmp
WizardSmallImageFile=D:\Bilder\wz_leer_small.bmp
;End adjustments for showing the logo
WizardStyle=modern
SignTool=Certum

[Files]
; Hier holen wir deine beiden fertig veröffentlichten (und idealerweise signierten) EXEs ab
Source: "mmunblock\bin\Release\net8.0\win-x64\publish\mmunblock.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "mmunblockhost\bin\Release\net8.0\win-x64\publish\mmunblockhost.exe"; DestDir: "{app}"; Flags: ignoreversion

[Registry]
; 1. Den Registry-Pfad für Mozilla Firefox Native Messaging im aktuellen Benutzerkonto (HKCU) anlegen
Root: HKCU; Subkey: "Software\Mozilla\NativeMessagingHosts\com.mmunblock"; ValueType: string; ValueData: "{app}\com.mmunblock.json"; Flags: uninsdeletekey
; Chrome und Edge: gleicher Host, eigenes Manifest mit allowed_origins
Root: HKCU; Subkey: "Software\Google\Chrome\NativeMessagingHosts\com.mmunblock"; ValueType: string; ValueData: "{app}\com.mmunblock.chromium.json"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Microsoft\Edge\NativeMessagingHosts\com.mmunblock"; ValueType: string; ValueData: "{app}\com.mmunblock.chromium.json"; Flags: uninsdeletekey

[Run]
; Abschlussdialog: Erweiterung im jeweils installierten Browser oeffnen (Haken kann abgewaehlt werden)
#if FirefoxStoreUrl != ""
Filename: "{code:GetBrowserExe|firefox}"; Parameters: """{#FirefoxStoreUrl}"""; Description: "Erweiterung für Firefox installieren (Add-on-Seite öffnen)"; Flags: nowait postinstall skipifsilent; Check: HasBrowser('firefox')
#endif
#if ChromeStoreUrl != ""
Filename: "{code:GetBrowserExe|chrome}"; Parameters: """{#ChromeStoreUrl}"""; Description: "Erweiterung für Chrome installieren (Store-Seite öffnen)"; Flags: nowait postinstall skipifsilent; Check: HasBrowser('chrome')
#endif
#if EdgeStoreUrl != ""
Filename: "{code:GetBrowserExe|msedge}"; Parameters: """{#EdgeStoreUrl}"""; Description: "Erweiterung für Edge installieren (Add-ons-Seite öffnen)"; Flags: nowait postinstall skipifsilent; Check: HasBrowser('msedge')
#endif

[UninstallDelete]
Type: files; Name: "{app}\com.mmunblock.json"
Type: files; Name: "{app}\com.mmunblock.chromium.json"

[Code]
// Pfad eines installierten Browsers aus den Windows-"App Paths" lesen (leer = nicht installiert)
function GetBrowserExe(Param: String): String;
var
  Key, Path: String;
begin
  Key := 'Software\Microsoft\Windows\CurrentVersion\App Paths\' + Param + '.exe';
  Path := '';
  if not RegQueryStringValue(HKCU, Key, '', Path) then
    if not RegQueryStringValue(HKLM64, Key, '', Path) then
      RegQueryStringValue(HKLM32, Key, '', Path);
  Result := RemoveQuotes(Path);
end;

function HasBrowser(Name: String): Boolean;
var
  Exe: String;
begin
  Exe := GetBrowserExe(Name);
  Result := (Exe <> '') and FileExists(Exe);
end;

// 2. Das JSON-Manifest dynamisch während der Installation schreiben
procedure CurStepChanged(CurStep: TSetupStep);
var
  JsonLines: TArrayOfString;
  JsonFilePath: String;
  HostPath: String;
  ChromiumJsonPath: String;
  ChromiumLines: TArrayOfString;
  Origins: String;
begin
  if CurStep = ssPostInstall then
  begin
    JsonFilePath := ExpandConstant('{app}\com.mmunblock.json');
    
    // Den Pfad holen und alle einfachen Backslashes durch doppelte Backslashes ersetzen
    HostPath := ExpandConstant('{app}\mmunblockhost.exe');
    StringChangeEx(HostPath, '\', '\\', True);
    
    SetArrayLength(JsonLines, 9);
    JsonLines[0] := '{';
    JsonLines[1] := '  "name": "com.mmunblock",';
    JsonLines[2] := '  "description": "Native Messaging Host fuer MMUnblock (Signiert)",';
    JsonLines[3] := '  "path": "' + HostPath + '",';
    JsonLines[4] := '  "type": "stdio",';
    JsonLines[5] := '  "allowed_extensions": [';
    JsonLines[6] := '    "@mmunblockpro"';
    JsonLines[7] := '  ]';
    JsonLines[8] := '}';

    if not SaveStringsToFile(JsonFilePath, JsonLines, False) then
    begin
      Log('Fehler beim Erstellen der com.mmunblock.json');
    end;

    // Chrome / Edge: gleiches Format, aber allowed_origins statt allowed_extensions
    ChromiumJsonPath := ExpandConstant('{app}\com.mmunblock.chromium.json');
    Origins := '    "chrome-extension://{#ChromeExtId}/"';
    if '{#EdgeExtId}' <> '' then
      Origins := Origins + ',' + #13#10 + '    "chrome-extension://{#EdgeExtId}/"';

    SetArrayLength(ChromiumLines, 9);
    ChromiumLines[0] := '{';
    ChromiumLines[1] := '  "name": "com.mmunblock",';
    ChromiumLines[2] := '  "description": "Native Messaging Host fuer MMUnblock (Signiert)",';
    ChromiumLines[3] := '  "path": "' + HostPath + '",';
    ChromiumLines[4] := '  "type": "stdio",';
    ChromiumLines[5] := '  "allowed_origins": [';
    ChromiumLines[6] := Origins;
    ChromiumLines[7] := '  ]';
    ChromiumLines[8] := '}';

    if not SaveStringsToFile(ChromiumJsonPath, ChromiumLines, False) then
    begin
      Log('Fehler beim Erstellen der com.mmunblock.chromium.json');
    end;
  end;
end;
/////////////////////////////////////////////////////////////////////
// Funktion prüft, ob eine alte Version existiert und deinstalliert sie lautlos
/////////////////////////////////////////////////////////////////////
function GetUninstallString(): String;
var
  sUninstPath: String;
  sUninstallString: String;
begin
  sUninstPath := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + '{#SetupSetting("AppId")}' + '_is1';
  sUninstallString := '';
  
  // Erst im aktuellen Benutzer (HKCU) suchen
  if not RegQueryStringValue(HKCU, sUninstPath, 'UninstallString', sUninstallString) then
  begin
    // Falls nicht gefunden, im gesamten System (HKLM) suchen
    RegQueryStringValue(HKLM, sUninstPath, 'UninstallString', sUninstallString);
  end;
  
  Result := sUninstallString;
end;

function IsUpgrade(): Boolean;
begin
  Result := (GetUninstallString() <> '');
end;

function InitializeSetup(): Boolean;
var
  V: Integer;
  sUninstallString: String;
  sParameters: String;
begin
  Result := True;
  
  if IsUpgrade() then
  begin
    // Dem Benutzer kurz mitteilen, dass die alte Version entfernt wird
    // (Kann auch weggelassen werden, wenn es komplett unsichtbar sein soll)
    MsgBox('Eine ältere Version von MMUnblock Pro wurde gefunden. Diese wird nun automatisch deinstalliert, bevor die neue Version installiert wird.', mbInformation, MB_OK);
    
    sUninstallString := RemoveQuotes(GetUninstallString());
    sParameters := '/SILENT /NORESTART /SUPPRESSMSGBOXES';
    
    // Führt die alte unins000.exe im Hintergrund aus und wartet, bis sie fertig ist
    if Exec(sUninstallString, sParameters, '', SW_HIDE, ewWaitUntilTerminated, V) then
    begin
      // Optionale Verzögerung von 1 Sekunde, damit Windows die Dateisperren sicher aufhebt
      Sleep(1000);
    end;
  end;
end;