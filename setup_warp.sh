#!/usr/bin/env bash
# Exit on any error, and print every command as it runs
set -ex

echo "--- STARTING VERBOSE INSTALL ---"

# 1. Add Repository with feedback
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor --yes -o /usr/share/keyrings/cloudflare-warp.gpg

# Check if lsb_release is actually working
CODENAME=$(lsb_release -cs)
echo "Detected Ubuntu Codename: $CODENAME"

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ $CODENAME main" | tee /etc/apt/sources.list.d/cloudflare-warp.list

# 2. Update and Install (No silence)
apt-get update
apt-get install -y cloudflare-warp psmisc net-tools

# 3. Start Service
if [ -d /run/systemd/system ] || pidof systemd >/dev/null; then
    echo "Using Systemd..."
    systemctl enable --now warp-svc
else
    echo "Systemd not found, using nohup..."
    mkdir -p /var/lib/cloudflare-warp
    nohup warp-svc > /var/log/warp-svc.log 2>&1 &
    sleep 5
fi

# 4. Handshake with Cloudflare
# This is usually where things hang if the daemon isn't ready
warp-cli --accept-tos registration new
warp-cli --accept-tos mode proxy
warp-cli --accept-tos connect

sleep 2

netstat -ntlp

echo "--- DAEMON STATUS ---"
pidof warp-svc || echo "warp-svc IS NOT RUNNING"
