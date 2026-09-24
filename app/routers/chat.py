from fastapi import APIRouter, HTTPException, Depends, Query
from datetime import datetime
from bson import ObjectId
from typing import Optional, List
from pydantic import BaseModel, Field
from pymongo import ReturnDocument
import random

from app.core.database import get_db
from app.core.security import get_current_user, get_current_admin
from app.core.app_settings import get_app_settings
from app.utils.helpers import serialize_doc, calculate_level, add_xp_for_action
from app.services.ai_bot import generate_reply, ai_configured, build_system_prompt
from app.routers.hosts import public_host

router = APIRouter(prefix="/chat", tags=["Chat & Random Match"])

MAX_MESSAGE_LEN = 1000


class ChatMessage(BaseModel):
    message: str
    conversation_id: Optional[str] = None
    # Kis host/persona se baat karni hai. None = Priya page ka default persona.
    host_id: Optional[str] = None

class NewSessionRequest(BaseModel):
    host_id: Optional[str] = None

class RandomMatchRequest(BaseModel):
    interest: Optional[str] = None

class BotTestRequest(BaseModel):
    message: str
    host_id: Optional[str] = None
    history: List[dict] = Field(default_factory=list)


# ======================= PERSONA =======================

async def resolve_persona(db, host_id: Optional[str] = None, *, admin: bool = False) -> dict:
    """Build the bot persona from admin configuration.

    host_id given      → that host's profile + bot context.
    host_id None       → Priya page default: linked `priya_host_id` host (if any),
                         merged with the global Priya persona from App Settings.
    """
    cfg = await get_app_settings(db)
    default = cfg["priya_bot"]
    is_default = not host_id
    hid = host_id or cfg.get("priya_host_id")

    host = None
    if hid:
        try:
            q = {"_id": ObjectId(hid)}
            if not admin:
                q["is_active"] = True
            host = await db.host_users.find_one(q)
        except Exception:
            if not is_default:
                raise HTTPException(status_code=400, detail="Invalid host ID")
        if not host and not is_default:
            raise HTTPException(status_code=404, detail="Host not found")

    if host:
        if not is_default and not admin and not host.get("bot_enabled", True):
            raise HTTPException(status_code=403, detail="Chat is not available for this host")
        name = host.get("name") or default["name"]
        greeting = host.get("bot_greeting") or (
            default["greeting"] if is_default and name == default["name"]
            else f"Heyy! Main {name} hoon 😊 Kaise ho? Hindi, English ya Hinglish — jaise chaho baat karo!"
        )
        personality = host.get("bot_personality") or (default["personality"] if is_default else "")
        instructions = host.get("bot_instructions") or default["instructions"]
        return {
            "host_id": str(host["_id"]),
            "is_default": is_default,
            "name": name,
            "avatar": host.get("profile_picture"),
            "greeting": greeting,
            "personality": personality,
            "instructions": instructions,
            "age": host.get("age"),
            "gender": host.get("gender"),
            "city": host.get("city"),
            "language": host.get("language"),
            "interests": host.get("interests") or [],
            "bio": host.get("bio"),
            "description": host.get("description"),
            "price_per_minute": host.get("price_per_minute"),
            "host": host,
        }

    return {
        "host_id": None,
        "is_default": True,
        "name": default["name"],
        "avatar": None,
        "greeting": default["greeting"],
        "personality": default["personality"],
        "instructions": default["instructions"],
        "gender": "female",
        "interests": [],
        "host": None,
    }


def persona_public(p: dict) -> dict:
    return {
        "name": p["name"],
        "host_id": p.get("host_id"),
        "is_default": p.get("is_default", False),
        "avatar": p.get("avatar"),
        "greeting": p["greeting"],
        "host": public_host(p["host"]) if p.get("host") else None,
        "ai_powered": ai_configured(),
    }


async def _get_owned_conversation(db, conv_id: str, user_id: str) -> dict:
    try:
        conv = await db.conversations.find_one({"_id": ObjectId(conv_id), "user_id": user_id, "type": "bot"})
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid conversation ID")
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return conv


async def _create_conversation(db, user_id: str, persona: dict, conv_host_id: Optional[str],
                               first_message: Optional[dict] = None) -> dict:
    now = datetime.utcnow()
    conv_doc = {
        "user_id": user_id,
        "type": "bot",
        "host_id": conv_host_id,          # None = Priya default persona
        "bot_name": persona["name"],
        "messages": [first_message or {
            "sender": "bot",
            "message": persona["greeting"],
            "timestamp": now.isoformat(),
        }],
        "unread": 1 if first_message else 0,
        "created_at": now,
        "updated_at": now,
    }
    result = await db.conversations.insert_one(conv_doc)
    conv_doc["_id"] = result.inserted_id
    return conv_doc


async def _latest_conversation(db, user_id: str, conv_host_id: Optional[str]) -> Optional[dict]:
    """User ki us host ke saath sabse recent chat (Inbox thread)."""
    convs = await db.conversations.find(
        {"user_id": user_id, "type": "bot", "host_id": conv_host_id}
    ).sort([("updated_at", -1), ("created_at", -1)]).limit(1).to_list(1)
    return convs[0] if convs else None


def _fill_template(tpl: str, user: dict, host: dict) -> str:
    price = host.get("price_per_minute") or 0
    first = ((user.get("name") or "").strip().split(" ") or [""])[0] or "dear"
    return (tpl.replace("{user}", first)
               .replace("{host}", host.get("name") or "")
               .replace("{price}", f"{float(price):g}"))


async def push_host_message(db, user: dict, host: dict, kind: str = "call") -> Optional[dict]:
    """Host ki taraf se user ke Inbox me message daalo (e.g. user ne video call button dabaya).

    Latest thread me append hota hai (na ho toh naya thread), unread +1.
    Returns the message dict (or None if disabled / host chat off).
    """
    try:
        cfg = await get_app_settings(db)
        if not cfg.get("call_message_enabled", True) or not host.get("bot_enabled", True):
            return None
        if kind == "low_balance":
            tpl = cfg.get("call_message_low_balance") or ""
        else:
            tpl = (host.get("call_message") or "").strip() or cfg.get("call_message") or ""
        text = _fill_template(tpl, user, host).strip()
        if not text:
            return None
        uid = str(user["_id"])
        hid = str(host["_id"])
        msg = {"sender": "bot", "message": text, "timestamp": datetime.utcnow().isoformat(), "kind": kind}
        conv = await _latest_conversation(db, uid, hid)
        if conv:
            # Double-tap / baar baar button → same message 60 sec me dobara nahi
            last = (conv.get("messages") or [{}])[-1]
            if last.get("kind") == kind:
                try:
                    age = (datetime.utcnow() - datetime.fromisoformat(last.get("timestamp"))).total_seconds()
                except Exception:
                    age = 9999
                if age < 60:
                    return {**last, "conversation_id": str(conv["_id"]), "host_id": hid,
                            "host_name": host.get("name"), "duplicate": True}
            await db.conversations.update_one(
                {"_id": conv["_id"]},
                {"$push": {"messages": msg}, "$inc": {"unread": 1},
                 "$set": {"updated_at": datetime.utcnow(), "bot_name": host.get("name")}},
            )
        else:
            persona = {"name": host.get("name") or "Host", "greeting": text}
            conv = await _create_conversation(db, uid, persona, hid, first_message=msg)
        return {**msg, "conversation_id": str(conv["_id"]), "host_id": hid, "host_name": host.get("name")}
    except Exception:
        return None  # message fail hone se call kabhi nahi rukni chahiye


# ======================= BOT ENDPOINTS =======================

@router.get("/bot/persona")
async def get_bot_persona(
    host_id: Optional[str] = Query(None),
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Priya page header info: persona name, avatar, greeting + linked host (for video call)."""
    persona = await resolve_persona(db, host_id)
    return {"success": True, "persona": persona_public(persona)}


@router.post("/bot/message")
async def chat_with_bot(
    request: ChatMessage,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """
    Chat with the Priya-page AI bot. Understands & replies in Hindi, English or
    Hinglish, using the persona/instructions configured by admin.
    """
    text = (request.message or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Message cannot be empty")
    if len(text) > MAX_MESSAGE_LEN:
        raise HTTPException(status_code=400, detail=f"Message too long (max {MAX_MESSAGE_LEN} characters)")

    user_id = str(current_user["_id"])
    if request.conversation_id:
        conv = await _get_owned_conversation(db, request.conversation_id, user_id)
        conv_host_id = conv.get("host_id")
        persona = await resolve_persona(db, conv_host_id)
    else:
        conv_host_id = request.host_id or None
        persona = await resolve_persona(db, conv_host_id)
        conv = await _create_conversation(db, user_id, persona, conv_host_id)
    conv_id = str(conv["_id"])

    result = await generate_reply(persona, conv.get("messages") or [], text)
    bot_reply = result["reply"]

    now = datetime.utcnow().isoformat()
    await db.conversations.update_one(
        {"_id": conv["_id"]},
        {
            "$push": {"messages": {"$each": [
                {"sender": "user", "message": text, "timestamp": now},
                {"sender": "bot", "message": bot_reply, "timestamp": now,
                 "ai_powered": result["ai_powered"], "language": result["language"]},
            ]}},
            "$set": {"updated_at": datetime.utcnow(), "bot_name": persona["name"]},
        }
    )

    # XP for chat (atomic $inc — pehle stale value overwrite hoti thi)
    xp_gained = add_xp_for_action("chat_message")
    user = await db.users.find_one_and_update(
        {"_id": current_user["_id"]}, {"$inc": {"xp": xp_gained}}, return_document=ReturnDocument.AFTER
    )
    if user:
        level_info = calculate_level(user.get("xp", 0))
        await db.users.update_one(
            {"_id": current_user["_id"]},
            {"$set": {"level": level_info["level"], "level_title": level_info["title"]}}
        )

    return {
        "success": True,
        "conversation_id": conv_id,
        "bot_reply": bot_reply,
        "bot_name": persona["name"],
        "host_id": persona.get("host_id"),
        "your_message": text,
        "language": result["language"],
        "ai_powered": result["ai_powered"],
        "xp_gained": xp_gained
    }


@router.get("/bot/history/{conversation_id}")
async def get_bot_chat_history(
    conversation_id: str,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Get chat history with bot"""
    conv = await _get_owned_conversation(db, conversation_id, str(current_user["_id"]))
    if conv.get("unread"):
        await db.conversations.update_one({"_id": conv["_id"]}, {"$set": {"unread": 0}})
        conv["unread"] = 0
    return {"success": True, "conversation": serialize_doc(conv)}


@router.get("/bot/thread")
async def get_bot_thread(
    host_id: Optional[str] = Query(None),
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Open a chat from the Inbox: latest thread with this host (created if none) +
    persona. Marks the thread as read."""
    persona = await resolve_persona(db, host_id or None)
    uid = str(current_user["_id"])
    conv_host_id = host_id or None
    conv = await _latest_conversation(db, uid, conv_host_id)
    if not conv:
        conv = await _create_conversation(db, uid, persona, conv_host_id)
    elif conv.get("unread"):
        await db.conversations.update_one({"_id": conv["_id"]}, {"$set": {"unread": 0}})
    return {
        "success": True,
        "conversation_id": str(conv["_id"]),
        "messages": conv.get("messages") or [],
        "persona": persona_public(persona),
    }


@router.get("/inbox")
async def chat_inbox(
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Inbox: saare chat-enabled hosts + har host ke saath last message & unread count.
    Recent chats upar, baaki hosts (online pehle) neeche."""
    uid = str(current_user["_id"])
    cfg = await get_app_settings(db)
    hosts = await db.host_users.find(
        {"is_active": True, "bot_enabled": {"$ne": False}}
    ).to_list(300)
    convs = await db.conversations.find({"user_id": uid, "type": "bot"}).to_list(500)

    def last_ts(c):
        msgs = c.get("messages") or []
        ts = msgs[-1].get("timestamp") if msgs else None
        return ts or (c.get("updated_at") or c.get("created_at") or datetime.min).isoformat()

    latest = {}
    unread = {}
    for c in convs:
        key = c.get("host_id")
        unread[key] = unread.get(key, 0) + int(c.get("unread") or 0)
        if key not in latest or last_ts(c) > last_ts(latest[key]):
            latest[key] = c

    def item(host_key, name, avatar, host_doc):
        c = latest.get(host_key)
        last = (c.get("messages") or [{}])[-1] if c else {}
        return {
            "host_id": host_key,
            "name": name,
            "avatar": avatar,
            "is_online": bool(host_doc.get("is_online")) if host_doc else True,
            "host": public_host(host_doc) if host_doc else None,
            "conversation_id": str(c["_id"]) if c else None,
            "last_message": last.get("message"),
            "last_sender": last.get("sender"),
            "last_time": last_ts(c) if c else None,
            "unread": unread.get(host_key, 0),
        }

    items = [item(str(h["_id"]), h.get("name"), h.get("profile_picture"), h) for h in hosts]
    # Default Priya persona (jab koi host linked nahi) — pinned
    pinned = []
    if not cfg.get("priya_host_id"):
        pb = cfg["priya_bot"]
        pinned.append(item(None, pb["name"], None, None))

    with_chat = sorted([i for i in items if i["last_time"]], key=lambda i: i["last_time"], reverse=True)
    without = sorted([i for i in items if not i["last_time"]], key=lambda i: (not i["is_online"], (i["name"] or "").lower()))
    result = pinned + with_chat + without
    return {
        "success": True,
        "items": result,
        "total_unread": sum(i["unread"] for i in result),
    }


@router.get("/bot/my-conversations")
async def my_bot_conversations(
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Get all bot conversations"""
    convs = await db.conversations.find(
        {"user_id": str(current_user["_id"]), "type": "bot"}
    ).sort("created_at", -1).limit(20).to_list(20)
    return {"success": True, "conversations": [serialize_doc(c) for c in convs]}


@router.post("/bot/new-session")
async def start_new_bot_session(
    request: Optional[NewSessionRequest] = None,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Start a fresh bot conversation (optionally with a specific host persona)"""
    host_id = (request.host_id if request else None) or None
    persona = await resolve_persona(db, host_id)
    conv = await _create_conversation(db, str(current_user["_id"]), persona, host_id)
    return {
        "success": True,
        "conversation_id": str(conv["_id"]),
        "greeting": persona["greeting"],
        "bot_name": persona["name"],
        "persona": persona_public(persona),
    }


@router.post("/admin/bot-test")
async def admin_bot_test(
    request: BotTestRequest,
    db=Depends(get_db),
    admin=Depends(get_current_admin),
):
    """Admin: preview how the bot replies with the current configuration (nothing is saved)."""
    if not request.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")
    persona = await resolve_persona(db, request.host_id or None, admin=True)
    history = [m for m in request.history if isinstance(m, dict)][-20:]
    result = await generate_reply(persona, history, request.message.strip())
    return {
        "success": True,
        "reply": result["reply"],
        "ai_powered": result["ai_powered"],
        "language": result["language"],
        "persona_name": persona["name"],
        "system_prompt": build_system_prompt(persona),
    }

# ========== RANDOM MATCH ==========

@router.post("/random-match")
async def random_match(
    request: RandomMatchRequest,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """
    Random match - finds a random online host to connect with.
    Can filter by interest.
    """
    if current_user.get("is_guest"):
        raise HTTPException(status_code=403, detail="Guests cannot use random match. Please register.")

    query = {"is_active": True, "is_online": True}
    if request.interest:
        query["interests"] = {"$in": [request.interest]}

    hosts = await db.host_users.find(query).to_list(100)
    if not hosts:
        # If no filtered match, try without filter
        hosts = await db.host_users.find({"is_active": True, "is_online": True}).to_list(100)

    if not hosts:
        return {
            "success": False,
            "message": "Abhi koi available nahi hai. Thodi der baad try karo! 😊"
        }

    matched = random.choice(hosts)
    return {
        "success": True,
        "message": f"Match mila! {matched['name']} ke saath connect ho 🎉",
        "matched_host": public_host(matched),
        "price_per_minute": matched["price_per_minute"],
        "action": "initiate_call"
    }

@router.get("/random-match/interests")
async def get_popular_interests(db=Depends(get_db)):
    """Get popular interests for random match filter"""
    pipeline = [
        {"$unwind": "$interests"},
        {"$group": {"_id": "$interests", "count": {"$sum": 1}}},
        {"$sort": {"count": -1}},
        {"$limit": 20}
    ]
    result = await db.host_users.aggregate(pipeline).to_list(20)
    interests = [r["_id"] for r in result if r["_id"]]
    return {"success": True, "interests": interests}
