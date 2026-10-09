# MMUnblockPro 🚀

**MMUnblockPro** ist eine professionelle Windows-Erweiterung für Mozilla Firefox, Google Chrome und Microsoft Edge, mit der du die NTFS-Zonenerkennung ("Mark of the Web") von heruntergeladenen Dateien vollautomatisch und direkt im Browser entfernen kannst. Schluss mit dem manuellen Rechtsklick -> "Zulassen" in den Dateieigenschaften!

Das Projekt besteht aus einer Browser-Erweiterung (Firefox, Chrome, Edge) und einem im Hintergrund agierenden, via **Certum digital signierten** Windows-Dienst (Native Messaging Host).

---

## 🛠️ Installation

Die Erweiterung braucht zusätzlich eine kleine Windows-Komponente (Native Messaging Host), die das Entsperren übernimmt. Am einfachsten startest du deshalb mit dem Installer.

### Schritt 1: Windows-Komponente (Installer) herunterladen
👉 **[MMUnblockPro_Setup.exe herunterladen](https://github.com/manfred-mueller/MMUnBlockPro/releases/latest)**

*Doppelklick auf die Setup-Datei genügt, Administratorrechte sind nicht nötig. Der Installer richtet alle Pfade und Registry-Einträge für Firefox, Chrome und Edge ein. Am Ende bietet er an, die Erweiterung direkt im jeweils installierten Browser zu öffnen.*

### Schritt 2: Erweiterung im Browser installieren
**Mozilla Firefox:** 👉 **[Firefox Add-on Seite (AMO)](https://addons.mozilla.org/de/firefox/addon/mmunblock-pro/)** *(dort auf "Zu Firefox hinzufügen" klicken)*

**Google Chrome / Microsoft Edge:** Die Erweiterung wird über den Chrome Web Store bzw. die Edge-Add-ons-Seite bereitgestellt (nicht gelistet, nur per Link erreichbar); die Links folgen nach der Veröffentlichung. Bis dahin lässt sie sich aus dem Release-Paket (`MMUnblockPro-<Version>-chrome.zip` bzw. `-edge.zip`) als entpackte Erweiterung laden.

> **Hinweis:** Wurde nur die Erweiterung installiert, weist sie selbst darauf hin: Beim ersten Start öffnet sie die Download-Seite des Installers, danach zeigt sie bei Bedarf ein rotes „!“ am Symbol, eine Benachrichtigung und einen Hinweis im Popup.

---

## 🔍 Wie es funktioniert

```
[ Firefox / Chrome / Edge ] ──(Native Messaging)──> [ mmunblockhost.exe ] ──> [ mmunblock.exe (CLI) ]
(Erweiterung erkennt Download)              (Unsichtbarer Vermittler)    (Entsperrt die Datei via Win32-API)

```

1. **Browser-Erweiterung:** Registriert, wenn ein Download erfolgreich abgeschlossen wurde, und sendet den Dateipfad via *Native Messaging* an den Host.
2. **mmunblockhost.exe:** Nimmt das Signal vom Browser entgegen und startet im Hintergrund blitzschnell das Core-Kommandozeilen-Tool.
3. **mmunblock.exe:** Entfernt den `Zone.Identifier`-Datenstrom (Alternative Data Stream) der Datei sauber über die Windows-API.

---

## 🔒 Sicherheit & Vertrauen

Da dieses Tool tief in das System eingreift, um Dateiblockaden zu lösen, steht Sicherheit an oberster Stelle:
* **Digital Signiert:** Alle ausführbaren Dateien (`.exe`) sowie der Installer selbst sind mit einem offiziellen **Certum Code Signing Zertifikat** ("Open Source Developer, Mueller Manfred") kryptografisch signiert. Dadurch wird der Windows SmartScreen-Filter nicht ausgelöst.
* **Open Source:** Der gesamte Quellcode ist einsehbar. Keine versteckte Telemetrie, keine Datenübertragung nach außen (`data_collection_permissions` ist im Manifest deaktiviert).
* **Rechte-Minimum:** Der Installer benötigt *keine* Administratorrechte (UAC), da er sich vollständig im Benutzerverzeichnis (`%localappdata%`) installiert.

---

## 💻 Für Entwickler (Lokaler Build & Test)

### Aufbau der Erweiterung
`mmunblockplugin\manifest.base.json` enthält nur die gemeinsamen Teile. Das Build-Skript erzeugt daraus pro Browser ein eigenes Manifest (Firefox: `gecko`-Einstellungen und `background.scripts`; Chrome/Edge: `background.service_worker`), damit keine browserfremden Schlüssel enthalten sind. Die Version wird nur in `manifest.base.json` gepflegt.

### Voraussetzungen
* [.NET 8.0 SDK](https://dotnet.microsoft.com/download)
* [Inno Setup Compiler](https://jrsoftware.org/isdl.php) (für den Installer)
* [web-ext](https://github.com/mozilla/web-ext) (`npm install --global web-ext`)
* `signtool.exe` und ein Code-Signing-Zertifikat (optional, mit `-SkipExeSign` übersprungen)
* Für die Firefox-Signierung die Umgebungsvariablen `AMO-Key` und `AMO-Secret`

### Build-Prozess
```powershell
# Nur die Erweiterungs-Ordner erzeugen (build\firefox, build\chrome, build\edge):
.\Build-All.ps1 -Dev

# Kompletter Build: Lint, Store-Pakete, XPI, EXEs, Installer -> dist\<Version>\
.\Build-All.ps1
```
Einzelne Schritte lassen sich mit `-SkipFirefoxSign`, `-SkipExeBuild`, `-SkipExeSign` und `-SkipInstaller` abschalten.

### Lokales Testen der Erweiterung
* **Firefox:** `about:debugging` → "Diesen Firefox" → "Temporäres Add-on laden..." → `build\firefox\manifest.json` wählen.
* **Chrome:** `chrome://extensions` → Entwicklermodus → "Entpackte Erweiterung laden" → Ordner `build\chrome` wählen.
* **Edge:** `edge://extensions` → Entwicklermodus → "Entpackte Erweiterung laden" → Ordner `build\edge` wählen.

Die Sideload-Ordner für Chrome und Edge enthalten einen festen `key`, damit die Extension-ID stabil bleibt (siehe `ChromeExtId` in `MMUnBlockPro.iss`). Nach der Veröffentlichung im Edge-Add-ons-Store muss die dort vergebene ID in `EdgeExtId` eingetragen werden.

---

## 📄 Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert – siehe die [LICENSE](LICENSE) Datei für Details.
