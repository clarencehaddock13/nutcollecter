#!/bin/bash
set -x

echo "Initializing environment and cleaning up old configs..."
kill $(pgrep wireproxy) 2>/dev/null || true
rm -f wgcf wgcf-profile.conf wgcf-account.toml wireproxy wireproxy.tar.gz warp-proxy.conf

echo "Downloading latest wgcf build..."
WGCF_URL=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest \
  | grep -oP '"browser_download_url": "\K[^"]*linux_amd64[^"]*' \
  | grep -v '\.sha256' | head -1)
curl -fsSL "$WGCF_URL" -o wgcf
chmod +x wgcf

echo "Registering unique account with Cloudflare..."
./wgcf register --accept-tos

echo "Generating WireGuard profile..."
./wgcf generate

echo "Downloading latest wireproxy..."
curl -fsSL -o wireproxy.tar.gz \
  https://github.com/pufferffish/wireproxy/releases/latest/download/wireproxy_linux_amd64.tar.gz
tar -xzf wireproxy.tar.gz
chmod +x wireproxy

echo "Assembling wireproxy config with IPv6 disabled..."
cp wgcf-profile.conf warp-proxy.conf

# Fix endpoint to IPv4 only
sed -i 's/Endpoint = engage.cloudflareclient.com:2408/Endpoint = 162.159.192.1:2408/g' warp-proxy.conf

# Strip any IPv6 AllowedIPs entries — keep only IPv4 routes
sed -i 's|AllowedIPs = 0.0.0.0/0, ::/0|AllowedIPs = 0.0.0.0/0|g' warp-proxy.conf
sed -i 's|AllowedIPs = ::/0||g' warp-proxy.conf

# Remove any IPv6 DNS entries (e.g. 2606:4700:4700::1111)
sed -i 's|, *[0-9a-fA-F:]*:[0-9a-fA-F:]*||g' warp-proxy.conf

# Bind SOCKS5 on IPv4 loopback only
cat >> warp-proxy.conf << 'CONF'

[Socks5]
BindAddress = 127.0.0.1:40000
CONF

echo "Starting wireproxy on 127.0.0.1:40000..."
./wireproxy -c warp-proxy.conf > wireproxy.log 2>&1 &
WPID=$!

echo "Waiting for tunnel handshake..."
sleep 4

# Verify process is still alive
if ! kill -0 $WPID 2>/dev/null; then
  echo "wireproxy failed to start. Log:"
  cat wireproxy.log
  exit 1
fi

echo "Testing tunnel — expecting Cloudflare IPv4 egress..."
RESULT=$(curl -s --max-time 10 -x socks5h://127.0.0.1:40000 https://api.ipify.org)

if [[ -z "$RESULT" ]]; then
  echo "Tunnel test failed. Check wireproxy.log"
  exit 1
fi

echo ""
echo "Egress IP: $RESULT"
echo ""
echo "🚀 WARP SOCKS5 proxy active on 127.0.0.1:40000 (IPv4 only)"
echo "   PID: $WPID | Log: wireproxy.log"
