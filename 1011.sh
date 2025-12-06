#!/usr/bin/env bash
set -euo pipefail

# ===== Ensure interactive reads =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then exec </dev/tty; fi

# ===== Logging =====
LOG_FILE="/tmp/1011_aio_$(date +%s).log"
touch "$LOG_FILE"

# ===== Color & UI =====
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'
  C_CYAN=$'\e[38;5;51m'; C_GREEN=$'\e[38;5;46m'; C_YEL=$'\e[38;5;226m'
  C_RED=$'\e[38;5;196m'; C_GREY=$'\e[38;5;245m'
  C_PURPLE=$'\e[38;5;93m'
else
  RESET= BOLD= C_CYAN= C_GREEN= C_YEL= C_RED= C_GREY= C_PURPLE=
fi

# ===== Banner =====
clear
printf "\n\n"
printf "${C_CYAN}${BOLD}"
printf "╔══════════════════════════════════════════════════════════════════╗\n"
printf "║    ${C_RED} ______  _____  _____   ____      __  ___  __  __         ${C_CYAN}\n"
printf "║    ${C_RED}|___  / | ____||  __ \ / __ \    /_ |/ _ \/_ |/_ |        ${C_CYAN}\n"
printf "║    ${C_RED}   / /  | |__  | |__) | |  | |____| | | | || || |        ${C_CYAN}\n"
printf "║    ${C_RED}  / /   |  __| |  _  /| |  | |____| | | | || || |        ${C_CYAN}\n"
printf "║    ${C_RED} / /__  | |____| | \ \| |__| |    | || |_| || || |        ${C_CYAN}\n"
printf "║    ${C_RED}/_____| |______|_|  \_\\____/     |_| \___/ |_||_|        ${C_CYAN}\n"
printf "║                                                                  \n"
printf "║         ${C_YEL}🚀 ALL-IN-ONE DEPLOYMENT (VLESS + VMESS + TROJAN)       ${C_CYAN}\n"
printf "║         ${C_GREEN}⚡ Powered by ZERO_1011                                 ${C_CYAN}\n"
printf "║                                                                  \n"
printf "╚══════════════════════════════════════════════════════════════════╝${RESET}\n\n"

# ===== Telegram Setup (Step 1) =====
printf "${C_PURPLE}┌── Step 1: Telegram Configuration ────────────────────────┐${RESET}\n"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-${TELEGRAM_CHAT_ID:-}}"

if [[ ( -z "${TELEGRAM_TOKEN}" || -z "${TELEGRAM_CHAT_IDS}" ) && -f .env ]]; then
  set -a; source ./.env; set +a
fi

read -rp "${C_GREEN}🤖 Bot Token (Optional):${RESET} " _tk || true
[[ -n "${_tk:-}" ]] && TELEGRAM_TOKEN="$_tk"

read -rp "${C_GREEN}👤 Chat ID (Optional):${RESET} " _ids || true
[[ -n "${_ids:-}" ]] && TELEGRAM_CHAT_IDS="${_ids// /}"
printf "${C_PURPLE}└──────────────────────────────────────────────────────────┘${RESET}\n\n"

tg_send(){
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || -z "${TELEGRAM_CHAT_IDS:-}" ]]; then return 0; fi
  IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}"
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" >>"$LOG_FILE" 2>&1
  done
  printf "${C_GREEN}✓ Telegram notification sent.${RESET}\n"
}

# ===== Project Check (Step 2) =====
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  printf "${C_RED}❌ Error: No Active GCP Project Found.${RESET}\n"
  printf "Run: gcloud config set project <YOUR_PROJECT_ID>\n"
  exit 1
fi

# ===== Configuration (Step 3) =====
# Docker Image from mgmyomin1 (System Only)
IMAGE="docker.io/mgmyomin1/vless-ws:latest"
UUID="562572c6-d933-4c91-8633-d9222414777e"
TROJAN_PW="Trojan-MgMyoMin1"

# ===== Region Selection (Step 4) =====
printf "\n${C_PURPLE}┌── Step 4: Select Region ─────────────────────────────────┐${RESET}\n"
echo "  1) 🇸🇬 Singapore (asia-southeast1) - Recommended"
echo "  2) 🇺🇸 US Central (us-central1)"
echo "  3) 🇯🇵 Japan (asia-northeast1)"
echo "  4) 🇮🇩 Indonesia (asia-southeast2)"
echo "  5) 🇮🇳 India (asia-south1)"
printf "${C_PURPLE}└──────────────────────────────────────────────────────────┘${RESET}\n"
read -rp "${C_GREEN}Choose [1-5, default 1]:${RESET} " _r
case "${_r:-1}" in
  2) REGION="us-central1" ;;
  3) REGION="asia-northeast1" ;;
  4) REGION="asia-southeast2" ;;
  5) REGION="asia-south1" ;;
  *) REGION="asia-southeast1" ;;
esac

# ===== Resource Selection (Step 5 - CPU/RAM) =====
printf "\n${C_PURPLE}┌── Step 5: Resources Selection ───────────────────────────┐${RESET}\n"
echo "  ${C_GREY}CPU Options: 1, 2, 4, 6${RESET}"
read -rp "${C_GREEN}CPU Cores [default 2]:${RESET} " _cpu || true
CPU="${_cpu:-2}"

echo "  ${C_GREY}Memory Options: 512Mi, 1Gi, 2Gi, 4Gi, 8Gi${RESET}"
read -rp "${C_GREEN}Memory [default 2Gi]:${RESET} " _mem || true
MEMORY="${_mem:-2Gi}"
printf "${C_PURPLE}└──────────────────────────────────────────────────────────┘${RESET}\n"

# ===== Service Name (Step 6) =====
read -rp "${C_GREEN}Enter Service Name [default: zero-1011]:${RESET} " _svc
SERVICE="${_svc:-zero-1011}"

# ===== Time Calculation (Step 7 - Start/End Time) =====
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
# 1 Hour Timeout (3600s) default for Cloud Run manual deploy
END_EPOCH="$(( START_EPOCH + 3600 ))"
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"

printf "\n${C_PURPLE}┌── Step 7: Deployment Schedule ───────────────────────────┐${RESET}\n"
printf "   ${C_GREY}Start Time:${RESET} ${C_CYAN}${START_LOCAL}${RESET}\n"
printf "   ${C_GREY}End Time:  ${RESET} ${C_CYAN}${END_LOCAL}${RESET}\n"
printf "${C_PURPLE}└──────────────────────────────────────────────────────────┘${RESET}\n"

# ===== Deploy (Step 9) =====
printf "\n${C_YEL}🚀 Deploying ZERO_1011 All-in-One Server...${RESET}\n"
printf "${C_GREY}   (Image: $IMAGE | $CPU vCPU | $MEMORY RAM)${RESET}\n"

# Enable APIs quietly
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet >/dev/null 2>&1

gcloud run deploy "$SERVICE" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="$MEMORY" \
  --cpu="$CPU" \
  --timeout=3600 \
  --allow-unauthenticated \
  --port=8080 \
  --min-instances=1 \
  --quiet

# ===== Result Generation (Step 10) =====
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"

# Link Generation (Using path: tg-1011)
# 1. VLESS
VLESS_LINK="vless://${UUID}@vpn.googleapis.com:443?path=%2F%40tg-1011&security=tls&encryption=none&host=${HOST}&type=ws&sni=${HOST}#ZERO-VLESS"

# 2. VMess (JSON -> Base64)
VMESS_JSON="{\"v\":\"2\",\"ps\":\"ZERO-VMESS\",\"add\":\"vpn.googleapis.com\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${HOST}\",\"path\":\"/@tg-1011-vmess\",\"tls\":\"tls\",\"sni\":\"${HOST}\",\"alpn\":\"\"}"
VMESS_BASE64=$(echo -n "$VMESS_JSON" | base64 -w 0)
VMESS_LINK="vmess://${VMESS_BASE64}"

# 3. Trojan
TROJAN_LINK="trojan://${TROJAN_PW}@vpn.googleapis.com:443?path=%2F%40tg-1011-trojan&security=tls&host=${HOST}&type=ws&sni=${HOST}#ZERO-TROJAN"

# ===== Telegram Notification (Branding: ZERO_1011) =====
MSG=$(cat <<EOF
✅ <b>ZERO_1011 Deployment Success</b>
━━━━━━━━━━━━━━━━━━━━━━━━━━
<blockquote>🌍 <b>Region:</b> ${REGION}
🔗 <b>Host:</b> ${HOST}
⚙️ <b>Resources:</b> ${CPU} vCPU / ${MEMORY}
🕒 <b>Start:</b> ${START_LOCAL}
⏳ <b>End:</b> ${END_LOCAL}</blockquote>

<b>1️⃣ VLESS WS:</b>
<pre><code>${VLESS_LINK}</code></pre>

<b>2️⃣ VMess WS:</b>
<pre><code>${VMESS_LINK}</code></pre>

<b>3️⃣ Trojan WS:</b>
<pre><code>${TROJAN_LINK}</code></pre>
━━━━━━━━━━━━━━━━━━━━━━━━━━
<b>Powered by ZERO_1011</b>
EOF
)

tg_send "${MSG}"

# ===== Final Output =====
printf "\n${C_CYAN}✅ DEPLOYMENT SUCCESSFUL!${RESET}\n"
printf "${C_GREY}──────────────────────────────────────────────────────────${RESET}\n"
printf "${C_GREEN}1️⃣ VLESS WS Link:${RESET}\n${VLESS_LINK}\n\n"
printf "${C_GREEN}2️⃣ VMess WS Link:${RESET}\n${VMESS_LINK}\n\n"
printf "${C_GREEN}3️⃣ Trojan WS Link:${RESET}\n${TROJAN_LINK}\n\n"
printf "${C_GREY}──────────────────────────────────────────────────────────${RESET}\n"
printf "${C_PURPLE}🕒 Start Time: ${START_LOCAL}${RESET}\n"
printf "${C_PURPLE}⏳ End Time:   ${END_LOCAL}${RESET}\n"
printf "${C_YEL}ℹ️  Links & Time sent to Telegram!${RESET}\n\n"
