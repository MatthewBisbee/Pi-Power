// Existing elements
const btn = document.getElementById('power');
const statusEl = document.getElementById('status');
const card = document.getElementById('card-power');

// Status lights + countdown
const dotTail = document.getElementById('dot-tailscale');
const dotUnraid = document.getElementById('dot-unraid');
const ring = document.getElementById('ring-fg');
const ringText = document.getElementById('ring-text');
const bootHint = document.getElementById('boot-hint');

const CIRC = 339.292;      // 2πr with r=54
let pollTimer = null;
let tickTimer = null;
let etaSeconds = 260;
let bootStartMs = null;

// ---- helpers ----
function setDot(el, state) {
  if (!el) return;
  el.classList.remove('ok','warn','bad');
  if (state) el.classList.add(state);
}
function fmtMMSS(sec) {
  sec = Math.max(0, Math.ceil(sec));
  const m = Math.floor(sec/60), s = sec % 60;
  return (m<10?'0':'')+m+':'+(s<10?'0':'')+s;
}
function drawProgress(p) {
  const off = CIRC * (1 - Math.max(0, Math.min(1, p)));
  if (ring) ring.style.strokeDashoffset = String(off);
}
function startTicker() {
  if (tickTimer) clearInterval(tickTimer);
  tickTimer = setInterval(() => {
    if (!bootStartMs || !etaSeconds || !ringText) return;
    const now = Date.now();
    const elapsed = (now - bootStartMs) / 1000;
    const remaining = Math.max(0, etaSeconds - elapsed);
    ringText.textContent = fmtMMSS(remaining);
    drawProgress(Math.min(1, elapsed / etaSeconds));
  }, 250);
}

// Poll server health continuously (even if nobody pressed the button)
async function poll() {
  try {
    const r = await fetch('/api/unraid-health', { cache: 'no-store' });
    if (!r.ok) throw new Error('health ' + r.status);
    const j = await r.json();

    // sync timer anchor & ETA from server
    if (j.bootStart) {
      if (bootStartMs !== j.bootStart) {
        bootStartMs = j.bootStart;
        etaSeconds = j.etaSeconds || 260;
        if (bootHint) bootHint.textContent = 'Estimated boot window';
        startTicker();
      }
    } else {
      // no active boot window
      bootStartMs = null;
      drawProgress(0);
      if (ringText) ringText.textContent = '--:--';
      if (bootHint) bootHint.textContent = 'Waiting for boot window…';
    }

    // lights
    setDot(dotTail, j.tailscaleOnline ? 'ok' : 'bad');
    if (j.cloudflareOk) {
      setDot(dotUnraid, 'ok');
      if (ringText) ringText.textContent = 'READY';
      drawProgress(1);
      if (bootHint) bootHint.textContent = 'Unraid is ready';
    } else {
      setDot(dotUnraid, j.cloudflare1033 ? 'warn' : 'bad');
    }
  } catch (e) {
    // server unreachable or error
    setDot(dotTail, 'bad');
    setDot(dotUnraid, 'bad');
  }
}

function startPolling() {
  if (pollTimer) clearInterval(pollTimer);
  poll(); // immediate
  pollTimer = setInterval(poll, 3000);
}

// Always poll, regardless of button state
startPolling();

/* ---------------- existing /press flow (unchanged semantics) ---------------- */
btn.addEventListener('click', async () => {
  btn.disabled = true;

  // show status line
  statusEl.textContent = 'Sending...';
  statusEl.classList.add('show');
  statusEl.classList.remove('ok','err');

  try {
    const r = await fetch('/press', { method: 'POST' });
    if (r.ok) {
      statusEl.textContent = 'Sent.';
      statusEl.classList.add('ok');
      statusEl.classList.remove('err');

      // Tell server to start the shared countdown
      try {
        const m = await fetch('/api/boot-mark', { method: 'POST' });
        if (m.ok) {
          const j = await m.json();
          bootStartMs = j.bootStart;
          etaSeconds = j.etaSeconds || 260;
          if (bootHint) bootHint.textContent = 'Estimated boot window';
          startTicker();
        }
      } catch {}

      // success flash on the card
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
