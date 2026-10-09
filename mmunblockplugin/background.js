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
function checkHost(openSetupTab) {
  chrome.runtime.sendNativeMessage(HOST_NAME, { ping: true }, () => {
    const err = chrome.runtime.lastError;
    const kind = err ? classifyHostError(err.message) : 'ok';
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

// Exakte Domain oder Subdomain (github.com trifft api.github.com, aber nicht github.com.evil.example)
function isDomainWhitelisted(domain, whitelist) {
  const host = (domain || '').toLowerCase();
  if (!host) return false;
  return whitelist.some((entry) => {
    const allowed = String(entry).trim().toLowerCase().replace(/^\*?\./, '');
    return allowed.length > 0 && (host === allowed || host.endsWith('.' + allowed));
  });
}

chrome.downloads.onChanged.addListener((delta) => {
  if (delta.state && delta.state.current === 'complete') {

    chrome.downloads.search({ id: delta.id }, (results) => {
      if (!results || !results[0]) return;

      const fileUrl = results[0].url;
      const filePath = results[0].filename;

      let domain = "";
      try {
        domain = new URL(fileUrl).hostname;
      } catch (e) {
        console.error("Ungültige URL", fileUrl);
      }

      chrome.storage.local.get(['whitelist'], async (storage) => {
        const whitelist = storage.whitelist || [];
        const isWhitelisted = isDomainWhitelisted(domain, whitelist);

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
            message: `Möchtest du diese Datei entsperren?\n${results[0].finalUrl || domain}`,
            buttons: [
              { title: '🔒 Jetzt entsperren' },
              { title: 'Ignorieren' }
            ],
            requireInteraction: true
          });
        }
      });
    });
  }
});

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
