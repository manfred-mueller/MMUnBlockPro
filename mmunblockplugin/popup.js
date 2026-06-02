chrome.storage.local.get(['whitelist'], (result) => {
  if (result.whitelist) {
    document.getElementById('whitelist').value = result.whitelist.join('\n');
  }
});

document.getElementById('save').addEventListener('click', () => {
  const text = document.getElementById('whitelist').value;
  const list = text.split('\n').map(line => line.trim()).filter(line => line.length > 0);
  
  chrome.storage.local.set({ whitelist: list }, () => {
    alert('Whitelist erfolgreich gespeichert!');
  });
});