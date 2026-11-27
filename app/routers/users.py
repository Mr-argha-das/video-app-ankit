"""User account settings, blocked/hidden hosts and reports.

Prefix: /api/v1/users  (all user-authenticated except admin report list)
"""
from datetime import datetime
from typing import Optional, List
from bson import ObjectId

from fastapi import APIRouter, HTTPException, Depends, Query, status
from pydantic import BaseModel

from app.core.database import get_db
from app.core.security import get_current_user, get_current_admin
from app.utils.helpers import serialize_doc
from app.core.ratelimit import check_rate, client_ip

router = APIRouter(prefix="/users", tags=["User Account"])


class SettingsUpdate(BaseModel):
    dnd: Optional[bool] = None
    languages: Optional[List[str]] = None


class BlockHostRequest(BaseModel):
    host_id: str


class ReportRequest(BaseModel):
    host_id: str
    reason: str
    details: Optional[str] = None


class DeviceRegister(BaseModel):
    fcm_token: str


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

@router.get("/me/settings")
async def get_settings(
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Get current user's settings (dnd, languages)."""
    user = await db.users.find_one({"_id": current_user["_id"]}, {"dnd": 1, "languages": 1})
    return {
        "success": True,
        "settings": {
            "dnd": bool((user or {}).get("dnd", False)),
            "languages": (user or {}).get("languages", []),
        },
    }


@router.put("/me/settings")
async def update_settings(
    body: SettingsUpdate,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Update current user's settings."""
    update = {}
    if body.dnd is not None:
        update["dnd"] = bool(body.dnd)
    if body.languages is not None:
        update["languages"] = [l for l in body.languages if l][:20]

    if update:
        await db.users.update_one({"_id": current_user["_id"]}, {"$set": update})

    return await get_settings(current_user, db)


# ---------------------------------------------------------------------------
# Blocked / hidden hosts
# ---------------------------------------------------------------------------

@router.get("/me/blocked-hosts")
async def list_blocked_hosts(
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """List hosts the user has blocked or hidden."""
    uid = str(current_user["_id"])
    rows = await db.blocked_hosts.find({"user_id": uid}).sort("created_at", -1).to_list(500)
    return {
        "success": True,
        "blocked": [
            {"host_id": r["host_id"], "type": r.get("type", "block"), "created_at": r["created_at"]}
            for r in rows
        ],
    }


@router.post("/me/device")
async def register_device(
    body: DeviceRegister,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Register FCM push token for the current user."""
    await db.devices.update_one(
        {"user_id": str(current_user["_id"])},
        {"$set": {"fcm_token": body.fcm_token, "updated_at": datetime.utcnow()}},
        upsert=True,
    )
    return {"success": True, "message": "Device registered"}


@router.post("/me/blocked-hosts")
async def block_host(
    body: BlockHostRequest,
    request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Block or hide a host (rate limited per user)."""
    check_rate("users:block", str(current_user["_id"]), 30, 3600)
    uid = str(current_user["_id"])
    oid = ObjectId(body.host_id)
    host = await db.host_users.find_one({"_id": oid})
    if not host:
        raise HTTPException(status_code=404, detail="Host not found")

    await db.blocked_hosts.update_one(
        {"user_id": uid, "host_id": body.host_id},
        {"$setOnInsert": {"type": "block", "created_at": datetime.utcnow()}},
        upsert=True,
    )
    return {"success": True, "message": "Host blocked", "host_id": body.host_id}


@router.delete("/me/blocked-hosts/{host_id}")
async def unblock_host(
    host_id: str,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Remove a host from the blocked/hidden list."""
    uid = str(current_user["_id"])
    await db.blocked_hosts.delete_one({"user_id": uid, "host_id": host_id})
    return {"success": True, "message": "Removed from blocked list"}


# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------

@router.post("/reports")
async def create_report(
    body: ReportRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Report a host (rate limited)."""
    check_rate("users:report", str(current_user["_id"]), 10, 3600)
    oid = ObjectId(body.host_id)
    host = await db.host_users.find_one({"_id": oid})
    if not host:
        raise HTTPException(status_code=404, detail="Host not found")

    doc = {
        "host_id": body.host_id,
        "host_name": host.get("name"),
        "reporter_id": str(current_user["_id"]),
        "reporter_name": current_user.get("name"),
        "reason": body.reason,
        "details": body.details,
        "status": "open",
        "created_at": datetime.utcnow(),
    }
    await db.reports.insert_one(doc)
    return {"success": True, "message": "Report submitted"}


# ---------------------------------------------------------------------------
# Admin: reports list
# ---------------------------------------------------------------------------

@router.get("/admin/reports")
async def admin_list_reports(
    status_filter: Optional[str] = Query(None, alias="status", enum=["open", "resolved", "dismissed"]),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db=Depends(get_db),
    admin=Depends(get_current_admin),
):
    """Admin: list all reports."""
    query = {}
    if status_filter:
        query["status"] = status_filter
    skip = (page - 1) * limit
    rows = await db.reports.find(query).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    total = await db.reports.count_documents(query)
    return {
        "success": True,
        "reports": [serialize_doc(r) for r in rows],
        "total": total,
        "page": page,
    }
