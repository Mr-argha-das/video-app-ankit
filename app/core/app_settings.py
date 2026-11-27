"""Admin-configurable runtime settings (stored in `app_settings` collection).

Single document `{_id: "global", ...}`. Missing keys fall back to DEFAULTS, so
the app works out-of-the-box and admin only overrides what they need.
"""
from copy import deepcopy
from datetime import datetime

DEFAULTS = {
    # ---- Call flow ----
    "connecting_seconds": 10,              # "Calling… / Connecting…" screen duration
    "billing_tick_seconds": 5,             # how often the app syncs billing with server
    "heartbeat_grace_seconds": 45,         # no billing sync for this long => call auto-closed
    # ---- Incoming calls ----
    "incoming_call_enabled": True,
    "incoming_call_interval_seconds": 300,  # har 5 minute (app open & in use)
    "incoming_ring_timeout_seconds": 30,    # unanswered => missed
    # ---- Host message on call button ----
    # User kisi host ko video call kare → us host ka message turant Inbox chat me.
    # Placeholders: {user} {host} {price}. Host ka apna "call_message" ho toh woh use hota hai.
    "call_message_enabled": True,
    "call_message": "Hiii {user} 😍 Main {host}! Tumhari video call aa rahi hai — bas connect ho rahi hoon 💕 Call ke baad yahan chat bhi kar sakte ho!",
    # Balance kam ho tab call button dabane par
    "call_message_low_balance": "Aww {user} 🥺 Mujhse video call karni hai? Bas 🪙{price}/min chahiye — wallet recharge kar lo, main wait kar rahi hoon 💕",
    # ---- Priya page / bot ----
    # Host whose profile/video/bot-context powers the Priya page (optional).
    "priya_host_id": None,
    # Default persona when no host is linked (or host has no bot context).
    "priya_bot": {
        "name": "Priya",
        "greeting": "Heyy! Main Priya hoon 😊 Kaise ho aaj? Hindi, English ya Hinglish — jaise chaho baat karo!",
        "personality": (
            "Priya is a 24-year-old cheerful, warm and caring girl from Mumbai. "
            "She loves music (Arijit Singh), Bollywood movies, travelling and street food. "
            "She is a good listener, supportive and a little playful."
        ),
        "instructions": (
            "Keep replies short (1-3 sentences) and friendly. Ask a follow-up question "
            "to keep the conversation going. Occasionally invite the user to a video call "
            "with you from the Priya page, but don't be pushy."
        ),
    },
}

PUBLIC_KEYS = [
    "connecting_seconds",
    "billing_tick_seconds",
    "incoming_call_enabled",
    "incoming_call_interval_seconds",
    "incoming_ring_timeout_seconds",
    "priya_host_id",
]

# Validation limits for numeric settings: key -> (min, max)
NUMERIC_LIMITS = {
    "connecting_seconds": (0, 60),
    "billing_tick_seconds": (2, 60),
    "heartbeat_grace_seconds": (15, 600),
    "incoming_call_interval_seconds": (30, 3600),
    "incoming_ring_timeout_seconds": (10, 120),
}


def _merge(base: dict, override: dict) -> dict:
    out = deepcopy(base)
    for k, v in (override or {}).items():
        if k in ("_id", "updated_at"):
            continue
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _merge(out[k], v)
        elif v is not None or k == "priya_host_id":
            out[k] = v
    return out


async def get_app_settings(db) -> dict:
    doc = None
    try:
        doc = await db.app_settings.find_one({"_id": "global"})
    except Exception:
        doc = None
    return _merge(DEFAULTS, doc or {})


async def update_app_settings(db, patch: dict) -> dict:
    clean = {}
    for k, v in patch.items():
        if k not in DEFAULTS:
            continue
        if k in NUMERIC_LIMITS and v is not None:
            lo, hi = NUMERIC_LIMITS[k]
            v = int(max(lo, min(hi, int(v))))
        if k == "priya_bot" and isinstance(v, dict):
            for sub, val in v.items():
                if sub in DEFAULTS["priya_bot"]:
                    clean[f"priya_bot.{sub}"] = (val or "").strip()[:4000]
            continue
        if k == "priya_host_id":
            v = v or None
        if k in ("incoming_call_enabled", "call_message_enabled"):
            v = bool(v)
        if k in ("call_message", "call_message_low_balance"):
            v = (v or "").strip()[:500] or DEFAULTS[k]
        clean[k] = v
    clean["updated_at"] = datetime.utcnow()
    await db.app_settings.update_one({"_id": "global"}, {"$set": clean}, upsert=True)
    return await get_app_settings(db)
