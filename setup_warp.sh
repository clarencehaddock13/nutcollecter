#!/bin/bash
set -x

echo "Cleaning up old configs..."
kill $(pgrep wireproxy) 2>/dev/null || true
rm -f wireproxy wireproxy.tar.gz warp-proxy.conf wireproxy.log warp-reg

echo "Downloading wireproxy..."
curl -fsSL -o wireproxy.tar.gz https://github.com/windtf/wireproxy/releases/download/v1.1.2/wireproxy_linux_amd64.tar.gz
tar -xzf wireproxy.tar.gz
chmod +x wireproxy

echo "Downloading warp-reg..."
curl -fsSL -o warp-reg https://github.com/badafans/warp-reg/releases/download/v1.0/main-linux-amd64
chmod +x warp-reg

echo "Generating keys and capturing terminal output..."
# 🚀 Capture the console dump directly into a string variable
REG_OUTPUT=$(./warp-reg)

echo "$REG_OUTPUT"

# Extract the variables directly from the captured console text
PRIV_KEY=$(echo "$REG_OUTPUT" | grep -i "private_key:" | awk '{print $2}')
PEER_PUB=$(echo "$REG_OUTPUT" | grep -i "public_key:" | awk '{print $2}')
WARP_IP=$(echo "$REG_OUTPUT" | grep -i "v4:" | awk '{print $2}')

if [[ -z "$PRIV_KEY" ]]; then
    echo "❌ Key generation parsing failed."
    exit 1
fi

echo "Converting profile to wireproxy format..."
cat << EOF > warp-proxy.conf
[Interface]
PrivateKey = $PRIV_KEY
Address = $WARP_IP/32
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
