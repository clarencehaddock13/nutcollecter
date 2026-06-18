#!/usr/bin/env bash
# Enable debug mode to see every command executed
set -x

echo "Initializing environment and cleaning up old configs..."
# Kill any existing instances to prevent port conflicts
pkill wireproxy || true
rm -f warp-proxy.conf wgcf-profile.conf wgcf-account.toml

# 2. Download wgcf dynamically
echo "Downloading latest wgcf build..."
curl -fsSL $(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep -oP '"browser_download_url": "\K[^"]*linux_amd64') -o wgcf
chmod +x wgcf

# 3. Create a unique new Cloudflare account and generate keys dynamically
echo "Registering unique account with Cloudflare..."
./wgcf register --accept-tos
echo "Generating dynamic WireGuard profile keys..."
./wgcf generate

# 4. Download wireproxy (User-Space Tunnel Client)
echo "Downloading latest wireproxy engine..."
curl -L -o wireproxy.tar.gz https://github.com/windtf/wireproxy/releases/download/v1.0.9/wireproxy_linux_amd64.tar.gz
tar -xzf wireproxy.tar.gz
chmod +x wireproxy

# 5. Build the proxy configuration dynamically
echo "Parsing generated keys and assembling your wireproxy configuration..."
cat wgcf-profile.conf > warp-proxy.conf
# Swap the domain string for the direct Anycast IP to prevent container DNS lookup blocks
sed -i 's/Endpoint = engage.cloudflareclient.com:2408/Endpoint = 162.159.192.1:2408/g' warp-proxy.conf
echo -e "\n[Socks5]\nBindAddress = 127.0.0.1:40000" >> warp-proxy.conf

# 6. Boot the engine silently into the background
echo "Starting wireproxy server natively in user-space on port 40000..."
./wireproxy -c warp-proxy.conf > /dev/null 2>&1 &
WIREPROXY_PID=$!

# 4. THE PORT CHECK (Wait loop for the socket)
echo "Waiting for port 40000 to open..."
for i in {1..10}; do
    # Using 'ss' as a more modern alternative to netstat, but falling back to netstat
    if netstat -ntlp 2>/dev/null | grep -q ":40000"; then
        echo "✅ PORT 40000 IS LIVE!"
        break
    fi
    echo "Attempt $i: Port not ready yet..."
    sleep 2
done

# 5. Final Socket Dump & Verification
echo "--- FULL LISTENING PORTS ---"
netstat -ntlp 2>/dev/null || ss -ntlp

echo "Testing live tunnel traffic output..."
curl -s -x socks5h://127.0.0.1:40000 api.ipify.org; echo ""

echo -e "\n🚀 Success! Fresh dynamic connection active on 127.0.0.1:40000"
