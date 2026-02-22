# ╔══════════════════════════════════════════════════════════════════════╗
# ║         PicoClaw — Railway Dockerfile  ✅ ملف واحد بس               ║
# ║  Model  : moonshotai/kimi-k2-instruct  (NVIDIA NIM)                 ║
# ║  Channel: Telegram                                                   ║
# ╠══════════════════════════════════════════════════════════════════════╣
# ║  🔑 أضف في Railway → Variables:                                     ║
# ║                                                                      ║
# ║  NVIDIA_KEY           = nvapi-xxxx...        ← إجباري               ║
# ║  TELEGRAM_BOT_TOKEN   = 1234567:AAxx...      ← إجباري               ║
# ║  TELEGRAM_ALLOWED_IDS = @yourusername        ← اختياري              ║
# ║                                                                      ║
# ║  ⚠️ مهم جداً لـ TELEGRAM_ALLOWED_IDS:                               ║
# ║  استخدم @username (مش الـ numeric ID) — Bug #62                     ║
# ║  مثال: @ahmed أو @ahmed,@sara لأكتر من شخص                         ║
# ║  أو اتركه فاضي عشان تسمح للكل                                       ║
# ╚══════════════════════════════════════════════════════════════════════╝

# ═══════════════════════════════════════════════════════════════════════
# Stage 1: Build من السورس الرسمي
# go.mod يطلب Go 1.21+ ← نستخدم 1.21-alpine للاستقرار
# ═══════════════════════════════════════════════════════════════════════
FROM golang:1.21-alpine AS builder

# git لازم لـ make deps (go modules) + make لبناء المشروع
RUN apk add --no-cache git make

WORKDIR /src

# Clone آخر نسخة وابني
# make deps → go get -u ./... && go mod tidy
# make build → بيطلع build/picoclaw-linux-amd64 + symlink build/picoclaw
RUN git clone --depth=1 https://github.com/sipeed/picoclaw.git . \
    && make deps \
    && make build \
    && echo "✅ Build output:" \
    && ls -lh build/

# ═══════════════════════════════════════════════════════════════════════
# Stage 2: Runtime Image
# python:3.12-alpine = python3 + alpine (خفيف + كافي)
# ═══════════════════════════════════════════════════════════════════════
FROM python:3.12-alpine

RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    curl \
    bash

# ── نسخ الـ binary مباشرة (مش الـ symlink عشان ممكن ميتنسخش صح) ──
COPY --from=builder /src/build/picoclaw-linux-amd64 /usr/local/bin/picoclaw
RUN chmod +x /usr/local/bin/picoclaw

# ── تشغيل onboard عشان ينشئ الـ workspace structure الرسمي ──
# ينشئ: ~/.picoclaw/config.json + workspace/sessions,memory,cron,skills
# + ملفات: AGENTS.md, IDENTITY.md, SOUL.md, TOOLS.md, USER.md
# ملاحظة: الـ config.json اللي بتنشئه onboard هيتكتب فوقه Python script
RUN /usr/local/bin/picoclaw onboard \
    && echo "✅ Workspace created:" \
    && ls /root/.picoclaw/ \
    && ls /root/.picoclaw/workspace/

# ═══════════════════════════════════════════════════════════════════════
# Python Startup Script
# بيشتغل وقت تشغيل الـ container (مش وقت البناء)
# عشان يقرأ الـ Railway Variables اللي مش متاحة وقت البناء
# ═══════════════════════════════════════════════════════════════════════
RUN cat > /start.py << 'PYEOF'
#!/usr/bin/env python3
"""
PicoClaw Startup Script — NVIDIA NIM + Telegram
=================================================
1. يتحقق من Railway Variables
2. يبني config.json الصح
3. يشغل picoclaw gateway
"""
import os, json, sys

# ── Banner ──────────────────────────────────────────────────────────
print()
print("╔══════════════════════════════════════════════════╗")
print("║   🤖  PicoClaw — Kimi-K2 via NVIDIA NIM         ║")
print("║   💬  Channel: Telegram                         ║")
print("╚══════════════════════════════════════════════════╝")
print()

# ── قراءة الـ Railway Variables ─────────────────────────────────────
nvidia_key     = os.environ.get("NVIDIA_KEY", "").strip()
telegram_token = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
allowed_raw    = os.environ.get("TELEGRAM_ALLOWED_IDS", "").strip()

# ── التحقق من الإجباريات ────────────────────────────────────────────
missing = []
if not nvidia_key:
    missing.append("NVIDIA_KEY")
if not telegram_token:
    missing.append("TELEGRAM_BOT_TOKEN")

if missing:
    print("❌ خطأ: Variables ناقصة في Railway → Variables:")
    for v in missing:
        print(f"   ✗ {v}")
    print()
    print("📌 الخطوات:")
    print("   1. افتح الـ project في Railway")
    print("   2. Variables → New Variable")
    print("   3. أضف المتغيرين المذكورين")
    print()
    sys.exit(1)

# ── معالجة TELEGRAM_ALLOWED_IDS ─────────────────────────────────────
# ⚠️ BUG #62 في picoclaw:
#    الـ numeric IDs مش بتشتغل لو عندك Telegram username
#    السبب: picoclaw بيبني الـ senderID كـ "123456789|myusername"
#    وبعدين بيعمل exact match — فـ "123456789" مش هيـ match
#
# الحل:
#    استخدم @username بدل الـ numeric ID في TELEGRAM_ALLOWED_IDS
#    مثال: @ahmed أو @ahmed,@sara
#    أو اتركه فاضي عشان تسمح للكل
#
# تنبيه تلقائي لو حد حط numeric ID
allow_from = []
if allowed_raw:
    raw_ids = [x.strip() for x in allowed_raw.split(",") if x.strip()]
    numeric_ids = [x for x in raw_ids if x.isdigit()]
    if numeric_ids:
        print("⚠️  تحذير: لقيت Numeric IDs في TELEGRAM_ALLOWED_IDS:")
        for nid in numeric_ids:
            print(f"   - '{nid}' قد لا تشتغل (Bug #62)")
        print("   💡 الحل: استخدم @username بدلاً من الـ numeric ID")
        print("      أو اتركه فاضي عشان تسمح للكل")
        print()
    allow_from = raw_ids

# ── بناء config.json ─────────────────────────────────────────────────
#
# ✅ قرارات مبنية على source code + Issues الرسمية:
#
# 1. model_list (الـ format الجديد الموصى به)
#    الـ "providers" deprecated وفيه Bug #127 مع custom api_base
#
# 2. "model": "openai/moonshotai/kimi-k2-instruct"
#    format: "vendor/model-name"
#    picoclaw بيشيل "openai/" prefix قبل ما يبعت للـ API
#    فـ NVIDIA NIM هيستقبل: "moonshotai/kimi-k2-instruct" ✓
#
# 3. "allowFrom" (camelCase) للـ Telegram
#    مؤكد من: README الرسمي + picoclaw-labs + EMSI + مصادر متعددة
#
# 4. workspace path: مطلق مش relative
#    "~/.picoclaw/workspace" ممكن تفشل في بعض Docker contexts
#    "/root/.picoclaw/workspace" مضمونة دايماً
#
# 5. gateway.host = "0.0.0.0"
#    بدونه Railway مش هيقدر يوصل للـ healthcheck
#    مؤكد من Issue #127 config
#
config = {
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
            "api_key": nvidia_key
        }
    ],
    "channels": {
        "telegram": {
            "enabled": True,
            "token": telegram_token,
            "allowFrom": allow_from
        }
    },
    "tools": {
        "web": {
            "search": {
                "enabled": False
            }
        },
        "cron": {
            "exec_timeout_minutes": 5
        }
    },
    "heartbeat": {
        "enabled": False
    },
    "gateway": {
        "host": "0.0.0.0",
        "port": 18790
    }
}

# ── كتابة الـ config فوق الـ default اللي عملته onboard ─────────────
config_path = "/root/.picoclaw/config.json"
os.makedirs(os.path.dirname(config_path), exist_ok=True)

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

# ── تأكيد نهائي ────────────────────────────────────────────────────
print("✅ Config جاهز")
print()
print("📊 إعدادات البوت:")
print(f"   🤖 Model    : moonshotai/kimi-k2-instruct")
print(f"   🔌 API      : NVIDIA NIM")
print(f"   🌐 Endpoint : https://integrate.api.nvidia.com/v1")
print(f"   💬 Channel  : Telegram")
print(f"   👥 Allowed  : {', '.join(allow_from) if allow_from else 'الكل (allow all)'}")
print(f"   🏠 Gateway  : 0.0.0.0:18790")
print(f"   📁 Workspace: /root/.picoclaw/workspace")
print()

# ── فحص الـ binary ──────────────────────────────────────────────────
import subprocess
try:
    r = subprocess.run(
        ["/usr/local/bin/picoclaw", "version"],
        capture_output=True, text=True, timeout=5
    )
    version = (r.stdout + r.stderr).strip()
    if version:
        print(f"   📦 Version  : {version}")
        print()
except Exception:
    pass

print("🚀 تشغيل PicoClaw Gateway...")
print("══════════════════════════════════════════════════")
print()
sys.stdout.flush()

# ── تشغيل البوت ──────────────────────────────────────────────────────
# os.execv يحل محل الـ Python process (أكفأ من subprocess)
# البوت هيشتغل ويفضل شغال حتى لو Railway عمل restart
os.execv("/usr/local/bin/picoclaw", ["/usr/local/bin/picoclaw", "gateway"])
PYEOF

RUN chmod +x /start.py

# ── HealthCheck ───────────────────────────────────────────────────────
# /health endpoint رسمي في picoclaw (PR #104)
# Railway بيستخدمه عشان يعرف الـ container شغال
HEALTHCHECK \
    --interval=30s \
    --timeout=10s \
    --start-period=30s \
    --retries=3 \
    CMD wget -qO- http://localhost:18790/health 2>/dev/null || exit 1

EXPOSE 18790

ENTRYPOINT ["python3", "/start.py"]
