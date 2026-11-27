"""OTP-based login.

POST /api/v1/auth/otp/send   {mobile}      -> sends 4-digit OTP (dev: prints to log)
POST /api/v1/auth/otp/verify  {mobile, otp}-> verifies OTP, creates user if missing

Rate limits: per-mobile + per-IP on send; per-mobile on verify (max 3 attempts).
Dev mode: OTP is printed to server log instead of going through an SMS gateway.
Provider interface (MSG91 / Firebase) behind SMS_PROVIDER env var.
"""
import logging
import re
import secrets
from abc import ABC, abstractmethod
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, HTTPException, Depends, Request, status
from bson import ObjectId

from app.core.database import get_db
from app.core.security import create_access_token, settings
from app.core.ratelimit import check_rate, client_ip
from app.utils.helpers import normalize_mobile, validate_mobile, generate_guest_username

router = APIRouter(prefix="/auth/otp", tags=["Authentication - OTP"])

log = logging.getLogger("otp")

OTP_LEN = 4
OTP_EXPIRY_MINUTES = 5
OTP_MAX_ATTEMPTS = 3
OTP_RESEND_COOLDOWN_SECONDS = 60


# ---------------------------------------------------------------------------
# SMS provider interface
# ---------------------------------------------------------------------------
class SMSSender(ABC):
    @abstractmethod
    def send(self, mobile: str, otp: str) -> bool:
        ...


class DevSMSSender(SMSSender):
    """Prints OTP to the server log (no real SMS). Use for local dev."""

    def send(self, mobile: str, otp: str) -> bool:
        log.info("=" * 60)
        log.info(f"[DEV OTP] mobile={mobile} otp={otp} (expires {OTP_EXPIRY_MINUTES} min)")
        log.info("=" * 60)
        return True


class MSG91SMSSender(SMSSender):
    """MSG91 stub — real HTTP call goes here."""

    def __init__(self):
        self.auth_key = settings.MSG91_AUTH_KEY if hasattr(settings, "MSG91_AUTH_KEY") else ""
        self.template_id = settings.MSG91_TEMPLATE_ID if hasattr(settings, "MSG91_TEMPLATE_ID") else ""

    def send(self, mobile: str, otp: str) -> bool:
        # TODO: replace with real MSG91 API call
        log.info(f"[MSG91 stub] would send OTP {otp} to {mobile}")
        return True


class FirebaseSMSSender(SMSSender):
    """Firebase Auth phone-stub."""

    def send(self, mobile: str, otp: str) -> bool:
        # TODO: Firebase phone auth integration
        log.info(f"[Firebase stub] would send OTP {otp} to {mobile}")
        return True


def _get_sender() -> SMSSender:
    provider = getattr(settings, "SMS_PROVIDER", "dev") or "dev"
    if provider == "msg91":
        return MSG91SMSSender()
    if provider == "firebase":
        return FirebaseSMSSender()
    return DevSMSSender()


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.post("/send")
async def otp_send(
    request: Request,
    mobile: str,
    db=Depends(get_db),
):
    """Send a 4-digit OTP to the mobile number.

    Rate limits:
      - per-mobile: 5 sends / hour
      - per-IP: 10 sends / hour
    Enforces a 60s resend cooldown per mobile.
    """
    mobile = normalize_mobile(mobile)
    if not validate_mobile(mobile):
        raise HTTPException(status_code=400, detail="Invalid mobile number")

    ip = client_ip(request)

    # Rate limits
    check_rate("otp:send", f"mobile:{mobile}", 5, 3600)
    check_rate("otp:send", f"ip:{ip}", 10, 3600)

    now = datetime.utcnow()
    existing = await db.otps.find_one({"mobile": mobile})

    # Resend cooldown
    if existing and existing.get("resend_cooldown_until") and existing["resend_cooldown_until"] > now:
        remaining = int((existing["resend_cooldown_until"] - now).total_seconds()) + 1
        raise HTTPException(
            status_code=429,
            detail=f"Please wait {remaining}s before requesting a new OTP",
            headers={"Retry-After": str(remaining)},
        )

    otp = f"{secrets.randbelow(10 ** OTP_LEN):0{OTP_LEN}d}"
    expires_at = now + timedelta(minutes=OTP_EXPIRY_MINUTES)
    cooldown_until = now + timedelta(seconds=OTP_RESEND_COOLDOWN_SECONDS)

    await db.otps.update_one(
        {"mobile": mobile},
        {
            "$set": {
                "otp": otp,
                "expires_at": expires_at,
                "resend_cooldown_until": cooldown_until,
                "attempts": 0,
                "verified": False,
                "updated_at": now,
            },
            "$setOnInsert": {"created_at": now},
        },
        upsert=True,
    )

    try:
        _get_sender().send(mobile, otp)
    except Exception as e:  # pragma: no cover - provider failure shouldn't break send
        log.warning(f"SMS provider failed for {mobile}: {e}")

    return {
        "success": True,
        "message": "OTP sent",
        "mobile": mobile,
        "expires_in_seconds": OTP_EXPIRY_MINUTES * 60,
    }


@router.post("/verify")
async def otp_verify(
    request: Request,
    mobile: str,
    otp: str,
    db=Depends(get_db),
):
    """Verify OTP. Logs the user in; creates a new user if none exists."""
    mobile = normalize_mobile(mobile)
    if not validate_mobile(mobile):
        raise HTTPException(status_code=400, detail="Invalid mobile number")

    ip = client_ip(request)
    check_rate("otp:verify", f"mobile:{mobile}", OTP_MAX_ATTEMPTS, 3600)

    now = datetime.utcnow()
    record = await db.otps.find_one({"mobile": mobile})
    if not record:
        raise HTTPException(status_code=400, detail="No OTP sent for this number")

    if record.get("verified"):
        raise HTTPException(status_code=400, detail="OTP already used")

    if record.get("expires_at") and record["expires_at"] <= now:
        raise HTTPException(status_code=400, detail="OTP expired — request a new one")

    attempts = int(record.get("attempts", 0))
    if attempts >= OTP_MAX_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many failed attempts — request a new OTP")

    if str(record.get("otp")) != str(otp):
        await db.otps.update_one(
            {"mobile": mobile},
            {"$inc": {"attempts": 1}},
        )
        remaining = OTP_MAX_ATTEMPTS - (attempts + 1)
        raise HTTPException(
            status_code=400,
            detail=f"Invalid OTP. {remaining} attempt(s) left.",
        )

    # Mark verified
    await db.otps.update_one(
        {"mobile": mobile},
        {"$set": {"verified": True, "updated_at": now}},
    )

    # Find or create user
    user = await db.users.find_one({"mobile": mobile})
    if not user:
        user_doc = {
            "name": f"User{secrets.randbelow(900000) + 100000}",
            "mobile": mobile,
            "username": f"user_{mobile[-4:]}_{generate_guest_username().split('_')[-1]}",
            "password": None,
            "gender": "other",
            "profile_picture": None,
            "wallet_balance": 0.0,
            "xp": 0,
            "level": 0,
            "level_title": "Newcomer",
            "is_blocked": False,
            "is_guest": False,
            "is_otp_user": True,
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
    else:
        await db.users.update_one(
            {"_id": user["_id"]},
            {"$set": {"last_login": now}},
        )

    token = create_access_token({"sub": str(user["_id"])})

    from app.utils.helpers import serialize_doc

    return {
        "success": True,
        "message": "Login successful",
        "access_token": token,
        "token_type": "bearer",
        "user": serialize_doc(user),
        "is_new_user": user.get("password") is None,
    }
