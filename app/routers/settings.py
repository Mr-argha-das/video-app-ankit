from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.core.app_settings import get_app_settings, update_app_settings, PUBLIC_KEYS
from app.core.config import settings as env_settings
from app.core.database import get_db
from app.core.security import get_current_admin
from app.services.ai_bot import ai_configured

router = APIRouter(prefix="/settings", tags=["App Settings"])


class PriyaBotSettings(BaseModel):
    name: Optional[str] = None
    greeting: Optional[str] = None
    personality: Optional[str] = None
    instructions: Optional[str] = None


class AppSettingsUpdate(BaseModel):
    connecting_seconds: Optional[int] = None
    billing_tick_seconds: Optional[int] = None
    heartbeat_grace_seconds: Optional[int] = None
    incoming_call_enabled: Optional[bool] = None
    incoming_call_interval_seconds: Optional[int] = None
    incoming_ring_timeout_seconds: Optional[int] = None
    priya_host_id: Optional[str] = None
    call_message_enabled: Optional[bool] = None
    call_message: Optional[str] = None
    call_message_low_balance: Optional[str] = None
    priya_bot: Optional[PriyaBotSettings] = None


@router.get("/app")
async def public_app_settings(db=Depends(get_db)):
    """Call/incoming-call timings used by the mobile app."""
    cfg = await get_app_settings(db)
    data = {k: cfg.get(k) for k in PUBLIC_KEYS}
    data["priya_name"] = cfg["priya_bot"]["name"]
    return {"success": True, "settings": data}


@router.get("/admin")
async def admin_get_settings(db=Depends(get_db), admin=Depends(get_current_admin)):
    cfg = await get_app_settings(db)
    return {
        "success": True,
        "settings": cfg,
        "ai": {
            "configured": ai_configured(),
            "model": env_settings.AI_MODEL if ai_configured() else None,
            "base_url": env_settings.AI_BASE_URL if ai_configured() else None,
        },
    }


@router.put("/admin")
async def admin_update_settings(body: AppSettingsUpdate, db=Depends(get_db), admin=Depends(get_current_admin)):
    patch = body.model_dump(exclude_unset=True)
    if "priya_bot" in patch and patch["priya_bot"] is not None:
        patch["priya_bot"] = {k: v for k, v in patch["priya_bot"].items() if v is not None}
    cfg = await update_app_settings(db, patch)
    return {"success": True, "message": "Settings saved", "settings": cfg}
