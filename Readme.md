# MMUnblockPro 🚀

**MMUnblockPro** ist eine professionelle Windows-Erweiterung für Microsoft Edge, mit der du die NTFS-Zonenerkennung ("Mark of the Web") von heruntergeladenen Dateien vollautomatisch und direkt im Browser entfernen kannst. Schluss mit dem manuellen Rechtsklick -> "Zulassen" in den Dateieigenschaften!

Das Projekt besteht aus einer offiziellen Microsoft Edge-Erweiterung und einem im Hintergrund agierenden, via **Certum digital signierten** Windows-Dienst (Native Messaging Host).

---

## 🛠️ Installation

Da moderne Browser aus Sicherheitsgründen streng isoliert sind, besteht die Installation aus **zwei einfachen Schritten**:

### Schritt 1: Erweiterung in Microsoft Edge installieren
Hole dir das offizielle Browser-Plugin direkt aus dem Edge Add-on Store:
👉 **[Hier geht es zur Microsoft Edge Add-on Seite](#-dein-store-link-hier-)** *(Klicke dort auf "Abrufen")*

### Schritt 2: Windows-Komponente (Installer) herunterladen
Damit die Erweiterung mit deinem PC kommunizieren darf, lade dir unseren signierten Windows-Installer herunter:
👉 **[MMUnblockPro_Setup.exe herunterladen](https://github.com/manfred-mueller/MMUnBlockPro/releases/latest)**

*Mache einfach einen Doppelklick auf die heruntergeladene Setup-Datei. Der Installer richtet alle notwendigen Pfade und Registry-Einträge vollautomatisch ein.*

---

## 🔍 Wie es funktioniert

```
[ Microsoft Edge ] ──(Native Messaging)──> [ mmunblockhost.exe ] ──> [ mmunblock.exe (CLI) ]
(Erweiterung erkennt Download)             (Unsichtbarer Vermittler)    (Entsperrt die Datei via Win32-API)

```

1. **Edge-Plugin:** Registriert, wenn ein Download erfolgreich abgeschlossen wurde, und sendet den Dateipfad via *Native Messaging* an den Host.
2. **mmunblockhost.exe:** Nimmt das Signal von Edge entgegen und startet im Hintergrund blitzschnell das Core-Kommandozeilen-Tool.
3. **mmunblock.exe:** Entfernt den `Zone.Identifier`-Datenstrom (Alternative Data Stream) der Datei sauber über die Windows-API.

---

## 🔒 Sicherheit & Vertrauen

Da dieses Tool tief in das System eingreift, um Dateiblockaden zu lösen, steht Sicherheit an oberster Stelle:
* **Digital Signiert:** Alle ausführbaren Dateien (`.exe`) sowie der Installer selbst sind mit einem offiziellen **Certum Code Signing Zertifikat** ("Open Source Developer, Mueller Manfred") kryptografisch signiert. Dadurch wird der Windows SmartScreen-Filter nicht ausgelöst.
* **Open Source:** Der gesamte Quellcode ist einsehbar. Keine versteckte Telemetrie, keine Datenübertragung nach außen.
* **Rechte-Minimum:** Der Installer benötigt *keine* Administratorrechte (UAC), da er sich vollständig im Benutzerverzeichnis (`%localappdata%`) installiert.

---

## 💻 Für Entwickler (Lokaler Build)

Wenn du das Projekt selbst kompilieren oder modifizieren möchtest:

### Voraussetzungen
* [.NET 8.0 SDK](https://dotnet.microsoft.com/download)
* [Inno Setup Compiler](https://jrsoftware.org/isdl.php) (für den Bau des Installers)

### Build-Prozess
1. Klone das Repository.
2. Veröffentliche die beiden C#-Projekte als Single-File-Anwendungen:
   ```bash
   cd mmunblock
   dotnet publish -c Release
   cd ../mmunblockhost
   dotnet publish -c Release
   
```
3. Öffne die `installer.iss` in Inno Setup und klicke auf **Compile** (`Strg + F9`), um die `MMUnblockPro_Setup.exe` im Ordner `Output/` zu generieren.

---

## 📄 Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert – siehe die [LICENSE](LICENSE) Datei für Details.
