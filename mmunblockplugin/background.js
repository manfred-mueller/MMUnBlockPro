const activeNotifications = new Map();

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

      chrome.storage.local.get(['whitelist'], (storage) => {
        const whitelist = storage.whitelist || [];
        const isWhitelisted = whitelist.some(allowed => domain.includes(allowed));

        if (isWhitelisted) {
          console.log(`Vollautomatisch entsperrt (Whitelist): ${domain}`);
          triggerNativeUnblock(filePath);
        } else {
          const notificationId = 'unblock-' + delta.id;
          activeNotifications.set(notificationId, filePath);

          chrome.notifications.create(notificationId, {
            type: 'basic',
            iconUrl: 'icon.png', 
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

chrome.notifications.onButtonClicked.addListener((notificationId, buttonIndex) => {
  if (buttonIndex === 0) { 
    const filePath = activeNotifications.get(notificationId);
    if (filePath) {
      triggerNativeUnblock(filePath);
    }
  }
  chrome.notifications.clear(notificationId);
  activeNotifications.delete(notificationId);
});

chrome.notifications.onClosed.addListener((notificationId) => {
  activeNotifications.delete(notificationId);
});

function triggerNativeUnblock(filePath) {
  chrome.runtime.sendNativeMessage(
    'com.mmunblock',
    { filePath: filePath },
    (response) => {
      if (chrome.runtime.lastError) {
        console.error("Native Messaging Fehler:", chrome.runtime.lastError.message);
      } else {
        console.log("Erfolgreich an C# übermittelt. Antwort:", response);
      }
    }
  );
}