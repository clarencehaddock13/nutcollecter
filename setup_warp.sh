#!/usr/bin/env bash
# Production-Hardened Deployment Script
set -x
set -e

# 1. Kill any existing processes on port 40000
echo "Ensuring port 40000 is free..."
fuser -k 40000/tcp || true

# 2. Cleanup artifacts
cleanup() {
    rm -f xray Xray-linux-64.zip config.json wgcf-profile.conf wgcf-account.toml
}
trap cleanup EXIT

# 3. Download & Clean-room extraction
echo "Preparing Xray binary..."
rm -f xray geoip.dat geosite.dat
curl -L -o Xray-linux-64.zip https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-linux-64.zip
unzip -o Xray-linux-64.zip
chmod +x xray

# 4. Register & Generate with retry
echo "Registering with Cloudflare..."
./wgcf register --accept-tos || true
for i in {1..5}; do
    ./wgcf generate
    if grep -q "Address" wgcf-profile.conf; then break; fi
    sleep 2
done

# 5. Extract Address & Config
PRIV_KEY=$(grep "PrivateKey" wgcf-profile.conf | awk '{print $3}')
PEER_PUB=$(grep "PublicKey" wgcf-profile.conf | awk '{print $3}')
ADDR=$(grep "Address" wgcf-profile.conf | sed 's/Address = //g' | cut -d',' -f1 | tr -d ' ')

cat <<EOF > config.json
{
  "inbounds": [{"port": 40000, "protocol": "socks", "settings": {"udp": true}}],
  "outbounds": [{
    "protocol": "wireguard",
    "settings": {
      "secretKey": "$PRIV_KEY",
      "peers": [{"publicKey": "$PEER_PUB", "endpoint": "162.159.195.1:2408"}],
      "address": ["$ADDR"]
    }
  }]
}
EOF

# 6. Start Xray
echo "Starting Xray proxy..."
./xray -c config.json &

# 7. Verification
echo "Verifying proxy connectivity..."
for i in {1..10}; do
    if netstat -ntlp 2>/dev/null | grep -q ":40000"; then break; fi
    sleep 2
done

PROXY_IP=$(curl -4 -s --max-time 10 -x socks5h://127.0.0.1:40000 https://ifconfig.me)
if [[ -n "$PROXY_IP" ]]; then
    echo "🚀 Success! Proxy is active on 127.0.0.1:40000 (WARP IP: $PROXY_IP)"
else
    echo "❌ CRITICAL: Proxy failed to route traffic."
    exit 1
fi
