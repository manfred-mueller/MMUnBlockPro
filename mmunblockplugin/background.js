// MMUnblock Pro - Firefox / Chrome / Edge
// Der Service Worker (Chrome/Edge) wird nach kurzer Leerlaufzeit beendet.
// Zuordnung Benachrichtigung -> Dateipfad liegt daher in storage.session
// und nicht nur im Arbeitsspeicher.

const PENDING_KEY = 'pendingNotifications';

// Windows-Komponente (Native Messaging Host)
const HOST_NAME = 'com.mmunblock';
const SETUP_URL = 'https://github.com/manfred-mueller/MMUnBlockPro/releases/latest';
const HOST_NOTIFICATION_ID = 'host-missing';
const HOST_NOTIFY_INTERVAL_MS = 60 * 60 * 1000; // Hinweis hoechstens einmal pro Stunde
let lastHostNotice = 0;

// Ordnet die Fehlermeldung von sendNativeMessage ein:
// 'missing'   = Host nicht installiert (Chrome/Edge: "...host not found", Firefox: "No such native application")
// 'forbidden' = Host vorhanden, erlaubt diese Erweiterungs-ID aber nicht
// 'error'     = sonstiger Fehler (der Host ist aber vorhanden, z. B. "Native host has exited")
function classifyHostError(message) {
  const m = message || '';
  if (/forbidden/i.test(m)) return 'forbidden';
  if (/not found|no such native application/i.test(m)) return 'missing';
  return 'error';
}

function setHostBadge(problem) {
  try {
    chrome.action.setBadgeText({ text: problem ? '!' : '' });
    if (problem) chrome.action.setBadgeBackgroundColor({ color: '#d32f2f' });
  } catch (e) { /* Badge ist nur ein Komfort */ }
}

function notifyHostProblem(kind) {
  const now = Date.now();
  if (now - lastHostNotice < HOST_NOTIFY_INTERVAL_MS) return;
  lastHostNotice = now;
  const forbidden = kind === 'forbidden';
  chrome.notifications.create(HOST_NOTIFICATION_ID, {
    type: 'basic',
    iconUrl: chrome.runtime.getURL('icons/icon-128.png'),
    title: 'MMUnblock Pro: Windows-Komponente fehlt',
    message: forbidden
      ? 'Die installierte Windows-Komponente kennt diese Erweiterung nicht. Bitte den aktuellen Installer ausführen.'
      : 'Zum Entsperren wird zusätzlich der kostenlose Windows-Installer benötigt.',
    buttons: [{ title: 'Installer herunterladen' }]
  });
}

// Prueft, ob der Host erreichbar ist. Ein bestehender Host beendet sich bei
// der Test-Nachricht ohne Antwort ("Native host has exited") - das zaehlt als vorhanden.
function probeHost(callback) {
  chrome.runtime.sendNativeMessage(HOST_NAME, { ping: true }, () => {
    const err = chrome.runtime.lastError;
    callback(err ? classifyHostError(err.message) : 'ok', err ? err.message : '');
  });
}

function checkHost(openSetupTab) {
  probeHost((kind) => {
    const problem = kind === 'missing' || kind === 'forbidden';
    setHostBadge(problem);
    if (problem && openSetupTab) chrome.tabs.create({ url: SETUP_URL });
  });
}

chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === 'install') checkHost(true);
});

chrome.runtime.onStartup.addListener(() => checkHost(false));

function getPending() {
  return new Promise((resolve) => {
    chrome.storage.session.get([PENDING_KEY], (s) => resolve(s[PENDING_KEY] || {}));
  });
}

function setPending(map) {
  return new Promise((resolve) => {
    chrome.storage.session.set({ [PENDING_KEY]: map }, resolve);
  });
}

async function addPending(id, filePath) {
  const map = await getPending();
  map[id] = filePath;
  await setPending(map);
}

async function takePending(id) {
  const map = await getPending();
  const filePath = map[id];
  if (id in map) {
    delete map[id];
    await setPending(map);
  }
  return filePath;
}

// Eintrag: "github.com" (Domain inkl. Subdomains) oder "github.com/benutzer/" (Pfad-Präfix, endet mit /)
function parseWhitelistEntry(entry) {
  const e = String(entry).trim().toLowerCase().replace(/^\*?\./, '');
  const slash = e.indexOf('/');
  if (slash === -1) return { host: e, path: '' };
  return { host: e.slice(0, slash), path: e.slice(slash) };
}

// Passt die URL zum Eintrag? Domain-Teil: exakt oder Subdomain. Pfad-Teil: nur an Segmentgrenzen.
function urlMatchesEntry(urlString, entry) {
  let u;
  try { u = new URL(urlString); } catch (e) { return false; }
  const { host, path } = parseWhitelistEntry(entry);
  if (!host) return false;
  const uh = u.hostname.toLowerCase();
  if (!(uh === host || uh.endsWith('.' + host))) return false;
  if (path === '') return true;
  const p = path.endsWith('/') ? path : path + '/';
  const pn = u.pathname.toLowerCase();
  return pn.startsWith(p) || pn === p.slice(0, -1);
}

// GitHub leitet Release-Downloads auf diese Hosts weiter. Sie gelten nur für Pfad-Einträge auf github.com.
const GITHUB_RELEASE_HOSTS = ['release-assets.githubusercontent.com', 'objects.githubusercontent.com'];

function isGithubReleaseHost(urlString) {
  try {
    return GITHUB_RELEASE_HOSTS.includes(new URL(urlString).hostname.toLowerCase());
  } catch (e) {
    return false;
  }
}

// Domain-Einträge: wie bisher nur die Ausgangs-URL. Pfad-Einträge: Ausgangs-URL muss passen,
// und die finale URL (nach Weiterleitungen) muss passen ODER auf einen GitHub-Release-Host zeigen (nur bei github.com-Pfaden).
function isWhitelistedDownload(item, whitelist) {
  const origin = item.url || '';
  const finalUrl = item.finalUrl || origin;
  return whitelist.some((entry) => {
    const { host, path } = parseWhitelistEntry(entry);
    if (path === '') return urlMatchesEntry(origin, entry);
    if (!urlMatchesEntry(origin, entry)) return false;
    if (urlMatchesEntry(finalUrl, entry)) return true;
    return host === 'github.com' && isGithubReleaseHost(finalUrl);
  });
}

// Fertiger Download: Zuerst pruefen, ob die Windows-Komponente erreichbar ist.
// Fehlt sie, wird NICHT gefragt, ob die Datei entsperrt werden soll (das ginge ohnehin nicht),
// sondern nur auf den Installer hingewiesen. Der Installer selbst loest keinen Hinweis aus.
chrome.downloads.onChanged.addListener((delta) => {
  if (!(delta.state && delta.state.current === 'complete')) return;

  chrome.downloads.search({ id: delta.id }, (results) => {
    if (!results || !results[0]) return;
    const item = results[0];

    probeHost((kind) => {
      if (kind === 'missing' || kind === 'forbidden') {
        setHostBadge(true);
        if (!/MMUnblockPro_Setup/i.test(item.filename || '')) notifyHostProblem(kind);
        return;
      }
      setHostBadge(false);
      handleCompletedDownload(delta, item);
    });
  });
});

function handleCompletedDownload(delta, item) {
  const fileUrl = item.url;
  const filePath = item.filename;

  let domain = "";
  try {
    domain = new URL(fileUrl).hostname;
  } catch (e) {
    console.error("Ungültige URL", fileUrl);
  }

  chrome.storage.local.get(['whitelist'], async (storage) => {
    const whitelist = storage.whitelist || [];
    const isWhitelisted = isWhitelistedDownload(item, whitelist);

    if (isWhitelisted) {
      console.log(`Vollautomatisch entsperrt (Whitelist): ${domain}`);
      triggerNativeUnblock(filePath);
    } else {
      const notificationId = 'unblock-' + delta.id;
      await addPending(notificationId, filePath);

      chrome.notifications.create(notificationId, {
        type: 'basic',
        iconUrl: chrome.runtime.getURL('icons/icon-128.png'),
        title: 'Download abgeschlossen',
        message: `Möchtest du diese Datei entsperren?\n${item.finalUrl || domain}`,
        buttons: [
          { title: '🔒 Jetzt entsperren' },
          { title: 'Ignorieren' }
        ],
        requireInteraction: true
      });
    }
  });
}

chrome.notifications.onClicked.addListener((notificationId) => {
  if (notificationId === HOST_NOTIFICATION_ID) {
    chrome.tabs.create({ url: SETUP_URL });
    chrome.notifications.clear(notificationId);
  }
});

chrome.notifications.onButtonClicked.addListener(async (notificationId, buttonIndex) => {
  if (notificationId === HOST_NOTIFICATION_ID) {
    if (buttonIndex === 0) chrome.tabs.create({ url: SETUP_URL });
    chrome.notifications.clear(notificationId);
    return;
  }
  const filePath = await takePending(notificationId);
  if (buttonIndex === 0 && filePath) {
    triggerNativeUnblock(filePath);
  }
  chrome.notifications.clear(notificationId);
});

chrome.notifications.onClosed.addListener((notificationId) => {
  takePending(notificationId);
});

function triggerNativeUnblock(filePath) {
  chrome.runtime.sendNativeMessage(
    'com.mmunblock',
    { filePath: filePath },
    (response) => {
      if (chrome.runtime.lastError) {
        const message = chrome.runtime.lastError.message;
        console.error("Native Messaging Fehler:", message);
        const kind = classifyHostError(message);
        if (kind === 'missing' || kind === 'forbidden') {
          setHostBadge(true);
          notifyHostProblem(kind);
        }
      } else {
        console.log("Erfolgreich an C# übermittelt. Antwort:", response);
        setHostBadge(false);
      }
    }
  );
}
