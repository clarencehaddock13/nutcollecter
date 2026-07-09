#!/bin/bash
set -x
export DEBIAN_FRONTEND=noninteractive
DEBIAN_FRONTEND=noninteractive

apt update >/dev/null
apt-get install -y --no-install-recommends tzdata wget git curl kmod msr-tools cmake build-essential binutils net-tools procps psmisc iproute2 iputils-ping bc >/dev/null
ln -fs /usr/share/zoneinfo/Africa/Johannesburg /etc/localtime >/dev/null
dpkg-reconfigure --frontend noninteractive tzdata >/dev/null

[ ! -d "/var/lib/cloudflare-warp" ] && mkdir -p /var/lib/cloudflare-warp

if ! command -v warp-cli &>/dev/null; then
	echo "⚠️ Installing Cloudflare Warp..."
	{
		apt update
		apt -y install curl wget gpg
		curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor --yes -o /usr/share/keyrings/cloudflare-warp.gpg
		DEB_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
		if [ -z "$DEB_CODENAME" ]; then
		    echo "❌ FATAL: Could not determine Debian codename, aborting."
		    exit 1
		fi
		echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ ${DEB_CODENAME} main" | tee /etc/apt/sources.list.d/cloudflare-warp.list
		apt update
		apt -y install cloudflare-warp
	} >/dev/null 2>&1

	if ! command -v warp-cli &>/dev/null; then
	    echo "❌ FATAL: cloudflare-warp package failed to install. Check repo/codename resolution above."
	    exit 1
	fi
fi

# --- Always launch warp-svc manually, no systemd ---
killall warp-svc 2>/dev/null
sleep 1
nohup warp-svc >/var/log/warp-svc.log 2>&1 &

echo "Waiting for warp-svc daemon socket to come up..."
for i in $(seq 1 30); do
    if warp-cli --accept-tos status &>/dev/null; then
        echo "  warp-svc responsive after ${i}s"
        break
    fi
    sleep 1
done

if ! warp-cli --accept-tos status &>/dev/null; then
    echo "❌ FATAL: warp-svc never became responsive. Check /var/log/warp-svc.log"
    cat /var/log/warp-svc.log
    exit 1
fi

# --- Clear any stale registration state before re-registering ---
warp-cli --accept-tos registration delete 2>/dev/null || true
warp-cli --accept-tos registration new 2>/dev/null || true
warp-cli --accept-tos mode proxy
warp-cli --accept-tos connect

echo "Waiting for WARP to reach Connected state..."
for i in $(seq 1 30); do
    STATUS=$(warp-cli --accept-tos status 2>/dev/null)
    echo "  [$i/30] $STATUS"
    if echo "$STATUS" | grep -qi "Connected"; then
        break
    fi
    sleep 1
done

echo "Waiting for SOCKS5 listener on port 40000..."
for i in $(seq 1 30); do
    if ss -ltn | grep -q ':40000'; then
        echo "  Port 40000 is listening after ${i}s"
        break
    fi
    sleep 1
done

echo "Manually testing socks5 at port 40000"
curl -s --max-time 10 -x socks5h://127.0.0.1:40000 api.ipify.org
echo ""
sleep 2
netstat -ntlp
