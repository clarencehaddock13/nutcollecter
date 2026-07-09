#!/usr/bin/env bash
# --- PROXY CONFIG ---
export ALL_PROXY="socks5h://127.0.0.1:40000"

echo "================================================="
echo "🛡️ PROXY PROOF OF CONCEPT"
echo "================================================="

# 1. SHOW THE BYPASS (The 'Dirty' GitHub IP)
DIRTY_IP=$(curl -s --noproxy '*' --max-time 10 ifconfig.me)
echo "1. DIRECT IP (Bypassed): $DIRTY_IP"

# 2. SHOW THE PROXIFIED (The 'Clean' Cloudflare IP)
CLEAN_IP=$(curl -4 -s --max-time 10 ifconfig.me)
echo "2. PROXY IP (Active):   $CLEAN_IP"

echo "-------------------------------------------------"
if [ -z "$CLEAN_IP" ]; then
    echo "❌ FAILURE: Proxy returned no response (port 40000 not listening or WARP not routing)."
    exit 1
elif [ "$DIRTY_IP" != "$CLEAN_IP" ]; then
    echo "✅ SUCCESS: Your identity is masked."
    echo "Render will only see: $CLEAN_IP"
else
    echo "❌ FAILURE: IPs match. WARP is not routing."
    exit 1
fi
echo "================================================="
