#!/usr/bin/env bash
set -euo pipefail

# -------- Settings --------
PI_HOST="chungy@ssh-pi.davisbisbee.com"

# Cloudflared for ALL SSH-family ops
SSH_CMD='ssh -o ProxyCommand="cloudflared access ssh --hostname ssh-pi.davisbisbee.com"'
export RSYNC_RSH="${SSH_CMD}"

# Remote paths
REMOTE_HTML="/var/www/html"
REMOTE_APP_DIR="/home/chungy/powerbtn"
REMOTE_VENV="/home/chungy/powerbtn-venv"
REMOTE_POWER_SCRIPT="/home/chungy/poweron.sh"
REMOTE_NGX_AVAIL="/etc/nginx/sites-available/pi"
REMOTE_NGX_ENABLED="/etc/nginx/sites-enabled/pi"

# Local paths
WEB_DIR="./web"
BACKEND_DIR="./backend"

# -------- 1) Commit & push to GitHub --------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "deploy: $(date -u +'%Y-%m-%d %H:%M:%S') UTC"
  fi
  git push -u origin HEAD
else
  echo "Warning: not a git repo; skipping commit/push."
fi

# -------- 2) Sync web files to /var/www/html --------
rsync -avz --delete \
  --exclude '.git' \
  --exclude '.gitignore' \
  --exclude '.DS_Store' \
  "${WEB_DIR}/" "${PI_HOST}:${REMOTE_HTML}/"

# -------- 3) Stage backend files on the Pi --------
${SSH_CMD} ${PI_HOST} "mkdir -p ~/deploy_staging/backend"
rsync -avz "${BACKEND_DIR}/" "${PI_HOST}:~/deploy_staging/backend/"

# -------- 4) Apply backend on the Pi --------
${SSH_CMD} -t ${PI_HOST} bash -lc "set -euo pipefail

  STAGE=~/deploy_staging/backend

  # Ensure app dir exists
  mkdir -p '${REMOTE_APP_DIR}'

  # Ensure venv exists + install deps (idempotent)
  if [ ! -d '${REMOTE_VENV}' ]; then
    python3 -m venv '${REMOTE_VENV}'
  fi
  '${REMOTE_VENV}/bin/pip' install --upgrade pip >/dev/null
  if [ -f \"\${STAGE}/requirements.txt\" ]; then
    '${REMOTE_VENV}/bin/pip' install -r \"\${STAGE}/requirements.txt\"
  fi

  # Install backend files
  install -m 0644 \"\${STAGE}/app.py\" '${REMOTE_APP_DIR}/app.py'
  install -m 0755 \"\${STAGE}/poweron.sh\" '${REMOTE_POWER_SCRIPT}'

  # If nginx config present in repo, install and reload nginx
  if [ -f \"\${STAGE}/pi.conf\" ]; then
    sudo install -m 0644 \"\${STAGE}/pi.conf\" '${REMOTE_NGX_AVAIL}'
    if [ ! -e '${REMOTE_NGX_ENABLED}' ]; then
      sudo ln -s '${REMOTE_NGX_AVAIL}' '${REMOTE_NGX_ENABLED}'
    fi
    sudo nginx -t
    sudo systemctl reload nginx
  fi

  # Restart backend:
  if systemctl list-unit-files | grep -q '^powerbtn\\.service'; then
    sudo systemctl daemon-reload
    sudo systemctl restart powerbtn.service
  else
    pkill -f 'waitress-serve --listen=127.0.0.1:8080' || true
    nohup '${REMOTE_VENV}/bin/waitress-serve' --listen=127.0.0.1:8080 app:app \
      --call >/dev/null 2>&1 &
    sleep 1
  fi

  echo 'Apply complete on Pi.'
"

echo "Deployed → https://pi.davisbisbee.com"
