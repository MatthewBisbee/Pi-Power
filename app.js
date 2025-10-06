const btn = document.getElementById('power');
const statusEl = document.getElementById('status');
const card = document.getElementById('card-power');

btn.addEventListener('click', async () => {
  btn.disabled = true;

  // reveal the status line and clear previous state
  statusEl.textContent = 'Sending...';
  statusEl.classList.add('show');
  statusEl.classList.remove('ok','err');

  try {
    const r = await fetch('/press', { method: 'POST' });
    if (r.ok) {
      statusEl.textContent = 'OK';
      statusEl.classList.add('ok');
      statusEl.classList.remove('err');

      // celebratory flash (optional, if you kept it)
      card.classList.remove('flash');
      void card.offsetWidth;
      card.classList.add('flash');
    } else {
      statusEl.textContent = 'Error ' + r.status;
      statusEl.classList.add('err');
      statusEl.classList.remove('ok');
    }
  } catch {
    statusEl.textContent = 'Network error';
    statusEl.classList.add('err');
    statusEl.classList.remove('ok');
  } finally {
    setTimeout(() => { btn.disabled = false; }, 10000); // 10s lockout
  }
});