#!/usr/bin/env bash
set -ex

echo "--- 🛡️ WARP INSTALL & PORT AUDIT ---"

# 1. Install Logic (Simplified & Verbose)
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/cloudflare-warp.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-warp.list

sudo apt-get update
sudo apt-get install -y cloudflare-warp psmisc net-tools

# 2. Daemon Start
if [ -d /run/systemd/system ]; then
    sudo systemctl enable --now warp-svc
else
    sudo mkdir -p /var/lib/cloudflare-warp
    sudo nohup warp-svc > /var/log/warp-svc.log 2>&1 &
    sleep 5
fi

# 3. Configure and Connect
warp-cli --accept-tos registration new || true
warp-cli --accept-tos mode proxy
# Force the port to 40000 just in case default is different
warp-cli --accept-tos proxy port 40000
warp-cli --accept-tos connect

# 4. THE PORT CHECK (Wait loop for the socket)
echo "Waiting for port 40000 to open..."
for i in {1..10}; do
    if sudo netstat -ntlp | grep -q ":40000"; then
        echo "✅ PORT 40000 IS LIVE!"
        break
    fi
    echo "Attempt $i: Port not ready yet..."
    sleep 2
done

# 5. Final Socket Dump
echo "--- FULL LISTENING PORTS ---"
sudo netstat -ntlp
