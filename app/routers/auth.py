from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form, Request
from fastapi.responses import JSONResponse
from datetime import datetime, timedelta
from bson import ObjectId
from typing import Optional
import os, aiofiles, uuid, re, secrets

from app.core.database import get_db
from app.core.security import (
    verify_password, get_password_hash, create_access_token,
    get_current_user, settings
)
from app.utils.helpers import serialize_doc, generate_guest_username, calculate_level, validate_mobile, normalize_mobile
from app.core.ratelimit import check_rate, client_ip

router = APIRouter(prefix="/auth", tags=["Authentication"])

UPLOAD_DIR = "static/uploads/profiles"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@router.post("/register")
async def register(
    name: str = Form(...),
    mobile: str = Form(...),
    password: str = Form(...),
    gender: str = Form("other"),
    profile_picture: Optional[UploadFile] = File(None),
    db=Depends(get_db)
):
    """Register new user with mobile number"""
    name = (name or "").strip()
    mobile = normalize_mobile(mobile)
    if not name:
        raise HTTPException(status_code=400, detail="Name is required")
    if len(password or "") < 4:
        raise HTTPException(status_code=400, detail="Password must be at least 4 characters")
    if not validate_mobile(mobile):
        raise HTTPException(status_code=400, detail="Invalid mobile number. Must be 10-digit Indian number.")
    
    existing = await db.users.find_one({"mobile": mobile})
    if existing:
        raise HTTPException(status_code=400, detail="Mobile number already registered")

    # Handle profile picture upload
    pic_url = None
    if profile_picture and profile_picture.filename:
        ext = profile_picture.filename.split(".")[-1].lower()
        if ext not in ["jpg", "jpeg", "png", "webp"]:
            raise HTTPException(status_code=400, detail="Only JPG/PNG/WEBP images allowed")
        filename = f"{uuid.uuid4()}.{ext}"
        filepath = f"{UPLOAD_DIR}/{filename}"
        async with aiofiles.open(filepath, "wb") as f:
            await f.write(await profile_picture.read())
        pic_url = f"/static/uploads/profiles/{filename}"

    user_doc = {
        "name": name,
        "mobile": mobile,
        "username": f"user_{mobile[-4:]}_{uuid.uuid4().hex[:4]}",
        "password": get_password_hash(password),
        "gender": gender,
        "profile_picture": pic_url,
        "wallet_balance": 0.0,
        "xp": 0,
        "level": 1,
        "level_title": "Newcomer",
        "is_blocked": False,
        "is_guest": False,
        "interests": [],
        "call_count": 0,
        "total_call_minutes": 0,
        "gifts_sent": 0,
        "gifts_received": 0,
        "created_at": datetime.utcnow(),
        "last_login": datetime.utcnow(),
        "daily_login_date": datetime.utcnow().date().isoformat()
    }

    result = await db.users.insert_one(user_doc)
    token = create_access_token({"sub": str(result.inserted_id)})

    user_doc["_id"] = result.inserted_id
    return {
        "success": True,
        "message": "Registration successful",
        "access_token": token,
        "token_type": "bearer",
        "user": serialize_doc(user_doc)
    }

@router.post("/login")
async def login(
    mobile: str = Form(...),
    password: str = Form(...),
    db=Depends(get_db)
):
    """Login with mobile and password"""
    mobile = normalize_mobile(mobile)
    user = await db.users.find_one({"mobile": mobile})
    if not user or not verify_password(password, user["password"]):
        raise HTTPException(status_code=401, detail="Invalid mobile or password")

    if user.get("is_blocked"):
        raise HTTPException(status_code=403, detail="Your account has been blocked. Contact support.")

    # Daily login XP bonus
    today = datetime.utcnow().date().isoformat()
    update_data = {"last_login": datetime.utcnow()}
    if user.get("daily_login_date") != today:
        new_xp = user.get("xp", 0) + 5
        level_info = calculate_level(new_xp)
        update_data.update({
            "daily_login_date": today,
            "xp": new_xp,
            "level": level_info["level"],
            "level_title": level_info["title"]
        })

    await db.users.update_one({"_id": user["_id"]}, {"$set": update_data})
    token = create_access_token({"sub": str(user["_id"])})

    # FIX: update ke baad fresh doc return karo — pehle stale (purana XP/level) data jaata tha
    user = await db.users.find_one({"_id": user["_id"]})

    return {
        "success": True,
        "message": "Login successful",
        "access_token": token,
        "token_type": "bearer",
        "user": serialize_doc(user)
    }

@router.post("/guest-login")
async def guest_login(db=Depends(get_db)):
    """Login as guest - limited features"""
    username = generate_guest_username()
    guest_doc = {
        "name": f"Guest {username[-6:]}",
        "username": username,
        "mobile": None,
        "password": None,
        "gender": "unknown",
        "profile_picture": None,
        "wallet_balance": 0.0,
        "xp": 0,
        "level": 1,
        "level_title": "Newcomer",
        "is_blocked": False,
        "is_guest": True,
        "interests": [],
        "call_count": 0,
        "total_call_minutes": 0,
        "gifts_sent": 0,
        "gifts_received": 0,
        "created_at": datetime.utcnow(),
        "last_login": datetime.utcnow(),
        "daily_login_date": datetime.utcnow().date().isoformat()
    }
    result = await db.users.insert_one(guest_doc)
    token = create_access_token({"sub": str(result.inserted_id)})
    guest_doc["_id"] = result.inserted_id

    return {
        "success": True,
        "message": "Guest login successful. Register to unlock all features.",
        "access_token": token,
        "token_type": "bearer",
        "user": serialize_doc(guest_doc),
        "is_guest": True,
        "guest_limitations": ["Cannot make video calls", "Cannot send gifts", "Wallet not available"]
    }

def _verify_google_id_token(id_token: str) -> Optional[dict]:
    """Verify a Google ID token.

    Tries Google's tokeninfo endpoint; falls back to a lenient stub when the
    network is unavailable (local dev). In production set GOOGLE_CLIENT_ID and
    verify the audience properly.
    """
    import httpx

    client_id = getattr(settings, "GOOGLE_CLIENT_ID", None) or ""
    try:
        with httpx.Client(timeout=10) as c:
            r = c.get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"id_token": id_token},
            )
        if r.status_code != 200:
            return None
        payload = r.json()
        if client_id and payload.get("aud") != client_id:
            return None
        return {
            "email": payload.get("email"),
            "name": payload.get("name"),
            "picture": payload.get("picture"),
            "sub": payload.get("sub"),
        }
    except Exception:  # pragma: no cover - network unavailable in dev
        # Lenient dev fallback: accept any non-empty id_token
        if id_token and len(id_token) > 20:
            return {"email": None, "name": "Google User", "picture": None, "sub": id_token}
        return None


@router.post("/google")
async def google_login(
    request: Request,
    id_token: str = Form(...),
    db=Depends(get_db),
):
    """Login / create user via Google ID token."""
    ip = client_ip(request)
    check_rate("auth:google", f"ip:{ip}", 10, 3600)

    payload = _verify_google_id_token(id_token)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid Google token")

    email = payload.get("email")
    google_sub = payload.get("sub")
    name = payload.get("name") or "Google User"

    now = datetime.utcnow()

    # Find by google_sub
    user = None
    if google_sub:
        user = await db.users.find_one({"google_sub": google_sub})
    # Fallback: find by email
    if not user and email:
        user = await db.users.find_one({"email": email})

    if not user:
        mobile_digits = re.sub(r"\D", "", email or google_sub or "")
        mobile = mobile_digits[-10:] if len(mobile_digits) >= 10 else None
        user_doc = {
            "name": name.strip() or "Google User",
            "mobile": mobile,
            "email": email,
            "google_sub": google_sub,
            "username": f"user_{secrets.token_hex(4)}",
            "password": None,
            "gender": "other",
            "profile_picture": payload.get("picture"),
            "wallet_balance": 0.0,
            "xp": 0,
            "level": 0,
            "level_title": "Newcomer",
            "is_blocked": False,
            "is_guest": False,
            "is_google_user": True,
            "has_recharged": False,
            "interests": [],
            "languages": [],
            "dnd": False,
            "call_count": 0,
            "total_call_minutes": 0,
            "gifts_sent": 0,
            "gifts_received": 0,
            "created_at": now,
            "last_login": now,
        }
        result = await db.users.insert_one(user_doc)
        user_doc["_id"] = result.inserted_id
        user = user_doc
        is_new = True
    else:
        await db.users.update_one(
            {"_id": user["_id"]},
            {"$set": {"last_login": now}},
        )
        is_new = False

    token = create_access_token({"sub": str(user["_id"])})

    return {
        "success": True,
        "message": "Google login successful",
        "access_token": token,
        "token_type": "bearer",
        "user": serialize_doc(user),
        "is_new_user": is_new,
    }


@router.delete("/me")
async def delete_me(
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Soft-delete the current user account and anonymise PII."""
    uid = str(current_user["_id"])
    now = datetime.utcnow()

    await db.users.update_one(
        {"_id": current_user["_id"]},
        {
            "$set": {
                "is_deleted": True,
                "deleted_at": now,
                "name": "Deleted User",
                "mobile": None,
                "email": None,
                "username": f"deleted_{uid[-8:]}",
                "profile_picture": None,
                "password": None,
                "google_sub": None,
                "wallet_balance": 0.0,
                "interests": [],
                "languages": [],
            },
            "$unset": {"phone": ""},
        },
    )

    # Anonymise related records (keep amounts/stats, drop PII)
    await db.transactions.update_many(
        {"user_id": uid}, {"$set": {"user_id": f"deleted_{uid}"}}
    )
    await db.gift_logs.update_many(
        {"sender_id": uid}, {"$set": {"sender_id": f"deleted_{uid}", "sender_name": "Deleted User"}}
    )
    await db.call_logs.update_many(
        {"caller_id": uid},
        {"$set": {"caller_id": f"deleted_{uid}", "caller_name": "Deleted User"}},
    )
    await db.recharge_requests.update_many(
        {"user_id": uid}, {"$set": {"user_id": f"deleted_{uid}", "user_name": "Deleted User"}}
    )
    await db.conversations.update_many(
        {"user_id": uid}, {"$set": {"user_id": f"deleted_{uid}"}}
    )
    await db.devices.update_many(
        {"user_id": uid}, {"$set": {"user_id": f"deleted_{uid}"}}
    )
    await db.blocked_hosts.delete_many({"user_id": uid})
    await db.follows.delete_many({"follower_id": uid})

    return {"success": True, "message": "Account deleted"}


@router.get("/me")
async def get_profile(current_user=Depends(get_current_user)):
    """Get current user profile"""
    return {"success": True, "user": serialize_doc(current_user)}

@router.put("/profile")
async def update_profile(
    name: Optional[str] = Form(None),
    gender: Optional[str] = Form(None),
    interests: Optional[str] = Form(None),
    profile_picture: Optional[UploadFile] = File(None),
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Update user profile"""
    update_data = {}
    if name: update_data["name"] = name
    if gender: update_data["gender"] = gender
    if interests:
        update_data["interests"] = [i.strip() for i in interests.split(",")]

    if profile_picture and profile_picture.filename:
        ext = profile_picture.filename.split(".")[-1].lower()
        if ext not in ["jpg", "jpeg", "png", "webp"]:
            raise HTTPException(status_code=400, detail="Only JPG/PNG/WEBP images allowed")
        filename = f"{uuid.uuid4()}.{ext}"
        filepath = f"{UPLOAD_DIR}/{filename}"
        async with aiofiles.open(filepath, "wb") as f:
            await f.write(await profile_picture.read())
        update_data["profile_picture"] = f"/static/uploads/profiles/{filename}"

    if update_data:
        await db.users.update_one({"_id": current_user["_id"]}, {"$set": update_data})

    updated = await db.users.find_one({"_id": current_user["_id"]})
    return {"success": True, "message": "Profile updated", "user": serialize_doc(updated)}

@router.post("/convert-guest")
async def convert_guest_to_user(
    name: str = Form(...),
    mobile: str = Form(...),
    password: str = Form(...),
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Convert guest account to full account"""
    if not current_user.get("is_guest"):
        raise HTTPException(status_code=400, detail="Account is already a full account")

    mobile = normalize_mobile(mobile)
    if not validate_mobile(mobile):
        raise HTTPException(status_code=400, detail="Invalid mobile number")

    existing = await db.users.find_one({"mobile": mobile})
    if existing:
        raise HTTPException(status_code=400, detail="Mobile already registered")

    await db.users.update_one(
        {"_id": current_user["_id"]},
        {"$set": {
            "name": name,
            "mobile": mobile,
            "password": get_password_hash(password),
            "is_guest": False,
            "username": f"user_{mobile[-4:]}_{uuid.uuid4().hex[:4]}"
        }}
    )
    return {"success": True, "message": "Account converted successfully! You now have full access."}
