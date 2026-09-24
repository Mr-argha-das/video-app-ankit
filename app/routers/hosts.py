from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form, Query
from datetime import datetime
from bson import ObjectId
from typing import Optional, List

from app.core.database import get_db
from app.core.security import get_current_admin, get_optional_user
from app.utils.helpers import serialize_doc
from app.utils.media import save_upload, save_many, delete_media_file, _has_file

router = APIRouter(prefix="/hosts", tags=["Host Users - Discover"])

LEVELS_MAP = {1: "Newcomer", 2: "Explorer", 3: "Regular", 4: "Active", 5: "Popular",
              6: "Star", 7: "Super Star", 8: "Legend", 9: "Elite", 10: "Champion"}

# Admin-only fields — bot prompt/context kabhi public API me nahi jaana chahiye.
PRIVATE_FIELDS = ("bot_personality", "bot_instructions")
CLEARABLE_FIELDS = {"bio", "description", "city", "language", "interests",
                    "bot_greeting", "bot_personality", "bot_instructions"}


def effective_call_video(host: dict) -> Optional[str]:
    """Video played during a call: dedicated call video → preview video → first gallery video."""
    return host.get("call_video") or host.get("preview_video") or next(iter(host.get("videos") or []), None)


def public_host(host: dict) -> dict:
    """Serialize a host for the user app (strips admin-only bot context)."""
    data = serialize_doc(host)
    for f in PRIVATE_FIELDS:
        data.pop(f, None)
    data.setdefault("images", [])
    data.setdefault("videos", [])
    data.setdefault("description", "")
    data["call_video"] = effective_call_video(host)
    data["has_call_video"] = bool(data["call_video"])
    data["has_bot"] = bool(host.get("bot_enabled", True))
    return data


def admin_host(host: dict) -> dict:
    data = serialize_doc(host)
    data.setdefault("images", [])
    data.setdefault("videos", [])
    data["effective_call_video"] = effective_call_video(host)
    return data


def _csv(v: Optional[str]) -> List[str]:
    return [i.strip() for i in (v or "").split(",") if i.strip()]


def _oid(host_id: str) -> ObjectId:
    try:
        return ObjectId(host_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid host ID")


# ========== PUBLIC / USER ENDPOINTS ==========

@router.get("/discover")
async def discover_hosts(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=50),
    interest: Optional[str] = None,
    gender: Optional[str] = None,
    level: Optional[int] = None,
    sort_by: str = Query("created_at", enum=["created_at", "price_per_minute", "level", "name"]),
    db=Depends(get_db),
    current_user=Depends(get_optional_user)
):
    """Home screen - Discover hosts (admin-added users)"""
    query = {"is_active": True}
    if interest:
        query["interests"] = {"$in": [interest]}
    if gender:
        query["gender"] = gender
    if level:
        query["level"] = level

    skip = (page - 1) * limit
    sort_dir = -1 if sort_by == "created_at" else 1

    hosts = await db.host_users.find(query).sort(sort_by, sort_dir).skip(skip).limit(limit).to_list(limit)
    total = await db.host_users.count_documents(query)

    return {
        "success": True,
        "hosts": [public_host(h) for h in hosts],
        "total": total,
        "page": page,
        "total_pages": (total + limit - 1) // limit,
        "has_next": (page * limit) < total
    }

@router.get("/featured")
async def get_featured_hosts(db=Depends(get_db)):
    """Get featured/top hosts for banner"""
    hosts = await db.host_users.find({"is_active": True, "is_featured": True}).limit(10).to_list(10)
    return {"success": True, "hosts": [public_host(h) for h in hosts]}

@router.get("/online")
async def get_online_hosts(db=Depends(get_db)):
    """Get currently online/available hosts"""
    hosts = await db.host_users.find({"is_active": True, "is_online": True}).to_list(50)
    return {"success": True, "hosts": [public_host(h) for h in hosts], "count": len(hosts)}

@router.get("/{host_id}")
async def get_host_detail(host_id: str, db=Depends(get_db)):
    """Host profile page — info, images, videos, call price"""
    host = await db.host_users.find_one({"_id": _oid(host_id), "is_active": True})
    if not host:
        raise HTTPException(status_code=404, detail="Host not found")
    return {"success": True, "host": public_host(host)}

# ========== ADMIN ENDPOINTS ==========

@router.post("/admin/add")
async def admin_add_host(
    name: str = Form(...),
    age: int = Form(...),
    gender: str = Form("female"),
    level: int = Form(1),
    price_per_minute: float = Form(10.0),
    bio: Optional[str] = Form(None),
    description: Optional[str] = Form(None),
    city: Optional[str] = Form(None),
    interests: Optional[str] = Form(None),
    language: Optional[str] = Form("Hindi, English"),
    is_online: bool = Form(True),
    is_featured: bool = Form(False),
    # Bot / chat context
    bot_enabled: bool = Form(True),
    bot_greeting: Optional[str] = Form(None),
    bot_personality: Optional[str] = Form(None),
    bot_instructions: Optional[str] = Form(None),
    # Media
    profile_picture: Optional[UploadFile] = File(None),
    preview_video: Optional[UploadFile] = File(None),
    call_video: Optional[UploadFile] = File(None),
    images: List[UploadFile] = File(default=[]),
    videos: List[UploadFile] = File(default=[]),
    db=Depends(get_db),
    admin=Depends(get_current_admin)
):
    """Admin: Add new host (profile pic, gallery images, videos, call video, price, bot context)"""
    if price_per_minute <= 0:
        raise HTTPException(status_code=400, detail="Price per minute must be positive")

    pic_url = await save_upload(profile_picture, "image") if _has_file(profile_picture) else None
    preview_url = await save_upload(preview_video, "video") if _has_file(preview_video) else None
    call_url = await save_upload(call_video, "video") if _has_file(call_video) else None
    image_urls = await save_many(images, "image")
    video_urls = await save_many(videos, "video")

    # Profile pic nahi diya toh pehli gallery image use karo
    if not pic_url and image_urls:
        pic_url = image_urls[0]

    host_doc = {
        "name": name.strip(),
        "age": age,
        "gender": gender,
        "level": level,
        "level_title": LEVELS_MAP.get(level, "Newcomer"),
        "price_per_minute": price_per_minute,
        "bio": bio or f"Hi! I'm {name}. Let's have a great conversation!",
        "description": description or "",
        "city": city or "",
        "interests": _csv(interests),
        "language": language,
        "profile_picture": pic_url,
        "preview_video": preview_url,
        "call_video": call_url,
        "images": image_urls,
        "videos": video_urls,
        "bot_enabled": bot_enabled,
        "bot_greeting": (bot_greeting or "").strip(),
        "bot_personality": (bot_personality or "").strip(),
        "bot_instructions": (bot_instructions or "").strip(),
        "is_active": True,
        "is_online": is_online,
        "is_featured": is_featured,
        "total_calls": 0,
        "total_minutes": 0,
        "total_earnings": 0.0,
        "rating": 4.5,
        "review_count": 0,
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow()
    }

    result = await db.host_users.insert_one(host_doc)
    host_doc["_id"] = result.inserted_id

    return {"success": True, "message": "Host added successfully", "host": admin_host(host_doc)}

@router.put("/admin/{host_id}")
async def admin_update_host(
    host_id: str,
    name: Optional[str] = Form(None),
    age: Optional[int] = Form(None),
    gender: Optional[str] = Form(None),
    level: Optional[int] = Form(None),
    price_per_minute: Optional[float] = Form(None),
    bio: Optional[str] = Form(None),
    description: Optional[str] = Form(None),
    city: Optional[str] = Form(None),
    interests: Optional[str] = Form(None),
    language: Optional[str] = Form(None),
    is_active: Optional[bool] = Form(None),
    is_featured: Optional[bool] = Form(None),
    is_online: Optional[bool] = Form(None),
    bot_enabled: Optional[bool] = Form(None),
    bot_greeting: Optional[str] = Form(None),
    bot_personality: Optional[str] = Form(None),
    bot_instructions: Optional[str] = Form(None),
    # Existing gallery video ko call video banana ho toh uska URL bhejo
    call_video_url: Optional[str] = Form(None),
    # FastAPI khali form strings ko "not sent" maanta hai — text field clear
    # karne ke liye uska naam yahan bhejo (comma separated), e.g. "description,city"
    clear_fields: Optional[str] = Form(None),
    profile_picture: Optional[UploadFile] = File(None),
    preview_video: Optional[UploadFile] = File(None),
    call_video: Optional[UploadFile] = File(None),
    images: List[UploadFile] = File(default=[]),   # appended to gallery
    videos: List[UploadFile] = File(default=[]),   # appended to gallery
    db=Depends(get_db),
    admin=Depends(get_current_admin)
):
    """Admin: Update host details. New images/videos are appended to the gallery."""
    oid = _oid(host_id)
    existing = await db.host_users.find_one({"_id": oid})
    if not existing:
        raise HTTPException(status_code=404, detail="Host not found")

    update_data = {"updated_at": datetime.utcnow()}
    push = {}

    if name: update_data["name"] = name.strip()
    if age: update_data["age"] = age
    if gender: update_data["gender"] = gender
    if level:
        update_data["level"] = level
        update_data["level_title"] = LEVELS_MAP.get(level, "Newcomer")
    if price_per_minute is not None:
        if price_per_minute <= 0:
            raise HTTPException(status_code=400, detail="Price per minute must be positive")
        update_data["price_per_minute"] = price_per_minute
    # Text fields: empty string allowed (admin clearing a field)
    if bio is not None: update_data["bio"] = bio
    if description is not None: update_data["description"] = description
    if city is not None: update_data["city"] = city
    if language is not None: update_data["language"] = language
    if interests is not None: update_data["interests"] = _csv(interests)
    if is_active is not None: update_data["is_active"] = is_active
    if is_featured is not None: update_data["is_featured"] = is_featured
    if is_online is not None: update_data["is_online"] = is_online
    if bot_enabled is not None: update_data["bot_enabled"] = bot_enabled
    if bot_greeting is not None: update_data["bot_greeting"] = bot_greeting.strip()
    if bot_personality is not None: update_data["bot_personality"] = bot_personality.strip()
    if bot_instructions is not None: update_data["bot_instructions"] = bot_instructions.strip()

    for f in _csv(clear_fields):
        if f in CLEARABLE_FIELDS:
            update_data[f] = [] if f == "interests" else ""

    if _has_file(profile_picture):
        update_data["profile_picture"] = await save_upload(profile_picture, "image")
    if _has_file(preview_video):
        update_data["preview_video"] = await save_upload(preview_video, "video")
    if _has_file(call_video):
        update_data["call_video"] = await save_upload(call_video, "video")
    elif call_video_url is not None:
        allowed = set(existing.get("videos") or []) | {existing.get("preview_video"), existing.get("call_video")}
        if call_video_url and call_video_url not in allowed:
            raise HTTPException(status_code=400, detail="call_video_url must be one of this host's videos")
        update_data["call_video"] = call_video_url or None

    new_images = await save_many(images, "image")
    new_videos = await save_many(videos, "video")
    if new_images:
        push["images"] = {"$each": new_images}
        if not existing.get("profile_picture") and "profile_picture" not in update_data:
            update_data["profile_picture"] = new_images[0]
    if new_videos:
        push["videos"] = {"$each": new_videos}

    ops = {"$set": update_data}
    if push:
        ops["$push"] = push
    await db.host_users.update_one({"_id": oid}, ops)

    updated = await db.host_users.find_one({"_id": oid})
    return {"success": True, "message": "Host updated", "host": admin_host(updated)}

@router.delete("/admin/{host_id}/media")
async def admin_delete_host_media(
    host_id: str,
    url: str = Query(..., description="Media URL to remove"),
    kind: str = Query(..., enum=["image", "video", "call_video", "preview_video", "profile_picture"]),
    db=Depends(get_db),
    admin=Depends(get_current_admin)
):
    """Admin: Remove a single image/video from a host"""
    oid = _oid(host_id)
    host = await db.host_users.find_one({"_id": oid})
    if not host:
        raise HTTPException(status_code=404, detail="Host not found")

    if kind == "image":
        if url not in (host.get("images") or []):
            raise HTTPException(status_code=404, detail="Image not found on host")
        ops = {"$pull": {"images": url}}
        if host.get("profile_picture") == url:
            ops["$set"] = {"profile_picture": None}
    elif kind == "video":
        if url not in (host.get("videos") or []):
            raise HTTPException(status_code=404, detail="Video not found on host")
        ops = {"$pull": {"videos": url}}
        if host.get("call_video") == url:
            ops["$set"] = {"call_video": None}
    else:
        if host.get(kind) != url:
            raise HTTPException(status_code=404, detail="Media not found on host")
        ops = {"$set": {kind: None}}

    await db.host_users.update_one({"_id": oid}, ops)
    updated = await db.host_users.find_one({"_id": oid})

    # File sirf tab delete karo jab host me kahin aur reference na ho
    still_used = url in (updated.get("images") or []) + (updated.get("videos") or []) or url in (
        updated.get("profile_picture"), updated.get("preview_video"), updated.get("call_video"))
    if not still_used:
        delete_media_file(url)

    return {"success": True, "message": "Media removed", "host": admin_host(updated)}

@router.delete("/admin/{host_id}")
async def admin_delete_host(host_id: str, db=Depends(get_db), admin=Depends(get_current_admin)):
    """Admin: Delete host"""
    result = await db.host_users.delete_one({"_id": _oid(host_id)})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Host not found")
    return {"success": True, "message": "Host deleted"}

@router.get("/admin/list/all")
async def admin_list_hosts(
    page: int = 1,
    limit: int = 20,
    db=Depends(get_db),
    admin=Depends(get_current_admin)
):
    """Admin: List all hosts"""
    skip = (page - 1) * limit
    hosts = await db.host_users.find().sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    total = await db.host_users.count_documents({})
    return {
        "success": True,
        "hosts": [admin_host(h) for h in hosts],
        "total": total
    }

@router.get("/admin/{host_id}")
async def admin_get_host(host_id: str, db=Depends(get_db), admin=Depends(get_current_admin)):
    """Admin: Full host detail incl. inactive hosts + bot context"""
    host = await db.host_users.find_one({"_id": _oid(host_id)})
    if not host:
        raise HTTPException(status_code=404, detail="Host not found")
    return {"success": True, "host": admin_host(host)}
