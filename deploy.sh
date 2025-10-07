#!/usr/bin/env bash
set -euo pipefail

# --- Git: commit & push current working tree (optional but convenient) ---
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Stage everything that belongs in the repo
  git add -A

  # Commit only if there are changes
  if ! git diff --cached --quiet; then
    git commit -m "deploy: $(date -u +'%Y-%m-%d %H:%M:%S') UTC"
  fi

  # Push to the already-configured 'origin' (set this once via GitHub Desktop)
  git push -u origin HEAD
else
  echo "Warning: not a git repo here; skipping commit/push."
fi

# --- Deploy to Pi via Cloudflared SSH -> rsync ---
export RSYNC_RSH='ssh -o ProxyCommand="cloudflared access ssh --hostname ssh-pi.davisbisbee.com"'

# Exclude things that should not land on the Pi’s /var/www/html
rsync -avz --delete \
  --exclude '.git' \
  --exclude '.gitignore' \
  --exclude '.DS_Store' \
  --exclude 'deploy.sh' \
  --exclude 'node_modules' \
  ./ chungy@ssh-pi.davisbisbee.com:/var/www/html/

# Optional: show the commit that was just deployed (if repo present)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  short_sha="$(git rev-parse --short HEAD)"
  echo "Deployed commit ${short_sha} → https://pi.davisbisbee.com"
else
  echo "Deployed (no git repo) → https://pi.davisbisbee.com"
fi