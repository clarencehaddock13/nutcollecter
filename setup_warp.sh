#!/bin/bash
set -x

echo "Cleaning up old configs..."
kill $(pgrep wireproxy) 2>/dev/null || true
rm -f wireproxy wireproxy.tar.gz warp-proxy.conf wireproxy.log main-* warp.conf

echo "Downloading wireproxy..."
curl -fsSL -o wireproxy.tar.gz https://github.com/windtf/wireproxy/releases/download/v1.1.2/wireproxy_linux_amd64.tar.gz
tar -xzf wireproxy.tar.gz
chmod +x wireproxy

echo "Downloading warp-reg from correct repository..."
# 🚀 Fixed URL and binary name mapping
curl -fsSL -o warp-reg https://github.com/badafans/warp-reg/releases/download/v1.0/main-linux-amd64
chmod +x warp-reg
./warp-reg

if [ ! -f warp.conf ]; then
    echo "❌ Key generation failed. File warp.conf not found."
    exit 1
fi

echo "Converting profile to wireproxy format..."
PRIV_KEY=$(grep -i "PrivateKey" warp.conf | awk '{print $3}')
PEER_PUB=$(grep -i "PublicKey" warp.conf | awk '{print $3}')
WARP_IP=$(grep -i "Address" warp.conf | awk '{print $3}')

cat << EOF > warp-proxy.conf
[Interface]
PrivateKey = $PRIV_KEY
Address = $WARP_IP
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = $PEER_PUB
Endpoint = 162.159.192.1:2408
AllowedIPs = 0.0.0.0/0

[Socks5]
BindAddress = 127.0.0.1:40000
EOF

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
