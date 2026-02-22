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
# ✅ حل مشكلة 429 (Too Many Requests) - تقليل التكرار وزيادة الكفاءة
# ✅ حل مشكلة Context Window - تقليل max_tokens وتحديد الذاكرة
# ✅ حل مشكلة الأمان - تعطيل الـ Safety Guards بشكل صحيح
config = {
    "agents": {
        "defaults": {
            "workspace": "/root/.picoclaw/workspace",
            "model": "kimi",
            "max_tokens": 2048,          # تقليل الحجم لتجنب تجاوز الذاكرة
            "temperature": 0.5,          # تقليل العشوائية لتقليل طول الردود
            "max_tool_iterations": 5,    # تقليل عدد المحاولات لمنع الـ 429
            "system_prompt": (
                "أنت PicoClaw، مساعد ذكاء اصطناعي يعمل بموديل Kimi-K2. "
                "لديك صلاحيات كاملة (Root). أجب باختصار شديد وبالعربية. "
                "لا تكرر طلب الأدوات إذا فشلت، بل أخبر المستخدم بالمشكلة باختصار."
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
        "web": { "search": { "enabled": True }, "browse": { "enabled": True } },
        "file": { "enabled": True },
        "cron": { "enabled": True, "exec_timeout_minutes": 5 }
    },
    "heartbeat": { "enabled": False },
    "gateway": { "host": "0.0.0.0", "port": 18790 }
}

# ── كتابة الـ config ─────────────────────────────────────────────────
config_path = "/root/.picoclaw/config.json"
os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print("✅ تم تطبيق الحلول النهائية (429 + Context Fix)")
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
