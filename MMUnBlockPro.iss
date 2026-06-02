; ─── Inno Setup Definition für MMUnblockPro ──────────────────────────────────

[Setup]
AppName=MMUnblockPro
AppVersion=1.0
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
; 1. Den Registry-Pfad für Microsoft Edge Native Messaging im aktuellen Benutzerkonto (HKCU) anlegen
Root: HKCU; Subkey: "Software\Microsoft\Edge\NativeMessagingHosts\com.mmunblock"; ValueType: string; ValueData: "{app}\com.mmunblock.json"; Flags: uninsdeletekey

[Code]
// 2. Das JSON-Manifest dynamisch während der Installation schreiben
procedure CurStepChanged(CurStep: TSetupStep);
var
  JsonLines: TArrayOfString;
  JsonFilePath: String;
  HostPath: String;
begin
  if CurStep = ssPostInstall then
  begin
    JsonFilePath := ExpandConstant('{app}\com.mmunblock.json');
    
    // Den Pfad holen und alle einfachen Backslashes durch doppelte Backslashes ersetzen
    HostPath := ExpandConstant('{app}\mmunblockhost.exe');
    StringChangeEx(HostPath, '\', '\\', True);
    
    SetArrayLength(JsonLines, 10);
    JsonLines[0] := '{';
    JsonLines[1] := '  "name": "com.mmunblock",';
    JsonLines[2] := '  "description": "Native Messaging Host für MMUnblock (Signiert)",';
    JsonLines[3] := '  "path": "' + HostPath + '",';
    JsonLines[4] := '  "type": "stdio",';
    JsonLines[5] := '  "allowed_origins": [';
    JsonLines[6] := '    "extension://occhlpkljlaemgemhhdcafacjcmigbcg/"';
    JsonLines[7] := '  ]';
    JsonLines[8] := '}';

    if not SaveStringsToFile(JsonFilePath, JsonLines, False) then
    begin
      Log('Fehler beim Erstellen der com.mmunblock.json');
    end;
  end;
end;