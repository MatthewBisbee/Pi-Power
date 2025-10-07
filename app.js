// Existing elements (keep ids/classes unchanged)
const btn = document.getElementById('power');
const statusEl = document.getElementById('status');
const card = document.getElementById('card-power');

// NEW: status lights + countdown elements
const dotTail = document.getElementById('dot-tailscale');
const dotUnraid = document.getElementById('dot-unraid');
const ring = document.getElementById('ring-fg');
const ringText = document.getElementById('ring-text');
const bootHint = document.getElementById('boot-hint');

// Countdown + polling config
const CIRC = 339.292;       // 2πr for r=54
const ETA_SECONDS = 260;     // 4m20s default
let bootStartMs = readBootStartCookie();
let tickTimer = null;
let pollTimer = null;

// --- helpers ---
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
  if (!ringText) return;
  if (tickTimer) clearInterval(tickTimer);
  tickTimer = setInterval(() => {
    if (!bootStartMs) return;
    const now = Date.now();
    const elapsed = (now - bootStartMs) / 1000;
    const remaining = Math.max(0, ETA_SECONDS - elapsed);
    ringText.textContent = fmtMMSS(remaining);
    drawProgress(Math.min(1, elapsed / ETA_SECONDS));
  }, 250);
}
function writeBootStartCookie(ms) {
  const exp = new Date(Date.now() + 10*60*1000).toUTCString();
  document.cookie = 'bootStartMs=' + ms + '; expires=' + exp + '; path=/; SameSite=Lax';
}
function readBootStartCookie() {
  const m = document.cookie.match(/(?:^|;\s*)bootStartMs=(\d+)/);
  return m ? parseInt(m[1], 10) : null;
}

// Cloudflare-based readiness probe (CORS-free via image)
function checkUnraidViaIcon() {
  return new Promise(resolve => {
    const img = new Image();
    img.onload = () => resolve(true);   // served a valid icon → ready
    img.onerror = () => resolve(false); // 1033 or not up yet
    img.src = 'https://unraid.davisbisbee.com/favicon.ico?ts=' + Date.now();
  });
}

async function poll() {
  try {
    const ok = await checkUnraidViaIcon();
    if (ok) {
      setDot(dotUnraid, 'ok');
      if (ringText) ringText.textContent = 'READY';
      drawProgress(1);
      if (bootHint) bootHint.textContent = 'Unraid is ready';
    } else {
      setDot(dotUnraid, 'warn'); // warming / 1033 / not ready
      // If we detect warming and have no anchor yet, start an estimated window
      if (!bootStartMs) {
        bootStartMs = Date.now();
        writeBootStartCookie(bootStartMs);
        if (bootHint) bootHint.textContent = 'Estimated boot window';
        startTicker();
      }
    }
  } catch {
    setDot(dotUnraid, 'bad');
  }

  // Tailscale light (placeholder). We keep it neutral (gray) until you add
  // a tiny server probe; no server changes requested right now.
}

function startPolling() {
  if (pollTimer) clearInterval(pollTimer);
  poll(); // immediate
  pollTimer = setInterval(poll, 3000);
}

// If a boot window already exists (cookie), reflect it immediately
if (bootStartMs) {
  if (bootHint) bootHint.textContent = 'Estimated boot window';
  startTicker();
}
startPolling();

/* ---------------- existing /press flow (kept intact) ---------------- */
btn.addEventListener('click', async () => {
  btn.disabled = true;

  // reveal the status line and clear previous state
  statusEl.textContent = 'Sending...';
  statusEl.classList.add('show');
  statusEl.classList.remove('ok','err');

  try {
    const r = await fetch('/press', { method: 'POST' });
    if (r.ok) {
      statusEl.textContent = 'Sent.';
      statusEl.classList.add('ok');
      statusEl.classList.remove('err');

      // Anchor a shared (per-origin) boot window
      bootStartMs = Date.now();
      writeBootStartCookie(bootStartMs);
      if (bootHint) bootHint.textContent = 'Estimated boot window';
      startTicker();

      // success flash on the power card
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