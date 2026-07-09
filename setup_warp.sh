#!/bin/bash
set -x
export DEBIAN_FRONTEND=noninteractive
DEBIAN_FRONTEND=noninteractive
apt update >/dev/null
apt-get install -y --no-install-recommends tzdata wget git curl kmod msr-tools cmake build-essential binutils procps psmisc net-tools iputils-ping bc >/dev/null
ln -fs /usr/share/zoneinfo/Africa/Johannesburg /etc/localtime >/dev/null
dpkg-reconfigure --frontend noninteractive tzdata >/dev/null

[ ! -d "/var/lib/cloudflare-warp" ] && mkdir -p /var/lib/cloudflare-warp

if ! command -v warp-cli &>/dev/null; then
	echo "⚠️ Installing Cloudflare Warp..."
	{
		apt update
		apt -y install curl lsb-release wget gpg net-tools
		curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor --yes -o /usr/share/keyrings/cloudflare-warp.gpg
		DEB_CODENAME=$(lsb_release -sc 2>/dev/null)
		echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ ${DEB_CODENAME} main" | tee /etc/apt/sources.list.d/cloudflare-warp.list
		apt update
		apt -y install cloudflare-warp
	} >/dev/null 2>&1
fi


if [ -d /run/systemd/system ] || pidof systemd >/dev/null; then
	# Use systemctl if available
	systemctl enable --now warp-svc >/dev/null 2>&1
else
	# Fallback to manual background process
	if ! pidof warp-svc >/dev/null; then
		killall warp-svc 2>/dev/null
		nohup warp-svc >/var/log/warp-svc.log 2>&1 &
		sleep 5
	fi
fi

warp-cli --accept-tos registration new 2>/dev/null || true
warp-cli --accept-tos mode proxy
warp-cli --accept-tos connect
sleep 5

echo "Manually testing socks5 at port 40000"
curl -s -x socks5h://127.0.0.1:40000 ifconfig.me
echo ""
sleep 2
netstat -ntlp
