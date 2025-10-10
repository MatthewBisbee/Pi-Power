#!/usr/bin/env bash
set -euo pipefail

# ---------- Locate repo root (works if script is at root or in web/) ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "${SCRIPT_DIR}/backend" && -d "${SCRIPT_DIR}/web" ]]; then
  ROOT_DIR="${SCRIPT_DIR}"
elif [[ -d "${SCRIPT_DIR}/../backend" && -d "${SCRIPT_DIR}/../web" ]]; then
  ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
  echo "Error: cannot find repo root containing 'web/' and 'backend/' near this script." >&2
  exit 1
fi

WEB_DIR="${ROOT_DIR}/web"
BACKEND_DIR="${ROOT_DIR}/backend"

# ---------- Remote host + paths ----------
PI_HOST="chungy@ssh-pi.davisbisbee.com"
SSH_PROXY='ssh -o ProxyCommand="cloudflared access ssh --hostname ssh-pi.davisbisbee.com"'
SCP_CMD=(scp -o ProxyCommand="cloudflared access ssh --hostname ssh-pi.davisbisbee.com")
SSH_CMD=(ssh -o ProxyCommand="cloudflared access ssh --hostname ssh-pi.davisbisbee.com")

REMOTE_HTML="/var/www/html"
REMOTE_APP_DIR="/home/chungy/powerbtn"
REMOTE_APP="${REMOTE_APP_DIR}/app.py"
REMOTE_POWER_SCRIPT="/home/chungy/poweron.sh"
REMOTE_VENV="/home/chungy/powerbtn-venv"
REMOTE_NGX_AVAIL="/etc/nginx/sites-available/pi"
REMOTE_NGX_ENABLED="/etc/nginx/sites-enabled/pi"

# ---------- 1) Commit & push ----------
if git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "${ROOT_DIR}" add -A
  if ! git -C "${ROOT_DIR}" diff --cached --quiet; then
    git -C "${ROOT_DIR}" commit -m "deploy: $(date -u +'%Y-%m-%d %H:%M:%S') UTC"
  fi
  git -C "${ROOT_DIR}" push -u origin HEAD
else
  echo "Note: not a Git repo; skipping commit/push."
fi

# ---------- 2) Web: rsync web/ → /var/www/html ----------
rsync -e "${SSH_PROXY}" -avz --delete \
  --exclude '.git' --exclude '.gitignore' --exclude '.DS_Store' \
  "${WEB_DIR}/" "${PI_HOST}:${REMOTE_HTML}/"

# ---------- 3) Backend: ensure app dir exists ----------
"${SSH_CMD[@]}" "${PI_HOST}" "mkdir -p '${REMOTE_APP_DIR}'"

# ---------- 4) Backend: copy single files ----------
# app.py -> /home/chungy/powerbtn/app.py
if [[ -f "${BACKEND_DIR}/app.py" ]]; then
  "${SCP_CMD[@]}" "${BACKEND_DIR}/app.py" "${PI_HOST}:${REMOTE_APP}"
fi

# poweron.sh -> /home/chungy/poweron.sh (0755)
if [[ -f "${BACKEND_DIR}/poweron.sh" ]]; then
  "${SCP_CMD[@]}" "${BACKEND_DIR}/poweron.sh" "${PI_HOST}:${REMOTE_POWER_SCRIPT}"
  "${SSH_CMD[@]}" "${PI_HOST}" "chmod 0755 '${REMOTE_POWER_SCRIPT}'"
fi

# nginx pi.conf -> upload to /tmp, sudo install to sites-available, link, test, reload
PUSHED_NGINX=0
if [[ -f "${BACKEND_DIR}/pi.conf" ]]; then
  "${SCP_CMD[@]}" "${BACKEND_DIR}/pi.conf" "${PI_HOST}:/tmp/pi.conf"
  "${SSH_CMD[@]}" "${PI_HOST}" "\
    set -e; \
    sudo install -m 0644 /tmp/pi.conf '${REMOTE_NGX_AVAIL}'; \
    if [ ! -e '${REMOTE_NGX_ENABLED}' ]; then sudo ln -s '${REMOTE_NGX_AVAIL}' '${REMOTE_NGX_ENABLED}'; fi; \
    sudo nginx -t; \
    sudo systemctl reload nginx; \
    rm -f /tmp/pi.conf"
  PUSHED_NGINX=1
fi

# ---------- 5) Backend: venv & requirements (only if requirements.txt exists) ----------
if [[ -f "${BACKEND_DIR}/requirements.txt" ]]; then
  "${SSH_CMD[@]}" "${PI_HOST}" "\
    if [ ! -d '${REMOTE_VENV}' ]; then python3 -m venv '${REMOTE_VENV}'; fi; \
    '${REMOTE_VENV}/bin/pip' install --upgrade pip >/dev/null 2>&1 || true"
  "${SSH_CMD[@]}" "${PI_HOST}" "cat > /tmp/req.txt" < "${BACKEND_DIR}/requirements.txt"
  "${SSH_CMD[@]}" "${PI_HOST}" "'${REMOTE_VENV}/bin/pip' install -r /tmp/req.txt"
  "${SSH_CMD[@]}" "${PI_HOST}" "rm -f /tmp/req.txt"
fi

# ---------- 6) Backend: respring backend process safely ----------
# Prefer systemd (powerbtn.service). Otherwise, kill+nohup Waitress.
"${SSH_CMD[@]}" "${PI_HOST}" "\
  if systemctl list-unit-files | grep -q '^powerbtn\\.service'; then
    sudo systemctl daemon-reload
    sudo systemctl restart powerbtn.service
  else
    pkill -f 'waitress-serve --listen=127.0.0.1:8080' || true
    nohup '${REMOTE_VENV}/bin/waitress-serve' --listen=127.0.0.1:8080 app:app --call >/dev/null 2>&1 &
    sleep 1
  fi"

# ---------- 7) Helpful summary ----------
"${SSH_CMD[@]}" "${PI_HOST}" "\
  echo '--- DEPLOY SUMMARY ---'; \
  echo 'app.py     -> ${REMOTE_APP}'; head -n2 '${REMOTE_APP}' || true; \
  echo 'poweron.sh -> ${REMOTE_POWER_SCRIPT}'; ls -l '${REMOTE_POWER_SCRIPT}' || true; \
  if [ ${PUSHED_NGINX} -eq 1 ]; then \
    echo 'nginx: reloaded'; \
    echo 'pi.conf paths:'; sudo ls -l '${REMOTE_NGX_AVAIL}' '${REMOTE_NGX_ENABLED}' || true; \
  else \
    echo 'nginx: unchanged'; \
  fi; \
  pgrep -af 'waitress-serve --listen=127.0.0.1:8080' || echo 'waitress not detected'; \
  ss -ltnp 2>/dev/null | grep 127.0.0.1:8080 || true; \
  echo '----------------------'"

echo "Deployed → https://pi.davisbisbee.com"