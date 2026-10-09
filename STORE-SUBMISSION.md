# Store-Einreichung MMUnblock Pro 1.4.1

Pakete (ohne `key`, geprüft): `dist\1.4.1\MMUnblockPro-1.4.1-chrome.zip` und `...-edge.zip`

## Texte (für beide Stores)

**Name:** MMUnblock Pro
**Kurzbeschreibung (max. 132 Zeichen):**
Entfernt die Windows-Download-Sperre (Mark of the Web) heruntergeladener Dateien – auf Wunsch per Klick oder automatisch per Whitelist.

**Detailbeschreibung (DE):**
MMUnblock Pro entfernt die Windows-Zonenmarkierung („Mark of the Web“) von Dateien, die Sie im Browser herunterladen – ohne Rechtsklick → Eigenschaften → „Zulassen“.

• Nach jedem Download erscheint eine Benachrichtigung: „Jetzt entsperren“ oder „Ignorieren“.
• Für vertrauenswürdige Domains (z. B. Ihren eigenen Server) können Sie eine Whitelist anlegen – diese Downloads werden automatisch entsperrt.
• Keine Telemetrie, keine Datenübertragung ins Internet. Open Source.

WICHTIG: Zusätzlich muss die kostenlose, signierte Windows-Komponente installiert werden (MMUnblockPro_Setup.exe, kein Administratorrecht nötig):
https://github.com/manfred-mueller/MMUnBlockPro/releases/latest

**Description (EN):**
MMUnblock Pro removes the Windows "Mark of the Web" from files you download in your browser – no more right-click → Properties → Unblock. Choose per download via notification, or auto-unblock downloads from domains on your whitelist. No telemetry, no network traffic, open source.
REQUIRED: install the free signed Windows helper (MMUnblockPro_Setup.exe, no admin rights needed): https://github.com/manfred-mueller/MMUnBlockPro/releases/latest

**Kategorie:** Productivity / Produktivität
**Sprache:** Deutsch (zusätzlich Englisch empfohlen)
**Website / Support:** https://github.com/manfred-mueller/MMUnBlockPro
**Datenschutz-URL:** https://github.com/manfred-mueller/MMUnBlockPro/blob/main/PRIVACY.md (PRIVACY.md vorher committen/pushen)

## Single Purpose (Chrome)
Entfernt nach Downloads die Windows-Zonenmarkierung der heruntergeladenen Datei über eine lokale Windows-Komponente.

## Begründung der Berechtigungen
- **downloads:** Erkennt abgeschlossene Downloads und liest Dateipfad und Quell-URL, um die richtige Datei zu entsperren und die Whitelist abzugleichen.
- **nativeMessaging:** Übergibt den Dateipfad an die lokal installierte Komponente (`com.mmunblock`), die die Zonenmarkierung entfernt. Ohne diese Berechtigung ist der einzige Zweck der Erweiterung nicht erfüllbar.
- **notifications:** Fragt nach jedem Download, ob die Datei entsperrt werden soll.
- **storage:** Speichert die vom Nutzer gepflegte Domain-Whitelist (local) und vorübergehend offene Benachrichtigungen (session).
- **Remote code:** Nein. Alle Skripte sind im Paket enthalten.

## Datenschutz-Angaben (Data-Usage-Formular)
- Gesammelte Daten: **keine** (Dateipfad/URL werden nur lokal verarbeitet, nichts wird übertragen).
- Bestätigungen: keine Datenweitergabe, kein Verkauf, keine Nutzung zu fremden Zwecken.

## Noch selbst zu erstellen (Pflicht)
- Screenshots 1280×800 oder 640×400 (mind. 1, besser 3: Benachrichtigung, Whitelist-Popup, entsperrte Datei)
- Chrome: kleine Werbekachel 440×280 (Marquee 1400×560 optional)
- Edge: Logo 300×300 (Icon 128 liegt vor), Screenshots 1280×800 oder 640×400

## Ablauf Chrome Web Store
1. https://chrome.google.com/webstore/devconsole → Neues Element → ZIP hochladen
2. Reiter „Store-Eintrag“, „Datenschutz“, „Verteilung“ (öffentlich oder nicht gelistet) ausfüllen
3. Reiter „Paket“: dort den **öffentlichen Schlüssel** kopieren. Damit die Extension-ID zum Installer passt, diesen Wert als `$DevKey` in Build-All.ps1 eintragen und `ChromeExtId` in der .iss auf die Store-ID setzen.
4. Zur Überprüfung einreichen (dauert meist einige Tage)

## Ablauf Edge Add-ons
1. https://partner.microsoft.com/dashboard/microsoftedge/overview (Programm ggf. einmalig anmelden)
2. Neue Erweiterung → ZIP hochladen → Verfügbarkeit, Eigenschaften, Store-Listing ausfüllen
3. Hinweise für Tester: „Needs the Windows helper MMUnblockPro_Setup.exe from GitHub releases; install it, then download any file from the internet to see the notification.“
4. Nach Veröffentlichung die Edge-ID in `EdgeExtId` (.iss) eintragen und Installer neu bauen

## Wichtig für die Prüfung
Die Erweiterung ist ohne die Windows-Komponente funktionslos. Das unbedingt in Beschreibung und Testhinweisen erwähnen, sonst droht Ablehnung wegen „nicht funktionsfähig“.
Seit 1.4.1 weist die Erweiterung selbst darauf hin: beim ersten Start öffnet sie die Installer-Seite (GitHub Releases), danach Hinweis per Benachrichtigung, Badge „!“ und Popup. Das in den Testhinweisen erwähnen.

## Nach der Veröffentlichung
1. Chrome-/Edge-Store-URL in `MMUnBlockPro.iss` (`ChromeStoreUrl`, `EdgeStoreUrl`) eintragen, außerdem `ChromeExtId`/`EdgeExtId` auf die Store-IDs setzen.
2. Links in der README ergänzen.
3. `Build-All.ps1` erneut laufen lassen, Installer neu veröffentlichen.
