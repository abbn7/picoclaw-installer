# ═══════════════════════════════════════════════════════════════
#  PicoClaw — Railway Dockerfile
#  Model  : moonshotai/kimi-k2-instruct  (via NVIDIA NIM)
#  Channel: Telegram
#
#  ✅ ملف واحد بس — ارفعه في repo وخده على Railway
#
#  🔑 Variables لازم تضيفهم في Railway → Variables:
#     NVIDIA_KEY           = nvapi-xxxx...
#     TELEGRAM_BOT_TOKEN   = 1234567890:AAx...
#     TELEGRAM_ALLOWED_IDS = (اختياري) مثال: 123456789,987654321
# ═══════════════════════════════════════════════════════════════

FROM ubuntu:22.04

# ── تجنب أي أسئلة تفاعلية أثناء البناء ──
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ── تثبيت الأدوات الأساسية ──
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    ca-certificates \
    jq \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── تحميل PicoClaw Binary المناسب للـ Architecture ──
RUN set -e; \
    ARCH=$(uname -m); \
    echo "🔍 Architecture detected: $ARCH"; \
    case "$ARCH" in \
        x86_64)  BINARY="picoclaw-linux-amd64"  ;; \
        aarch64) BINARY="picoclaw-linux-arm64"  ;; \
        armv7l)  BINARY="picoclaw-linux-arm-v7" ;; \
        *) echo "❌ Unsupported architecture: $ARCH" && exit 1 ;; \
    esac; \
    echo "📥 Downloading $BINARY ..."; \
    wget -q --show-progress \
        "https://github.com/sipeed/picoclaw/releases/latest/download/$BINARY" \
        -O /usr/local/bin/picoclaw; \
    chmod +x /usr/local/bin/picoclaw; \
    echo "✅ PicoClaw downloaded successfully"

# ── إنشاء المجلدات المطلوبة ──
RUN mkdir -p /root/.picoclaw/workspace/sessions \
             /root/.picoclaw/workspace/memory \
             /root/.picoclaw/workspace/cron \
             /root/.picoclaw/workspace/skills

# ── الـ Entrypoint Script — يعمل Config من الـ Variables وقت التشغيل ──
# (الـ Variables مش متاحة وقت البناء، بس متاحة وقت التشغيل في Railway)
RUN cat > /entrypoint.sh << 'ENTRYPOINT_EOF'
#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}   🤖 PicoClaw — Kimi-K2 via NVIDIA NIM   ${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""

# ── التحقق من الـ Variables الإجبارية ──
MISSING=0

if [ -z "$NVIDIA_KEY" ]; then
    echo -e "${RED}❌ NVIDIA_KEY غير موجود في Railway Variables!${NC}"
    MISSING=1
fi

if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo -e "${RED}❌ TELEGRAM_BOT_TOKEN غير موجود في Railway Variables!${NC}"
    MISSING=1
fi

if [ "$MISSING" -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}📌 عشان تضيف الـ Variables في Railway:${NC}"
    echo "   1. افتح الـ Project في Railway"
    echo "   2. روح Variables"
    echo "   3. أضف: NVIDIA_KEY و TELEGRAM_BOT_TOKEN"
    echo ""
    exit 1
fi

# ── بناء الـ allow_from list ──
# لو TELEGRAM_ALLOWED_IDS فيه قيم، حولها لـ JSON array
# لو فاضية، سيبها array فاضية (يسمح لكل الناس)
if [ -n "$TELEGRAM_ALLOWED_IDS" ]; then
    # حول "123,456,789" لـ ["123","456","789"]
    ALLOW_FROM_JSON=$(echo "$TELEGRAM_ALLOWED_IDS" | tr ',' '\n' | \
        jq -R . | jq -s .)
else
    ALLOW_FROM_JSON="[]"
fi

echo "⚙️  جاري إنشاء الـ Config..."

# ── إنشاء config.json ──
cat > /root/.picoclaw/config.json << CONFIG_EOF
{
  "agents": {
    "defaults": {
      "workspace": "/root/.picoclaw/workspace",
      "model": "kimi",
      "max_tokens": 8192,
      "temperature": 0.7,
      "max_tool_iterations": 20
    }
  },
  "model_list": [
    {
      "model_name": "kimi",
      "model": "openai/moonshotai/kimi-k2-instruct",
      "api_base": "https://integrate.api.nvidia.com/v1",
      "api_key": "${NVIDIA_KEY}"
    }
  ],
  "channels": {
    "telegram": {
      "enabled": true,
      "token": "${TELEGRAM_BOT_TOKEN}",
      "allow_from": ${ALLOW_FROM_JSON}
    }
  },
  "tools": {
    "web": {
      "duckduckgo": {
        "enabled": true,
        "max_results": 5
      }
    }
  }
}
CONFIG_EOF

echo -e "${GREEN}✅ Config جاهز${NC}"
echo ""
echo "📊 إعدادات البوت:"
echo "   🤖 Model   : moonshotai/kimi-k2-instruct (NVIDIA NIM)"
echo "   💬 Channel : Telegram"
echo "   👥 Allow   : ${TELEGRAM_ALLOWED_IDS:-الكل (مفيش قيود)}"
echo ""
echo -e "${GREEN}🚀 تشغيل PicoClaw Gateway...${NC}"
echo "══════════════════════════════════════════"
echo ""

# ── تشغيل البوت ──
exec /usr/local/bin/picoclaw gateway

ENTRYPOINT_EOF

RUN chmod +x /entrypoint.sh

# ── Railway بيشتغل بـ non-root user أحياناً — نضمن الصلاحيات ──
RUN chmod -R 755 /root/.picoclaw

# ── الـ Port (مش مطلوب لبوت Telegram بس Railway بيتوقعه) ──
EXPOSE 8080

# ── نقطة الدخول ──
ENTRYPOINT ["/entrypoint.sh"]
