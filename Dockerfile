# ── PicoClaw Dockerfile ──────────────────────────────────────────────
# 🛠️  Model  : moonshotai/kimi-k2-instruct
# 🔌  API    : NVIDIA NIM
# 🚀  Host   : Railway / Docker
# ──────────────────────────────────────────────────────────────────────

FROM ubuntu:22.04

# ── تثبيت المتطلبات ──────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    wget \
    python3 \
    ca-certificates \
    git \
    curl \
    jq \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# ── تحميل PicoClaw ──────────────────────────────────────────────────
RUN ARCH=$(uname -m) && \
    case $ARCH in \
        x86_64)  BINARY="picoclaw-linux-amd64"  ;; \
        aarch64) BINARY="picoclaw-linux-arm64"  ;; \
        *) echo "❌ معالج مش مدعوم: $ARCH" && exit 1 ;; \
    esac && \
    wget -q "https://github.com/sipeed/picoclaw/releases/latest/download/$BINARY" -O /usr/local/bin/picoclaw && \
    chmod +x /usr/local/bin/picoclaw

# ── إعداد بيئة العمل ─────────────────────────────────────────────────
WORKDIR /root
RUN mkdir -p /root/.picoclaw/workspace

# ── سكريبت التشغيل الذكي (Python) ────────────────────────────────────
COPY <<'PYEOF' /start.py
import os
import json
import sys

# ── جلب المتغيرات ──────────────────────────────────────────────────
nvidia_key = os.getenv("NVIDIA_KEY")
telegram_token = os.getenv("TELEGRAM_BOT_TOKEN")
allowed_raw = os.getenv("TELEGRAM_ALLOWED_IDS", "")

# ── فحص المتغيرات ──────────────────────────────────────────────────
if not nvidia_key or not telegram_token:
    print("❌ خطأ: NVIDIA_KEY أو TELEGRAM_BOT_TOKEN مش موجودين!")
    sys.exit(1)

# ── بناء config.json ─────────────────────────────────────────────────
# ✅ حل مشكلة 429 و Context Window بشكل جذري:
# 1. تعطيل الأدوات التي تسبب أخطاء Schema (cron, spi, web search).
# 2. تقليل max_tool_iterations لمنع الحلقات المفرغة.
# 3. تقليل max_tokens لضمان استقرار الذاكرة.
config = {
    "agents": {
        "defaults": {
            "workspace": "/root/.picoclaw/workspace",
            "model": "kimi",
            "max_tokens": 1536,          # تقليل إضافي لضمان عدم تجاوز الذاكرة
            "temperature": 0.4,          # ردود أكثر دقة وقصر
            "max_tool_iterations": 3,    # حد أدنى لمنع الـ 429 تماماً
            "system_prompt": (
                "أنت PicoClaw. مساعد AI يعمل بموديل Kimi-K2. "
                "لديك صلاحيات Root كاملة. أجب باختصار شديد جداً وبالعربية. "
                "استخدم أداة shell فقط لتنفيذ الأوامر. "
                "إذا احتجت للبحث، استخدم curl في الـ shell."
            )
        }
    },
    "model_list": [
        {
            "model_name": "kimi",
            "model": "openai/moonshotai/kimi-k2-instruct",
            "api_base": "https://integrate.api.nvidia.com/v1",
            "api_key": nvidia_key
        }
    ],
    "channels": {
        "telegram": {
            "enabled": True,
            "token": telegram_token,
            "allowFrom": [x.strip() for x in allowed_raw.split(",") if x.strip()] if allowed_raw else []
        }
    },
    "tools": {
        "shell": { 
            "enabled": True, 
            "allow_unsafe": True,
            "safety_guards": False 
        },
        "file": { "enabled": True },
        "web": { "search": { "enabled": False }, "browse": { "enabled": False } },
        "cron": { "enabled": False },
        "heartbeat": { "enabled": False },
        "gateway": { "host": "0.0.0.0", "port": 18790 }
    }
}

# ── كتابة الـ config ─────────────────────────────────────────────────
config_path = "/root/.picoclaw/config.json"
os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print("✅ تم تطبيق الإصلاحات الجذرية (Schema + 429 Fix)")
print("🚀 تشغيل PicoClaw Gateway...")
sys.stdout.flush()

# ── تشغيل البوت ──────────────────────────────────────────────────────
os.execv("/usr/local/bin/picoclaw", ["/usr/local/bin/picoclaw", "gateway"])
PYEOF

RUN chmod +x /start.py

# ── HealthCheck ───────────────────────────────────────────────────────
HEALTHCHECK \
    --interval=30s \
    --timeout=10s \
    --start-period=30s \
    --retries=3 \
    CMD wget -qO- http://localhost:18790/health 2>/dev/null || exit 1

EXPOSE 18790
ENTRYPOINT ["python3", "/start.py"]
