#!/bin/bash
set -x
echo "Cleaning up old configs..."
kill $(pgrep wireproxy) 2>/dev/null || true
rm -f wgcf wgcf-profile.conf wgcf-account.toml wireproxy wireproxy.tar.gz warp-proxy.conf

echo "Downloading wgcf..."
curl -fsSL https://github.com/ViRb3/wgcf/releases/download/v2.2.31/wgcf_2.2.31_linux_amd64 -o wgcf
chmod +x wgcf

echo "Registering WARP account..."
./wgcf register --accept-tos

echo "Generating WireGuard profile..."
./wgcf generate

echo "Downloading wireproxy..."
curl -fsSL -o wireproxy.tar.gz https://github.com/windtf/wireproxy/releases/download/v1.1.2/wireproxy_linux_amd64.tar.gz
tar -xzf wireproxy.tar.gz
chmod +x wireproxy

echo "Building base config (IPv4 only)..."
cp wgcf-profile.conf warp-proxy.conf
sed -i 's|^\(Address = [0-9.]*\/[0-9]*\),.*|\1|g' warp-proxy.conf
sed -i 's|AllowedIPs = 0.0.0.0/0, ::/0|AllowedIPs = 0.0.0.0/0|g' warp-proxy.conf
sed -i '/AllowedIPs = ::/d' warp-proxy.conf
sed -i 's|^\(DNS = \).*|\1 1.1.1.1, 1.0.0.1|g' warp-proxy.conf
printf '\n[Socks5]\nBindAddress = 127.0.0.1:40000\n' >> warp-proxy.conf

RESULT=""
WORKING_PORT=""

for PORT in 2408 500 1701 4500; do
  echo "Trying endpoint 162.159.192.1:$PORT..."
  sed -i "s|Endpoint = .*|Endpoint = 162.159.192.1:$PORT|g" warp-proxy.conf

  ./wireproxy -c warp-proxy.conf > wireproxy.log 2>&1 &
  WPID=$!

  for i in $(seq 1 10); do
    sleep 3
    if ! kill -0 $WPID 2>/dev/null; then
      echo "wireproxy crashed on port $PORT. Log:" && cat wireproxy.log
      break
    fi
    RESULT=$(curl -s --max-time 5 -x socks5h://127.0.0.1:40000 https://api.ipify.org 2>/dev/null)
    if [[ -n "$RESULT" ]]; then
      WORKING_PORT=$PORT
      break
    fi
    echo "  Attempt $i/10 — handshake pending..."
  done

  [[ -n "$RESULT" ]] && break

  echo "Port $PORT failed, killing and trying next..."
  kill $WPID 2>/dev/null || true
  sleep 1
done

if [[ -z "$RESULT" ]]; then
  echo "All ports failed. Last log:" && cat wireproxy.log && exit 1
fi

echo "Egress IP: $RESULT"
echo "WARP SOCKS5 proxy active on 127.0.0.1:40000 (IPv4 only) | Port: $WORKING_PORT | PID: $WPID"
