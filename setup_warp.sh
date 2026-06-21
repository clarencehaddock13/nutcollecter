#!/usr/bin/env bash
# Production-Hardened Deployment Script
set -x
set -e

# 1. Kill any existing instances on port 40000
# The || true ensures the script doesn't exit if no process is found
fuser -k 40000/tcp || true

# 2. Safely remove old artifacts if they exist
# rm -f already ignores missing files, so this is safe as-is
rm -f wgcf xray config.json wgcf-profile.conf wgcf-account.toml Xray-linux-64.zip geoip.dat geosite.dat

# 3. Download binaries
curl -fsSL $(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep -oP '"browser_download_url": "\K[^"]*linux_amd64') -o wgcf
curl -L -o Xray-linux-64.zip https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-linux-64.zip
unzip -oq Xray-linux-64.zip
chmod +x xray wgcf

# 4. Setup Config
./wgcf register --accept-tos || true
./wgcf generate
PRIV=$(grep "PrivateKey" wgcf-profile.conf | awk '{print $3}')
PUB=$(grep "PublicKey" wgcf-profile.conf | awk '{print $3}')
ADDR=$(grep "Address" wgcf-profile.conf | sed 's/Address = //g' | cut -d',' -f1 | tr -d ' ')

cat <<EOF > config.json
{
  "inbounds": [{"port": 40000, "protocol": "socks", "settings": {"udp": true}}],
  "outbounds": [{
    "protocol": "wireguard",
    "settings": {
      "secretKey": "$PRIV",
      "peers": [{"publicKey": "$PUB", "endpoint": "162.159.195.1:2408"}],
      "address": ["$ADDR"]
    }
  }]
}
EOF

# 5. Start Xray in the background
# nohup ensures the process stays alive even after this script exits
nohup ./xray -c config.json > xray.log 2>&1 &

# 6. Verification
for i in {1..10}; do
    if netstat -ntlp 2>/dev/null | grep -q ":40000"; then
        echo "✅ Proxy is live on port 40000"
        break
    fi
    sleep 2
done
