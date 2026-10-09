chrome.storage.local.get(['whitelist'], (result) => {
  if (result.whitelist) {
    document.getElementById('whitelist').value = result.whitelist.join('\n');
  }
});

document.getElementById('save').addEventListener('click', () => {
  const text = document.getElementById('whitelist').value;
  const list = text.split('\n').map(line => line.trim()).filter(line => line.length > 0);
  
  chrome.storage.local.set({ whitelist: list }, () => {
    const fb = document.getElementById('feedback');
    fb.style.display = 'block';
    setTimeout(() => { fb.style.display = 'none'; }, 2000);
  });
});

// Windows-Komponente pruefen und bei Bedarf auf den Installer hinweisen
chrome.runtime.sendNativeMessage('com.mmunblock', { ping: true }, () => {
  const err = chrome.runtime.lastError;
  const msg = err ? err.message : '';
  const forbidden = /forbidden/i.test(msg);
  const missing = /not found|no such native application/i.test(msg);
  const warn = document.getElementById('hostwarn');
  if (missing || forbidden) {
    document.getElementById('hostmsg').textContent = forbidden
      ? 'Die Windows-Komponente kennt diese Erweiterung nicht. Bitte den aktuellen Installer ausführen.'
      : 'Die Windows-Komponente ist nicht installiert – ohne sie kann nichts entsperrt werden.';
    warn.style.display = 'block';
  } else {
    try { chrome.action.setBadgeText({ text: '' }); } catch (e) { }
  }
});
