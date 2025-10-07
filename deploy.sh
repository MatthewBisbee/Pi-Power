#!/usr/bin/env bash
# --------------------------------------------------------------------
# Pi site deploy script
# Commits + pushes any Git changes, then rsyncs site to /var/www/html
# Optional alias tip (add this once):
#   echo "alias deploy='./deploy.sh'" >> ~/.bashrc && source ~/.bashrc
# After that, you can just type "deploy" instead of "./deploy.sh"
# --------------------------------------------------------------------

set -euo pipefail

# --- Git commit & push section (optional but nice) ---
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "deploy: $(date -u +'%Y-%m-%d %H:%M:%S') UTC"
  fi
  git push -u origin HEAD
else
  echo "Warning: not in a Git repo; skipping commit/push."
fi

# --- Deploy to Pi via Cloudflared SSH tunnel ---
export RSYNC_RSH='ssh -o ProxyCommand="cloudflared access ssh --hostname ssh-pi.davisbisbee.com"'

rsync -avz --delete \
  --exclude '.git' \
  --exclude '.gitignore' \
  --exclude '.DS_Store' \
  --exclude 'deploy.sh' \
  --exclude 'node_modules' \
  ./ chungy@ssh-pi.davisbisbee.com:/var/www/html/

# --- Completion message ---
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  short_sha="$(git rev-parse --short HEAD)"
  echo "Deployed commit ${short_sha} → https://pi.davisbisbee.com"
else
  echo "Deployed → https://pi.davisbisbee.com"
fi