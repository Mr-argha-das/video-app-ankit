"""Video calls — outgoing + incoming, with continuous wallet billing.

Flow (both outgoing and accepted incoming calls):

    POST /calls/initiate            → call created (status=initiated), balance checked.
                                      App shows "Calling… / Connecting…" for
                                      `connecting_seconds` (default 10s). NOT billed.
    POST /calls/answer/{call_id}    → host "picks up": status=active, billing clock starts,
                                      app starts playing the host's admin-uploaded video.
    POST /calls/billing-check       → every `billing_tick_seconds` (default 5s).
                                      Server charges pro-rata per second
                                      (rate/60 per second) for elapsed time and returns
                                      `continue` or `end_call` (balance exhausted).
    POST /calls/end                 → user hangs up; final settlement + rating.

Billing is fully server-side & time based: spamming billing-check can't double
charge, skipping it can't give free time (settled on next check / end), and if
the app vanishes without heartbeats the call is closed after
`heartbeat_grace_seconds` and billed only up to that point.
"""
from fastapi import APIRouter, HTTPException, Depends
from datetime import datetime, timedelta
from bson import ObjectId
from typing import Optional, Literal
from pydantic import BaseModel
from pymongo import ReturnDocument
import random, uuid

from app.core.database import get_db
from app.core.security import get_current_user, get_current_admin
from app.core.app_settings import get_app_settings
from app.utils.helpers import serialize_doc, calculate_level, add_xp_for_action
from app.routers.hosts import public_host, effective_call_video

router = APIRouter(prefix="/calls", tags=["Video Calls"])

IN_PROGRESS = ["initiated", "ringing", "active"]
ENDED_STATUSES = ["completed", "ended_insufficient_balance", "timed_out", "cancelled", "rejected", "missed"]


class StartCallRequest(BaseModel):
    host_id: str
    call_type: Literal["outgoing", "incoming"] = "outgoing"

class EndCallRequest(BaseModel):
    call_id: str
    rating: Optional[int] = None
    review: Optional[str] = None

class BalanceCheckRequest(BaseModel):
    call_id: str

class IncomingResponseRequest(BaseModel):
    host_id: str
    action: Literal["rejected", "missed"]


# ======================= BILLING HELPERS =======================

def _r2(x: float) -> float:
    return round(float(x) + 1e-9, 2)


async def _debit(user_id: ObjectId, amount: float, db) -> Optional[dict]:
    """Atomic conditional debit. Returns updated user or None if insufficient."""
    return await db.users.find_one_and_update(
        {"_id": user_id, "wallet_balance": {"$gte": amount}},
        {"$inc": {"wallet_balance": -amount}},
        return_document=ReturnDocument.AFTER,
    )


async def _drain(user_id: ObjectId, db) -> float:
    """Take whatever small balance is left (less than what's due). Race-safe CAS."""
    for _ in range(5):
        user = await db.users.find_one({"_id": user_id}, {"wallet_balance": 1})
        bal = (user or {}).get("wallet_balance", 0) or 0
        if bal <= 0:
            return 0.0
        done = await db.users.find_one_and_update(
            {"_id": user_id, "wallet_balance": bal}, {"$set": {"wallet_balance": 0}}
        )
        if done:
            return float(bal)
    return 0.0


async def _record_call_txn(call: dict, amount: float, balance_after: float, db):
    """One wallet transaction per call (amount accumulates) — not one per tick."""
    if amount <= 0:
        return
    now = datetime.utcnow()
    label = "Incoming" if call.get("call_type") == "incoming" else "Video"
    await db.transactions.update_one(
        {"call_id": call["call_id"], "type": "debit"},
        {
            "$inc": {"amount": amount},
            "$set": {
                "balance_after": balance_after,
                "description": f"{label} Call - {call['host_name']} (🪙{call['price_per_minute']}/min)",
                "updated_at": now,
            },
            "$setOnInsert": {
                "user_id": call["caller_id"],
                "status": "success",
                "balance_before": _r2(balance_after + amount),
                "created_at": now,
            },
        },
        upsert=True,
    )


async def _bill_until(call: dict, until: datetime, db) -> dict:
    """Charge everything due between call start and `until`.

    Returns {charged, balance, exhausted, billed_seconds}.
    """
    user_id = ObjectId(call["caller_id"])
    ppm = float(call["price_per_minute"])
    rate = ppm / 60.0
    start = call["start_time"]
    elapsed = max(0.0, (until - start).total_seconds())
    already = float(call.get("total_cost", 0) or 0)
    due = _r2(elapsed * rate - already)

    charged = 0.0
    exhausted = False
    balance = None
    billed_seconds = float(call.get("billed_seconds", 0) or 0)

    if due >= 0.01:
        user = await _debit(user_id, due, db)
        if user:
            charged = due
            balance = float(user.get("wallet_balance", 0))
            billed_seconds = elapsed
        else:
            # Pura due afford nahi hai → jo bacha hai wo lo, call khatam
            charged = _r2(await _drain(user_id, db))
            balance = 0.0
            billed_seconds = billed_seconds + (charged / rate if rate else 0)
            exhausted = True

    if balance is None:
        user = await db.users.find_one({"_id": user_id}, {"wallet_balance": 1})
        balance = float((user or {}).get("wallet_balance", 0) or 0)

    # Agle 1 second ka paisa bhi nahi bacha → balance exhausted
    if balance < max(0.01, rate):
        exhausted = True

    if charged > 0:
        await db.call_logs.update_one(
            {"call_id": call["call_id"]},
            {"$inc": {"total_cost": charged}, "$set": {"billed_seconds": billed_seconds}},
        )
        call["total_cost"] = _r2(already + charged)
        call["billed_seconds"] = billed_seconds
        await _record_call_txn(call, charged, balance, db)

    return {"charged": charged, "balance": _r2(balance), "exhausted": exhausted, "billed_seconds": billed_seconds}


async def _finalize(call: dict, status: str, end_time: datetime, db,
                    rating: Optional[int] = None, review: Optional[str] = None) -> dict:
    """Mark call ended (idempotent via status guard) + update user/host stats."""
    answered = bool(call.get("start_time"))
    if answered:
        talk_secs = int(max(0, (end_time - call["start_time"]).total_seconds()))
        # Balance khatam hone pe jitna pay kiya utna hi duration
        if status == "ended_insufficient_balance":
            talk_secs = int(min(talk_secs, call.get("billed_seconds", talk_secs) or talk_secs))
    else:
        talk_secs = 0

    update = {"status": status, "end_time": end_time, "duration_seconds": talk_secs}
    if rating:
        update["rating"] = max(1, min(5, int(rating)))
    if review:
        update["review"] = review[:500]

    res = await db.call_logs.update_one(
        {"call_id": call["call_id"], "status": {"$in": IN_PROGRESS}}, {"$set": update}
    )
    if res.modified_count == 0:
        return {"already_ended": True, "duration_seconds": call.get("duration_seconds", 0), "xp_gained": 0}

    xp_gained = 0
    level_info = None
    if answered:
        xp_gained = add_xp_for_action("call_made")
        user = await db.users.find_one_and_update(
            {"_id": ObjectId(call["caller_id"])},
            {"$inc": {"xp": xp_gained, "call_count": 1, "total_call_minutes": talk_secs // 60}},
            return_document=ReturnDocument.AFTER,
        )
        if user:
            level_info = calculate_level(user.get("xp", 0))
            await db.users.update_one(
                {"_id": user["_id"]},
                {"$set": {"level": level_info["level"], "level_title": level_info["title"]}},
            )
        try:
            await db.host_users.update_one(
                {"_id": ObjectId(call["host_id"])},
                {"$inc": {"total_calls": 1, "total_minutes": talk_secs // 60,
                          "total_earnings": float(call.get("total_cost", 0) or 0)}},
            )
        except Exception:
            pass

    if rating and answered:
        await _apply_rating(call["host_id"], rating, db)

    return {"already_ended": False, "duration_seconds": talk_secs, "xp_gained": xp_gained, "level_info": level_info}


async def _apply_rating(host_id: str, rating: int, db):
    try:
        host = await db.host_users.find_one({"_id": ObjectId(host_id)})
    except Exception:
        return
    if not host:
        return
    rating = max(1, min(5, int(rating)))
    old_rating = host.get("rating", 4.5)
    count = host.get("review_count", 0)
    new_rating = ((old_rating * count) + rating) / (count + 1)
    await db.host_users.update_one(
        {"_id": host["_id"]},
        {"$set": {"rating": round(new_rating, 1)}, "$inc": {"review_count": 1}},
    )


def _billable_until(call: dict, now: datetime, grace: int) -> (datetime, bool):
    """Billing heartbeat safety: returns (bill_until, timed_out)."""
    last = call.get("last_billing_check") or call.get("start_time") or now
    limit = last + timedelta(seconds=grace)
    if now > limit:
        return limit, True
    return now, False


async def _close_stale_calls(user_id: str, db, grace: int):
    """User ek time pe ek hi call me ho sakta hai — purani open calls settle karke band karo."""
    now = datetime.utcnow()
    stale = await db.call_logs.find({"caller_id": user_id, "status": {"$in": IN_PROGRESS}}).to_list(20)
    for call in stale:
        if call.get("start_time"):
            until, _ = _billable_until(call, now, grace)
            await _bill_until(call, until, db)
            await _finalize(call, "completed", until, db)
        else:
            await _finalize(call, "cancelled", now, db)


# ======================= USER ENDPOINTS =======================

@router.post("/initiate")
async def initiate_call(
    request: StartCallRequest,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Start a call (outgoing from host profile, or an accepted incoming call)."""
    if current_user.get("is_guest"):
        raise HTTPException(status_code=403, detail="Guests cannot make calls. Please register.")

    try:
        host = await db.host_users.find_one({"_id": ObjectId(request.host_id), "is_active": True})
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid host ID")
    if not host:
        raise HTTPException(status_code=404, detail="Host not found or inactive")

    if request.call_type == "outgoing" and not host.get("is_online", False):
        raise HTTPException(status_code=400, detail="Host is currently offline")

    cfg = await get_app_settings(db)
    await _close_stale_calls(str(current_user["_id"]), db, cfg["heartbeat_grace_seconds"])

    fresh = await db.users.find_one({"_id": current_user["_id"]}, {"wallet_balance": 1})
    user_balance = float((fresh or {}).get("wallet_balance", 0) or 0)
    price = float(host["price_per_minute"])

    # Kam se kam 1 minute ka balance chahiye
    if user_balance < price:
        raise HTTPException(
            status_code=402,
            detail=f"Insufficient balance. You need at least {price:g} coins for a 1-minute call. "
                   f"Your balance: {user_balance:g} coins. Please recharge your wallet."
        )

    now = datetime.utcnow()
    call_doc = {
        "call_id": str(uuid.uuid4()),
        "call_type": request.call_type,
        "caller_id": str(current_user["_id"]),
        "caller_name": current_user.get("name"),
        "host_id": str(host["_id"]),
        "host_name": host["name"],
        "price_per_minute": price,
        "status": "initiated",  # initiated -> active -> completed / ended_insufficient_balance / timed_out / cancelled
        "start_time": None,
        "end_time": None,
        "duration_seconds": 0,
        "billed_seconds": 0,
        "total_cost": 0.0,
        "balance_at_start": user_balance,
        "last_billing_check": now,
        "rating": None,
        "review": None,
        "created_at": now
    }
    result = await db.call_logs.insert_one(call_doc)
    call_doc["_id"] = result.inserted_id

    return {
        "success": True,
        "message": "Call initiated. Connecting...",
        "call": serialize_doc(call_doc),
        "call_id": call_doc["call_id"],
        "call_type": request.call_type,
        "your_balance": user_balance,
        "price_per_minute": price,
        "estimated_max_minutes": int(user_balance / price),
        "estimated_max_seconds": int(user_balance / (price / 60.0)),
        "call_video": effective_call_video(host),
        "connecting_seconds": cfg["connecting_seconds"],
        "billing_tick_seconds": cfg["billing_tick_seconds"],
    }


@router.post("/answer/{call_id}")
async def answer_call(call_id: str, current_user=Depends(get_current_user), db=Depends(get_db)):
    """Connecting screen khatam → host video starts → billing clock starts NOW."""
    call = await db.call_logs.find_one({"call_id": call_id})
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    # FIX: pehle bina auth koi bhi kisi ki call answer kar sakta tha
    if call["caller_id"] != str(current_user["_id"]):
        raise HTTPException(status_code=403, detail="Unauthorized")

    if call["status"] not in ["initiated", "ringing"]:
        return {"success": False, "message": f"Call cannot be answered (status: {call['status']})"}

    now = datetime.utcnow()
    res = await db.call_logs.update_one(
        {"call_id": call_id, "status": {"$in": ["initiated", "ringing"]}},
        {"$set": {"status": "active", "start_time": now, "last_billing_check": now}}
    )
    if res.modified_count == 0:
        return {"success": False, "message": "Call cannot be answered"}

    fresh = await db.users.find_one({"_id": current_user["_id"]}, {"wallet_balance": 1})
    balance = float((fresh or {}).get("wallet_balance", 0) or 0)
    rate = call["price_per_minute"] / 60.0
    return {
        "success": True,
        "message": "Call connected",
        "start_time": now.isoformat(),
        "balance": balance,
        "seconds_remaining": int(balance / rate) if rate else None,
    }


@router.post("/billing-check")
async def billing_check(
    request: BalanceCheckRequest,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """
    Call every few seconds (`billing_tick_seconds`) during an active call.
    Deducts coins pro-rata for elapsed time; returns `continue` or `end_call`.
    """
    call = await db.call_logs.find_one({"call_id": request.call_id})
    if not call:
        return {"success": False, "action": "end_call", "reason": "call_not_found"}
    if str(current_user["_id"]) != call["caller_id"]:
        raise HTTPException(status_code=403, detail="Unauthorized")
    if call["status"] != "active":
        reason = "insufficient_balance" if call["status"] == "ended_insufficient_balance" else "call_ended"
        return {"success": False, "action": "end_call", "reason": reason, "status": call["status"],
                "total_cost": call.get("total_cost", 0)}
    if not call.get("start_time"):
        return {"success": False, "action": "end_call", "reason": "call_not_started"}

    cfg = await get_app_settings(db)
    now = datetime.utcnow()
    until, timed_out = _billable_until(call, now, cfg["heartbeat_grace_seconds"])

    bill = await _bill_until(call, until, db)
    ppm = float(call["price_per_minute"])
    rate = ppm / 60.0
    balance = bill["balance"]
    seconds_remaining = int(balance / rate) if rate else 0

    if bill["exhausted"] or timed_out:
        status = "ended_insufficient_balance" if bill["exhausted"] else "timed_out"
        fin = await _finalize(call, status, until, db)
        return {
            "success": False,
            "action": "end_call",
            "reason": "insufficient_balance" if bill["exhausted"] else "connection_lost",
            "message": ("Aapka wallet balance khatam ho gaya hai. Call continue karne ke liye recharge karein."
                        if bill["exhausted"] else "Connection lost — call ended."),
            "deducted": bill["charged"],
            "new_balance": balance,
            "balance": balance,
            "total_cost": _r2(call.get("total_cost", 0)),
            "duration_seconds": fin.get("duration_seconds", 0),
            "seconds_remaining": 0,
            "recharge_required": bool(bill["exhausted"]),
        }

    await db.call_logs.update_one({"call_id": call["call_id"]}, {"$set": {"last_billing_check": now}})

    warning = None
    if seconds_remaining <= 60:
        warning = f"Low balance! Sirf {seconds_remaining} second ki call baaki hai — recharge karein"
    elif seconds_remaining <= 120:
        warning = f"Low balance! Only {seconds_remaining // 60} minute(s) remaining"

    return {
        "success": True,
        "action": "continue",
        "deducted": bill["charged"],
        "total_cost": _r2(call.get("total_cost", 0)),
        "new_balance": balance,
        "seconds_remaining": seconds_remaining,
        "elapsed_seconds": int((now - call["start_time"]).total_seconds()),
        "minutes_billed": int(bill["billed_seconds"] // 60),
        "reason": None,
        "warning": warning,
    }


@router.post("/end")
async def end_call(
    request: EndCallRequest,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """User hung up (or cancelled while connecting). Final settlement + optional rating."""
    call = await db.call_logs.find_one({"call_id": request.call_id})
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    if str(current_user["_id"]) != call["caller_id"]:
        raise HTTPException(status_code=403, detail="Unauthorized")

    # Server already ended it (e.g. balance exhausted) — sirf rating save karo
    if call["status"] not in IN_PROGRESS:
        if request.rating and call.get("start_time") and not call.get("rating"):
            r = max(1, min(5, request.rating))
            await db.call_logs.update_one({"call_id": call["call_id"]},
                                          {"$set": {"rating": r, "review": (request.review or None)}})
            await _apply_rating(call["host_id"], r, db)
        fresh = await db.users.find_one({"_id": current_user["_id"]}, {"wallet_balance": 1})
        return {
            "success": True,
            "message": "Call already ended",
            "status": call["status"],
            "duration_seconds": call.get("duration_seconds", 0),
            "duration_minutes": round(call.get("duration_seconds", 0) / 60, 1),
            "total_cost": _r2(call.get("total_cost", 0)),
            "new_balance": float((fresh or {}).get("wallet_balance", 0) or 0),
            "xp_gained": 0,
            "auto_ended": call["status"] == "ended_insufficient_balance",
        }

    cfg = await get_app_settings(db)
    now = datetime.utcnow()

    if not call.get("start_time"):
        # Connecting screen pe hi cancel — koi charge nahi
        await _finalize(call, "cancelled", now, db)
        return {"success": True, "message": "Call cancelled", "status": "cancelled",
                "duration_seconds": 0, "duration_minutes": 0, "total_cost": 0, "xp_gained": 0}

    until, _ = _billable_until(call, now, cfg["heartbeat_grace_seconds"])
    bill = await _bill_until(call, until, db)
    status = "ended_insufficient_balance" if bill["exhausted"] and bill["balance"] <= 0 else "completed"
    fin = await _finalize(call, status, until, db, rating=request.rating, review=request.review)

    secs = fin.get("duration_seconds", 0)
    return {
        "success": True,
        "message": "Call ended",
        "status": status,
        "duration_seconds": secs,
        "duration_minutes": round(secs / 60, 1),
        "total_cost": _r2(call.get("total_cost", 0)),
        "new_balance": bill["balance"],
        "xp_gained": fin.get("xp_gained", 0),
        "level_info": fin.get("level_info"),
    }


@router.get("/random-host")
async def get_random_incoming_call(
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Incoming call: pick a random online host (prefers hosts with an uploaded call video)."""
    if current_user.get("is_guest"):
        raise HTTPException(status_code=403, detail="Guests cannot receive calls")

    cfg = await get_app_settings(db)
    online_hosts = await db.host_users.find({"is_active": True, "is_online": True}).to_list(200)
    if not online_hosts:
        return {"success": False, "message": "No hosts available right now"}

    with_video = [h for h in online_hosts if effective_call_video(h)]
    host = random.choice(with_video or online_hosts)
    return {
        "success": True,
        "incoming_call": True,
        "host": public_host(host),
        "message": f"{host['name']} is calling you!",
        "price_per_minute": host["price_per_minute"],
        "ring_timeout_seconds": cfg["incoming_ring_timeout_seconds"],
    }


@router.post("/incoming/respond")
async def incoming_call_response(
    request: IncomingResponseRequest,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Log a rejected / missed incoming call (accepted calls go through /initiate)."""
    try:
        host = await db.host_users.find_one({"_id": ObjectId(request.host_id)})
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid host ID")
    if not host:
        raise HTTPException(status_code=404, detail="Host not found")
    now = datetime.utcnow()
    await db.call_logs.insert_one({
        "call_id": str(uuid.uuid4()),
        "call_type": "incoming",
        "caller_id": str(current_user["_id"]),
        "caller_name": current_user.get("name"),
        "host_id": str(host["_id"]),
        "host_name": host["name"],
        "price_per_minute": host.get("price_per_minute", 0),
        "status": request.action,
        "start_time": None,
        "end_time": now,
        "duration_seconds": 0,
        "total_cost": 0.0,
        "created_at": now,
    })
    return {"success": True, "status": request.action}


@router.get("/history")
async def call_history(
    page: int = 1,
    limit: int = 20,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Get call history for current user"""
    skip = (page - 1) * limit
    calls = await db.call_logs.find(
        {"caller_id": str(current_user["_id"])}
    ).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    total = await db.call_logs.count_documents({"caller_id": str(current_user["_id"])})

    return {
        "success": True,
        "calls": [serialize_doc(c) for c in calls],
        "total": total,
        "page": page
    }

@router.get("/admin/all")
async def admin_all_calls(
    page: int = 1,
    limit: int = 20,
    db=Depends(get_db),
    admin=Depends(get_current_admin)
):
    """Admin: View all calls"""
    skip = (page - 1) * limit
    calls = await db.call_logs.find().sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    total = await db.call_logs.count_documents({})

    # Stats — har answered call (completed / balance-exhausted / timed-out) count hoti hai
    pipeline = [
        {"$match": {"status": {"$in": ["completed", "ended_insufficient_balance", "timed_out"]}}},
        {"$group": {
            "_id": None,
            "total_calls": {"$sum": 1},
            "total_revenue": {"$sum": "$total_cost"},
            "avg_duration": {"$avg": "$duration_seconds"}
        }}
    ]
    stats_result = await db.call_logs.aggregate(pipeline).to_list(1)
    stats = stats_result[0] if stats_result else {}

    return {
        "success": True,
        "calls": [serialize_doc(c) for c in calls],
        "total": total,
        "stats": {
            "total_completed_calls": stats.get("total_calls", 0),
            "total_revenue": round(stats.get("total_revenue", 0) or 0, 2),
            "avg_duration_seconds": round(stats.get("avg_duration", 0) or 0, 0)
        }
    }
