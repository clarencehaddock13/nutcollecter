#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
RENDER_API_KEY="${1:-}"
GITLAB_REPO_URL="${2:-}"
CURRENT_RUN_INDEX="${3:-1}"

# Ensure proxy is active
#export ALL_PROXY="socks5h://127.0.0.1:40000"

# Pre-flight check for dependencies
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is not installed. Please install it in your CI setup step."
    exit 1
fi

[[ -z "$RENDER_API_KEY" || -z "$GITLAB_REPO_URL" ]] && exit 1

# --- 🛡️ STEALTH VERIFIER ---
echo "🔍 Performing Pre-Flight Stealth Audit..."
# Use --retry to ensure the proxy tunnel is established before continuing
CHECK_IP=$(curl -4 -s --max-time 15 --retry 3 https://ifconfig.me)

if [[ -z "$CHECK_IP" ]]; then
    echo "FATAL: Proxy connection failed. Shield is DOWN."
    exit 1
fi

echo "🚀 Shield Verified. Deployment IP: $CHECK_IP"
echo "------------------------------------------------"

API="https://api.render.com/v1"
AUTH_HDR="Authorization: Bearer ${RENDER_API_KEY}"
ACC_HDR="Accept: application/json"

# --- OWNER ID & REGION ---
# Added --retry to ensure data fetch doesn't fail on network jitter
OWNER_ID=$(curl -s --retry 3 -H "$AUTH_HDR" -H "$ACC_HDR" "${API}/owners?limit=1" | jq -r 'if type=="array" then .[0].owner.id // .[0].team.id else .owner.id // .id end')

POOL=("frankfurt" "oregon" "ohio" "virginia")
REGION=${POOL[$(( (CURRENT_RUN_INDEX - 1) % 4 ))]}
SERVICE_NAME="powerhouse-web-${CURRENT_RUN_INDEX}"

# --- THE TICKLE ---
echo "→ Requesting Service Creation for $SERVICE_NAME..."
# Added --retry and increased timeout for the POST request
CREATE_RESP=$(curl -s --retry 3 --retry-delay 5 --max-time 30 -X POST "${API}/services" \
  -H "$AUTH_HDR" -H "Content-Type: application/json" -H "$ACC_HDR" \
  -d "{
    \"name\": \"${SERVICE_NAME}\",
    \"type\": \"web_service\",
    \"ownerId\": \"${OWNER_ID}\",
    \"repo\": \"${GITLAB_REPO_URL}\",
    \"autoDeploy\": \"yes\",
    \"serviceDetails\": {
      \"runtime\": \"docker\",
      \"plan\": \"pro_ultra\",
      \"region\": \"${REGION}\",
      \"envSpecificDetails\": {
        \"dockerCommand\": \"./run_entrypoint.sh\"
      },
      \"disk\": {
        \"name\": \"power-disk-${CURRENT_RUN_INDEX}\",
        \"mountPath\": \"/var/data\",
        \"sizeGB\": 5
      }
    }
  }")

SERVICE_ID=$(echo "$CREATE_RESP" | jq -r '.service.id // .id // empty')

if [[ -z "$SERVICE_ID" || "$SERVICE_ID" == "null" ]]; then
    echo "FATAL: Render rejected service creation."
    echo "Response: $CREATE_RESP"
    exit 1
fi

# --- MONITORING LOOP ---
echo "→ Monitoring $SERVICE_NAME..."
while true; do
    # Added --retry to monitoring loop to handle temporary loss of tunnel
    STATUS_RESP=$(curl -s --retry 2 -H "$AUTH_HDR" -H "$ACC_HDR" "${API}/services/${SERVICE_ID}/deploys?limit=1")
    STATUS=$(echo "$STATUS_RESP" | jq -r 'if type=="array" then .[0].deploy.status else .status end // "pending"')
    
    if [[ "$STATUS" == "live" ]]; then
        echo "RENDER_SSH_RESULT=ssh ${SERVICE_ID}@ssh.${REGION}.render.com"
        break
    fi
    
    if [[ "$STATUS" == "build_failed" || "$STATUS" == "canceled" ]]; then
        echo "ERROR: Deployment failed with status: $STATUS"
        exit 1
    fi
    
    # Render API is sensitive to high frequency calls; sleep 20 is good.
    sleep 20
done
