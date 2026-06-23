#!/bin/bash
set -x

echo "Cleaning up old configs..."
kill $(pgrep wireproxy) 2>/dev/null || true
rm -f wgcf wgcf-profile.conf wgcf-account.toml wireproxy wireproxy.tar.gz warp-proxy.conf

echo "Downloading latest wgcf..."
WGCF_URL=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest \
  | grep -oP '"browser_download_url": "\K[^"]*linux_amd64[^"]*' \
  | grep -v '\.sha256' | head -1)
curl -fsSL "$WGCF_URL" -o wgcf
chmod +x wgcf

echo "Registering WARP account..."
./wgcf register --accept-tos

echo "Generating WireGuard profile..."
./wgcf generate

echo "Downloading latest wireproxy..."
curl -fsSL -o wireproxy.tar.gz \
  https://github.com/pufferffish/wireproxy/releases/latest/download/wireproxy_linux_amd64.tar.gz
tar -xzf wireproxy.tar.gz
chmod +x wireproxy

echo "Building config (IPv4 only)..."
cp wgcf-profile.conf warp-proxy.conf

# Fix endpoint to IPv4
sed -i 's/Endpoint = engage.cloudflareclient.com:2408/Endpoint = 162.159.192.1:2408/g' warp-proxy.conf

# Strip IPv6 address from Address line: "172.16.0.2/32, 2606::/128" -> "172.16.0.2/32"
sed -i 's|^\(Address = [0-9.]*\/[0-9]*\),.*|\1|g' warp-proxy.conf

# Strip IPv6 from AllowedIPs
sed -i 's|AllowedIPs = 0.0.0.0/0, ::/0|AllowedIPs = 0.0.0.0/0|g' warp-proxy.conf
sed -i '/AllowedIPs = ::/d' warp-proxy.conf

# Strip IPv6 DNS entries
sed -i 's|^\(DNS = \).*|\1 1.1.1.1, 1.0.0.1|g' warp-proxy.conf

printf '\n[Socks5]\nBindAddress = 127.0.0.1:40000\n' >> warp-proxy.conf

echo "Final config:"
cat warp-proxy.conf

echo "Starting wireproxy..."
./wireproxy -c warp-proxy.conf > wireproxy.log 2>&1 &
WPID=$!
sleep 4

if ! kill -0 $WPID 2>/dev/null; then
  echo "wireproxy failed to start. Log:" && cat wireproxy.log && exit 1
fi

echo "Testing tunnel..."
RESULT=$(curl -s --max-time 10 -x socks5h://127.0.0.1:40000 https://api.ipify.org)
if [[ -z "$RESULT" ]]; then
  echo "Tunnel test failed. Check wireproxy.log" && cat wireproxy.log && exit 1
fi

echo ""
echo "Egress IP: $RESULT"
echo "WARP SOCKS5 proxy active on 127.0.0.1:40000 (IPv4 only)"
echo "PID: $WPID"
