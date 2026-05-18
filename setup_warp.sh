#!/usr/bin/env bash

# --- 1. PRE-REQUISITES & TIMEZONE ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null
apt-get install -y --no-install-recommends \
    curl lsb-release wget gpg psmisc net-tools \
    tzdata procps iputils-ping bc >/dev/null

ln -fs /usr/share/zoneinfo/Africa/Johannesburg /etc/localtime >/dev/null
dpkg-reconfigure --frontend noninteractive tzdata >/dev/null

# --- 2. RESILIENT REPO INJECTION ---
if ! command -v warp-cli &>/dev/null; then
    echo "⚠️ Installing Cloudflare Warp..."
    # Ensure the keyrings directory exists
    mkdir -p /usr/share/keyrings
    
    # Download key and add repo in one clean pipe
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor --yes -o /usr/share/keyrings/cloudflare-warp.gpg
    
    # Use 'tee' with a bracketed arch to avoid mismatches
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | \
    tee /etc/apt/sources.list.d/cloudflare-warp.list >/dev/null
    
    apt-get update -y >/dev/null
    apt-get install -y cloudflare-warp >/dev/null
fi

# --- 3. SYSTEMD-AWARE SERVICE START ---
# Ensure local state directory exists for background mode
mkdir -p /var/lib/cloudflare-warp

if [ -d /run/systemd/system ] || pidof systemd >/dev/null; then
    systemctl enable --now warp-svc >/dev/null 2>&1
else
    if ! pidof warp-svc >/dev/null; then
        killall warp-svc 2>/dev/null || true
        # Run daemon with high priority in background
        nohup warp-svc >/var/log/warp-svc.log 2>&1 &
        # Give the daemon a moment to bind to the control socket
        for i in {1..5}; do pidof warp-svc >/dev/null && break || sleep 1; done
    fi
fi

# --- 4. REGISTRATION & PROXY MODE ---
# Accepting TOS and setting up proxy
warp-cli --accept-tos registration new 2>/dev/null || true
warp-cli --accept-tos mode proxy
warp-cli --accept-tos connect
sleep 3

# --- 5. THE AUDIT ---
echo "--- NETWORK AUDIT ---"
REAL_IP=$(curl -s ifconfig.me)
PROXY_IP=$(curl -s -x socks5h://127.0.0.1:40000 ifconfig.me)

echo "DIRECT IP: $REAL_IP"
echo "WARP   IP: $PROXY_IP"
echo "----------------------"
netstat -ntlp
