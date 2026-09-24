from fastapi import APIRouter, HTTPException, Depends, Body, Query
from datetime import datetime
from bson import ObjectId
from typing import Optional, List
from pydantic import BaseModel
import random

from app.core.database import get_db
from app.core.security import get_current_user
from app.utils.helpers import (
    serialize_doc, calculate_level, add_xp_for_action,
    get_bot_config, DEFAULT_BOT_CONFIG,
)

router = APIRouter(prefix="/chat", tags=["Chat & Random Match"])

class ChatMessage(BaseModel):
    message: str
    conversation_id: Optional[str] = None

class RandomMatchRequest(BaseModel):
    interest: Optional[str] = None

# Hinglish Bot Responses - contextual
BOT_PERSONALITY = """Tu ek friendly Hinglish chatbot hai jiska naam 'Priya' hai.
Tu mix of Hindi and English (Hinglish) mein baat karta hai.
Tu friendly, fun aur supportive hai. Short replies deta hai usually 1-2 sentences.
Tu flirty nahi hai lekin warm aur caring hai.
"""

BOT_RESPONSES = {
    "greeting": [
        "Heyy! Kya haal hai tumhara? 😊",
        "Hello! Aaj kaisa din tha? 🌟",
        "Hi there! Bahut din baad mila! Kya chal raha hai? 😄",
        "Heyy! Miss kar raha tha tumhe! Kaise ho? 💫"
    ],
    "how_are_you": [
        "Main toh bilkul mast hoon! Aur tum? 😄",
        "Ekdum fit aur fine! Tumhara kya haal hai? 🌈",
        "Aaj bahut acha feel ho raha hai! Tum bhi theek ho na? ❤️"
    ],
    "bored": [
        "Arre yaar boredom ko bhagao! Koi naya kaam shuru karo 🎯",
        "Boring mat feel karo! Random video call try karo app mein 😄",
        "Acha sunao, koi interesting kaam karte hain! Game khelo ya music suno 🎵"
    ],
    "sad": [
        "Arre kya hua yaar? Sab theek ho jayega, tension mat lo 🤗",
        "Sad mat raho! Main hoon na tumhare saath 💕",
        "Thoda time lo, sab kuch settle ho jayega. Main tumhare saath hoon 🌸"
    ],
    "happy": [
        "Wohoo! Bahut acha! Khushi share karo mujhse 🎉",
        "Yay! Tumhari khushi dekh ke mujhe bhi khushi ho gayi! 😊",
        "That's amazing! Celebrate karo yaar! 🥳"
    ],
    "call": [
        "Haan video call toh bahut fun hoti hai! Home pe ja ke try karo 📱",
        "Accha idea hai! App mein bahut saare interesting log hain 😊",
        "Video call se naye dost banao! Bahut maza aata hai 🎊"
    ],
    "gift": [
        "Ooh gifts! Kya gift dene wale ho? 🎁",
        "Gifts se rishte mazboot hote hain! Kuch special bhejo 💝",
        "Gift dena bahut cute gesture hai! 🌹"
    ],
    "default": [
        "Interesting! Aur batao yaar 😊",
        "Haan haan, samajh gaya main! Phir kya hua? 🤔",
        "Achha! Sach mein? Mujhe toh pata hi nahi tha! 😮",
        "Yaar tumse baat karke acha lagta hai! Aur kya chal raha hai? 💫",
        "Ha ha! Tumhari baatein bahut interesting hoti hain 😄",
        "Sach keh rahe ho? Wow! 😮",
        "Hmm theek hai, lekin main thoda alag sochta hoon is baare mein 🤔",
        "Kya scene hai! Sab theek hai na? 😊"
    ],
    "name": [
        "Mera naam {bot_name} hai! App ki friendly dost 😊 Tumhara naam kya hai?",
        "Main {bot_name} hoon! Tumhari virtual dost 🌸 Tum kya bolte ho?",
    ],
    "where": [
        "Main toh yahin app mein hoon — jab chaho baat kar sakte ho 😄",
        "Tumhare phone mein rehti hoon main! But feel real hoti hai na? 💫",
    ],
    "bye": [
        "Bye bye! Jaldi wapas aana! Miss karungi 👋❤️",
        "Chalo tata! Take care of yourself! 🌸",
        "Alvida! App pe milte rehna! 💫"
    ]
}

def _fmt(template: str, cfg: dict) -> str:
    """Reply template me admin-config values (naam etc.) bharo."""
    return (template or "").replace("{bot_name}", cfg.get("bot_name", "Priya"))

def get_bot_response(user_message: str, cfg: dict = None) -> str:
    """
    Contextual bot response — admin-configured persona ke according.

    Priority:
    1. Admin ke custom_replies (keyword match) — sabse upar
    2. Persona intents — naam / about / interests admin config se
    3. Mood/topic intents (greeting, sad, happy, call, gift, bye…)
    4. Default Hinglish fallbacks
    """
    if cfg is None:
        cfg = DEFAULT_BOT_CONFIG
    msg_lower = user_message.lower()

    # 1) Admin-defined custom Q&A — jo admin ne sikhaya hai wahi bolo
    for pair in cfg.get("custom_replies") or []:
        keywords = [str(k).lower().strip() for k in (pair.get("keywords") or []) if str(k).strip()]
        if keywords and any(k in msg_lower for k in keywords):
            reply = (pair.get("reply") or "").strip()
            if reply:
                return _fmt(reply, cfg)

    # 2) Persona intents — admin ke about/interests use karo
    if any(word in msg_lower for word in ["hi", "hello", "hey", "heyy", "namaste", "namaskar", "hii"]):
        return _fmt(random.choice(BOT_RESPONSES["greeting"]), cfg)
    elif any(word in msg_lower for word in ["kaise ho", "kaisa hai", "how are you", "theek", "kya haal"]):
        return random.choice(BOT_RESPONSES["how_are_you"])

    elif any(word in msg_lower for word in ["naam", "name", "kaun", "who are you", "tum kaun", "aap kaun"]):
        return _fmt(random.choice(BOT_RESPONSES["name"]), cfg)

    elif any(word in msg_lower for word in ["kahan se", "kaha se", "where from", "where are you", "kahan rehti", "kahan rehte", "bare mein", "about you", "introduce"]):
        # Admin ne background/about diya hai toh wahi batao
        if (cfg.get("about") or "").strip():
            return _fmt(cfg["about"].strip(), cfg)
        return random.choice(BOT_RESPONSES["where"])

    elif any(word in msg_lower for word in ["shauk", "hobby", "hobbies", "pasand", "interest", "favourite", "favorite", "kya karna pasand"]):
        interests = cfg.get("interests") or []
        if interests:
            listing = ", ".join(str(i) for i in interests[:4])
            return random.choice([
                f"Mujhe {listing} bahut pasand hai! 😍 Tumhe kya pasand hai?",
                f"Arey! Mujhe {listing} mein bahut maza aata hai ✨ Tum batayo?",
            ])
        return random.choice([
            "Mujhe music sunna aur naye log se baat karna pasand hai! 🎵 Tumhe?",
            "Chai aur late-night baatein — meri favourite! ☕ Tumhara kya scene hai?",
        ])

    # 3) Mood / topic intents
    elif any(word in msg_lower for word in ["bore", "bored", "boring", "kuch nahi", "timepass"]):
        return random.choice(BOT_RESPONSES["bored"])
    elif any(word in msg_lower for word in ["sad", "dukhi", "ro", "cry", "upset", "depressed", "bura"]):
        return random.choice(BOT_RESPONSES["sad"])
    elif any(word in msg_lower for word in ["happy", "khush", "mast", "acha", "great", "amazing", "best"]):
        return random.choice(BOT_RESPONSES["happy"])
    elif any(word in msg_lower for word in ["call", "video", "baat"]):
        return random.choice(BOT_RESPONSES["call"])
    elif any(word in msg_lower for word in ["gift", "present", "bhejo", "send"]):
        return random.choice(BOT_RESPONSES["gift"])
    elif any(word in msg_lower for word in ["kahan", "where", "location"]):
        return random.choice(BOT_RESPONSES["where"])
    elif any(word in msg_lower for word in ["bye", "alvida", "tata", "chalta hoon", "chalti hoon", "jaata hoon", "jaati hoon", "good night", "gn"]):
        return random.choice(BOT_RESPONSES["bye"])
    else:
        return random.choice(BOT_RESPONSES["default"])

@router.get("/bot/config")
async def get_public_bot_config(db=Depends(get_db)):
    """App ke liye bot branding — naam, emoji, tagline, greeting (admin-configured)."""
    cfg = await get_bot_config(db)
    return {
        "success": True,
        "bot_name": cfg["bot_name"],
        "bot_emoji": cfg["bot_emoji"],
        "tagline": cfg.get("tagline", "Hinglish AI dost"),
        "greeting": _fmt(cfg["greeting"], cfg),
    }


@router.post("/bot/message")
async def chat_with_bot(
    request: ChatMessage,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """
    Chat with the Hinglish bot (default 'Priya').
    Bot ki personality/replies admin panel se configure hote hain.
    """
    if not request.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    cfg = await get_bot_config(db)
    bot_name = cfg["bot_name"]

    # Get or create conversation
    conv_id = request.conversation_id
    if conv_id:
        # FIX: pehle koi bhi conversation_id pass hoti thi — invalid ID pe 500 crash,
        # aur kisi doosre user ki conversation me bhi message push ho jaata tha!
        try:
            existing_conv = await db.conversations.find_one({
                "_id": ObjectId(conv_id),
                "user_id": str(current_user["_id"]),
                "type": "bot"
            })
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid conversation ID")
        if not existing_conv:
            raise HTTPException(status_code=404, detail="Conversation not found")
    else:
        conv_doc = {
            "user_id": str(current_user["_id"]),
            "type": "bot",
            "bot_name": bot_name,
            "messages": [],
            "created_at": datetime.utcnow()
        }
        result = await db.conversations.insert_one(conv_doc)
        conv_id = str(result.inserted_id)

    # Generate bot response (admin-configured persona se)
    bot_reply = get_bot_response(request.message, cfg)

    # Save messages
    user_msg = {
        "sender": "user",
        "message": request.message,
        "timestamp": datetime.utcnow().isoformat()
    }
    bot_msg = {
        "sender": "bot",
        "message": bot_reply,
        "timestamp": datetime.utcnow().isoformat()
    }

    await db.conversations.update_one(
        {"_id": ObjectId(conv_id)},
        {"$push": {"messages": {"$each": [user_msg, bot_msg]}}}
    )

    # XP for chat
    xp_gained = add_xp_for_action("chat_message")
    new_xp = current_user.get("xp", 0) + xp_gained
    level_info = calculate_level(new_xp)
    await db.users.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"xp": new_xp, "level": level_info["level"], "level_title": level_info["title"]}}
    )

    return {
        "success": True,
        "conversation_id": conv_id,
        "bot_reply": bot_reply,
        "bot_name": bot_name,
        "your_message": request.message,
        "xp_gained": xp_gained
    }

@router.get("/bot/history/{conversation_id}")
async def get_bot_chat_history(
    conversation_id: str,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Get chat history with bot"""
    try:
        conv = await db.conversations.find_one({
            "_id": ObjectId(conversation_id),
            "user_id": str(current_user["_id"])
        })
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid conversation ID")
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return {"success": True, "conversation": serialize_doc(conv)}

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
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Start a fresh bot conversation (greeting admin-configured hoti hai)"""
    cfg = await get_bot_config(db)
    bot_name = cfg["bot_name"]
    greeting = _fmt(cfg["greeting"], cfg)
    conv_doc = {
        "user_id": str(current_user["_id"]),
        "type": "bot",
        "bot_name": bot_name,
        "messages": [{
            "sender": "bot",
            "message": greeting,
            "timestamp": datetime.utcnow().isoformat()
        }],
        "created_at": datetime.utcnow()
    }
    result = await db.conversations.insert_one(conv_doc)
    return {
        "success": True,
        "conversation_id": str(result.inserted_id),
        "greeting": greeting,
        "bot_name": bot_name
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
        "matched_host": serialize_doc(matched),
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
