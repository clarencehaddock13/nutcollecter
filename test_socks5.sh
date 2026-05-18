#!/usr/bin/env bash

# --- PROXY CONFIG ---
export ALL_PROXY="socks5h://127.0.0.1:40000"

echo "================================================="
echo "🛡️ PROXY PROOF OF CONCEPT"
echo "================================================="

# 1. SHOW THE BYPASS (The 'Dirty' GitHub IP)
# We use --noproxy '*' to force curl to ignore the environment variable
DIRTY_IP=$(curl -s --noproxy '*' ifconfig.me)
echo "1. DIRECT IP (Bypassed): $DIRTY_IP"

# 2. SHOW THE PROXIFIED (The 'Clean' Cloudflare IP)
# This uses the ALL_PROXY we exported above automatically
CLEAN_IP=$(curl -s ifconfig.me)
echo "2. PROXY IP (Active):   $CLEAN_IP"

echo "-------------------------------------------------"

if [ "$DIRTY_IP" != "$CLEAN_IP" ]; then
    echo "✅ SUCCESS: Your identity is masked."
    echo "Render will only see: $CLEAN_IP"
else
    echo "❌ FAILURE: IPs match. WARP is not routing."
fi
echo "================================================="
