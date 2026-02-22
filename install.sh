#!/bin/bash
set -e

# ─────────────────────────────────────────────

# PicoClaw Auto-Installer

# Model  : moonshotai/kimi-k2-instruct

# API    : NVIDIA NIM

# ─────────────────────────────────────────────

GREEN=’\033[0;32m’
YELLOW=’\033[1;33m’
RED=’\033[0;31m’
NC=’\033[0m’

echo -e “${GREEN}”
echo “  ██████╗ ██╗ ██████╗  ██████╗  ██████╗██╗      █████╗ ██╗    ██╗”
echo “  ██╔══██╗██║██╔════╝ ██╔═══██╗██╔════╝██║     ██╔══██╗██║    ██║”
echo “  ██████╔╝██║██║      ██║   ██║██║     ██║     ███████║██║ █╗ ██║”
echo “  ██╔═══╝ ██║██║      ██║   ██║██║     ██║     ██╔══██║██║███╗██║”
echo “  ██║     ██║╚██████╗ ╚██████╔╝╚██████╗███████╗██║  ██║╚███╔███╔╝”
echo “  ╚═╝     ╚═╝ ╚═════╝  ╚═════╝  ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝”
echo -e “${NC}”
echo “  🤖 PicoClaw Auto-Installer — Kimi-k2.5 via NVIDIA”
echo “━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━”

# ── API Key مدمج ──

NVIDIA_KEY=“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”

# ── Telegram Token مدمج ──

TELEGRAM_BOT_TOKEN=“5984403789:AAGd2UwL7-Tv8FBfbRenMKGuSzC-X4mMMQE”

# ── تحديد الـ Architecture ──

echo “”
echo “🔍 تحديد نوع المعالج…”
ARCH=$(uname -m)
case $ARCH in
aarch64) BINARY=“picoclaw-linux-arm64”  ;;
armv7l)  BINARY=“picoclaw-linux-arm-v7” ;;
x86_64)  BINARY=“picoclaw-linux-amd64”  ;;
*)
echo -e “${RED}❌ معالج مش مدعوم: $ARCH${NC}”
exit 1
;;
esac
echo -e “✅ المعالج: ${GREEN}$ARCH${NC} → $BINARY”

# ── تحميل PicoClaw ──

echo “”
echo “📥 تحميل PicoClaw…”
wget -q –show-progress   
“https://github.com/sipeed/picoclaw/releases/latest/download/$BINARY”   
-O /tmp/picoclaw

chmod +x /tmp/picoclaw
sudo mv /tmp/picoclaw /usr/local/bin/picoclaw
echo -e “✅ ${GREEN}PicoClaw اتحمل${NC}”

# ── إنشاء الـ Config ──

echo “”
echo “⚙️  إعداد الـ Config…”
mkdir -p ~/.picoclaw

cat > ~/.picoclaw/config.json << CONFIGEOF
{
“model_list”: [
{
“model_name”: “kimi”,
“model”: “moonshotai/kimi-k2-instruct”,
“base_url”: “https://integrate.api.nvidia.com/v1”,
“api_key”: “${NVIDIA_KEY}”
}
],
“agents”: {
“defaults”: {
“model”: “kimi”,
“system_prompt”: “أنت مساعد ذكاء اصطناعي مفيد ومبدع. أجب دائماً بشكل واضح ومختصر.”
}
},
“channels”: {
“telegram”: {
“token”: “${TELEGRAM_BOT_TOKEN}”,
“allowed_users”: []
}
}
}
CONFIGEOF

echo -e “✅ ${GREEN}Config اتعمل${NC}”

# ── إنشاء الـ systemd Service ──

echo “”
echo “🔧 إعداد الـ Service…”

cat > /tmp/picoclaw.service << SERVICEEOF
[Unit]
Description=PicoClaw AI Bot — Kimi k2.5 via NVIDIA
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/picoclaw gateway
Restart=always
RestartSec=10
User=${USER}
Environment=HOME=${HOME}
WorkingDirectory=${HOME}

[Install]
WantedBy=multi-user.target
SERVICEEOF

sudo mv /tmp/picoclaw.service /etc/systemd/system/picoclaw.service

# ── تفعيل وتشغيل ──

sudo systemctl daemon-reload
sudo systemctl enable picoclaw
sudo systemctl start picoclaw

sleep 2

# ── التحقق ──

echo “”
echo “━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━”
if systemctl is-active –quiet picoclaw; then
echo -e “✅ ${GREEN}البوت شغال تمام!${NC}”
else
echo -e “${RED}⚠️  فيه مشكلة — شوف اللوق:${NC}”
sudo journalctl -u picoclaw -n 20 –no-pager
fi

echo “”
echo “📊 الحالة  : sudo systemctl status picoclaw”
echo “📜 اللوق   : sudo journalctl -u picoclaw -f”
echo “🛑 إيقاف   : sudo systemctl stop picoclaw”
echo “🔄 إعادة   : sudo systemctl restart picoclaw”
echo “”
echo -e “${GREEN}🎉 خلاص! ابعت رسالة للبوت بتاعك على Telegram${NC}”
echo “━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━”