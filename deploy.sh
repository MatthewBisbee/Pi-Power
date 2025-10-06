#!/usr/bin/env bash
set -e
export RSYNC_RSH='ssh -o ProxyCommand="cloudflared access ssh --hostname ssh-pi.davisbisbee.com"'
rsync -avz --delete --exclude 'deploy.sh' ./ chungy@ssh-pi.davisbisbee.com:/var/www/html/
echo "Deployed → https://pi.davisbisbee.com"