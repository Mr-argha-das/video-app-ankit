import hmac
import hashlib
import base64
import httpx
import aiofiles
import uuid
from fastapi import APIRouter, HTTPException, Depends, Body, Query, Request, UploadFile, File, Form
from datetime import datetime, timedelta
from bson import ObjectId
from bson.errors import InvalidId
from pymongo import ReturnDocument
from typing import Optional, List
from pydantic import BaseModel

from app.core.database import get_db
from app.core.security import get_current_user, get_current_admin
from app.utils.helpers import serialize_doc
from app.utils.media import save_upload, delete_media_file

router = APIRouter(prefix="/wallet", tags=["Wallet"])

class RechargeRequest(BaseModel):
    amount: float
    payment_method: str = "upi"
    transaction_ref: Optional[str] = None  # UPI ka 12-digit UTR/ref — admin verify karega

class AdminCreditRequest(BaseModel):
    user_id: str
    amount: float
    reason: str = "Admin Credit"

class RejectRechargeRequest(BaseModel):
    reason: Optional[str] = "Payment not verified"

# Coin packages
COIN_PACKAGES = [
    {"id": "pack_50", "coins": 50, "price": 49, "bonus": 0, "label": "Starter Pack"},
    {"id": "pack_100", "coins": 100, "price": 89, "bonus": 10, "label": "Basic Pack"},
    {"id": "pack_250", "coins": 250, "price": 199, "bonus": 30, "label": "Popular Pack"},
    {"id": "pack_500", "coins": 500, "price": 379, "bonus": 75, "label": "Value Pack"},
    {"id": "pack_1000", "coins": 1000, "price": 699, "bonus": 200, "label": "Mega Pack"},
    {"id": "pack_2000", "coins": 2000, "price": 1299, "bonus": 500, "label": "Super Pack"},
]

def _package_for_amount(amount: float) -> dict:
    """Amount se matching package find karo (bonus ke saath).
    Custom amount pe 1 INR = 1 coin, no bonus."""
    for pack in COIN_PACKAGES:
        if pack["price"] == amount:
            return {"coins": pack["coins"] + pack["bonus"], "bonus": pack["bonus"], "pack": pack}
    return {"coins": amount, "bonus": 0, "pack": None}

@router.get("/balance")
async def get_wallet_balance(current_user=Depends(get_current_user), db=Depends(get_db)):
    """Get user wallet balance"""
    user = await db.users.find_one({"_id": current_user["_id"]})
    return {
        "success": True,
        "balance": user.get("wallet_balance", 0),
        "currency": "coins",
        "user_id": str(user["_id"])
    }

def _default_packs():
    """Seed packs: pay_amount/get_amount (₹ coins). 1 coin = ₹1."""
    return [
        {"pay_amount": 99, "get_amount": 99, "bonus": 0, "is_best": False, "sort": 1},
        {"pay_amount": 149, "get_amount": 149, "bonus": 0, "is_best": False, "sort": 2},
        {"pay_amount": 200, "get_amount": 204, "bonus": 4, "is_best": False, "sort": 3},
        {"pay_amount": 299, "get_amount": 304, "bonus": 5, "is_best": False, "sort": 4},
        {"pay_amount": 500, "get_amount": 520, "bonus": 20, "is_best": False, "sort": 5},
        {"pay_amount": 800, "get_amount": 903, "bonus": 103, "is_best": True, "sort": 6},
        {"pay_amount": 1000, "get_amount": 1080, "bonus": 80, "is_best": False, "sort": 7},
        {"pay_amount": 2000, "get_amount": 2160, "bonus": 160, "is_best": False, "sort": 8},
        {"pay_amount": 3000, "get_amount": 3210, "bonus": 210, "is_best": False, "sort": 9},
        {"pay_amount": 5000, "get_amount": 5500, "bonus": 500, "is_best": False, "sort": 10},
        {"pay_amount": 10000, "get_amount": 11500, "bonus": 1500, "is_best": False, "sort": 11},
        {"pay_amount": 20000, "get_amount": 24000, "bonus": 4000, "is_best": False, "sort": 12},
    ]


async def _get_packs(db):
    """Read active packs from DB; seed on first use."""
    packs = await db.talktime_packs.find({"is_active": True}).sort("sort", 1).to_list(100)
    if not packs:
        now = datetime.utcnow()
        docs = []
        for p in _default_packs():
            docs.append({**p, "is_active": True, "created_at": now, "updated_at": now})
        if docs:
            await db.talktime_packs.insert_many(docs)
            packs = await db.talktime_packs.find({"is_active": True}).sort("sort", 1).to_list(100)
    return [{"id": f"pack_{p['pay_amount']}", "pay_amount": p["pay_amount"],
             "get_amount": p["get_amount"], "bonus": p.get("bonus", 0),
             "is_best": bool(p.get("is_best", False))} for p in packs]


@router.get("/packages")
async def get_coin_packages(db=Depends(get_db)):
    """Get available talktime recharge packages (from talktime_packs collection)."""
    packs = await _get_packs(db)
    return {"success": True, "packages": packs}

@router.post("/recharge")
async def recharge_wallet(
    request: RechargeRequest,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """
    Create a recharge REQUEST. Coins tabhi credit honge jab admin
    UPI payment verify karke approve karega.
    FIX: pehle koi bhi amount bhejte hi coins instantly credit ho jaate the —
    bina kisi payment verification ke.
    """
    if current_user.get("is_guest"):
        raise HTTPException(status_code=403, detail="Guests cannot recharge. Please register first.")

    if request.amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be positive")

    match = _package_for_amount(request.amount)
    coins_to_credit = match["coins"]
    bonus = match["bonus"]

    # Get current UPID so user ko pata ho kahan payment bhejni hai
    upid_doc = await db.upid_config.find_one({})

    req_doc = {
        "user_id": str(current_user["_id"]),
        "user_name": current_user.get("name"),
        "user_mobile": current_user.get("mobile"),
        "amount_inr": request.amount,
        "coins_to_credit": coins_to_credit,
        "bonus_coins": bonus,
        "package_id": match["pack"]["id"] if match["pack"] else None,
        "payment_method": request.payment_method,
        "transaction_ref": request.transaction_ref,
        "status": "pending",  # pending -> approved / rejected
        "created_at": datetime.utcnow()
    }
    result = await db.recharge_requests.insert_one(req_doc)

    return {
        "success": True,
        "message": "Recharge request created. Coins will be credited after admin verifies your payment.",
        "request_id": str(result.inserted_id),
        "amount_inr": request.amount,
        "coins_to_receive": coins_to_credit,
        "bonus_coins": bonus,
        "status": "pending",
        "pay_to_upid": upid_doc["upid"] if upid_doc else None
    }

@router.get("/my-recharges")
async def my_recharge_requests(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=50),
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """User: Apni recharge requests ka status dekho"""
    skip = (page - 1) * limit
    query = {"user_id": str(current_user["_id"])}
    reqs = await db.recharge_requests.find(query).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    total = await db.recharge_requests.count_documents(query)
    return {
        "success": True,
        "recharges": [serialize_doc(r) for r in reqs],
        "total": total,
        "page": page
    }

@router.get("/transactions")
async def get_transactions(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=50),
    txn_type: Optional[str] = Query(None, enum=["credit", "debit"]),
    last_days: int = Query(90, ge=0, description="Default 90 days; 0 = all time"),
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Get transaction history (default last 90 days)"""
    query = {"user_id": str(current_user["_id"])}
    if txn_type:
        query["type"] = txn_type
    if last_days and last_days > 0:
        query["created_at"] = {"$gte": datetime.utcnow() - timedelta(days=last_days)}

    skip = (page - 1) * limit
    txns = await db.transactions.find(query).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    total = await db.transactions.count_documents(query)

    return {
        "success": True,
        "transactions": [serialize_doc(t) for t in txns],
        "total": total,
        "page": page
    }

async def deduct_wallet(user_id: ObjectId, amount: float, description: str, db) -> dict:
    """
    Internal function to deduct wallet balance.
    FIX: pehle read-modify-write tha (race condition — concurrent calls pe
    balance galat ho sakta tha). Ab atomic conditional $inc hai.
    """
    # Atomic: balance sirf tabhi kam hoga jab sufficient hai
    user = await db.users.find_one_and_update(
        {"_id": user_id, "wallet_balance": {"$gte": amount}},
        {"$inc": {"wallet_balance": -amount}},
        return_document=ReturnDocument.AFTER
    )

    if not user:
        existing = await db.users.find_one({"_id": user_id})
        if not existing:
            return {"success": False, "reason": "user_not_found"}
        return {"success": False, "reason": "insufficient_balance", "balance": existing.get("wallet_balance", 0)}

    new_balance = user.get("wallet_balance", 0)
    await db.transactions.insert_one({
        "user_id": str(user_id),
        "type": "debit",
        "amount": amount,
        "description": description,
        "status": "success",
        "balance_before": new_balance + amount,
        "balance_after": new_balance,
        "created_at": datetime.utcnow()
    })

    return {"success": True, "new_balance": new_balance, "deducted": amount}

# ========== ADMIN WALLET APIs ==========

@router.post("/admin/credit")
async def admin_credit_user(
    request: AdminCreditRequest,
    db=Depends(get_db),
    admin=Depends(get_current_admin)
):
    """Admin: Credit coins to user"""
    if request.amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be positive")
    try:
        user = await db.users.find_one({"_id": ObjectId(request.user_id)})
    except (InvalidId, TypeError):
        raise HTTPException(status_code=400, detail="Invalid user ID")
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # Atomic credit
    updated = await db.users.find_one_and_update(
        {"_id": user["_id"]},
        {"$inc": {"wallet_balance": request.amount}},
        return_document=ReturnDocument.AFTER
    )
    new_balance = updated.get("wallet_balance", 0)

    await db.transactions.insert_one({
        "user_id": request.user_id,
        "type": "credit",
        "amount": request.amount,
        "description": f"Admin Credit: {request.reason}",
        "status": "success",
        "balance_before": new_balance - request.amount,
        "balance_after": new_balance,
        "created_at": datetime.utcnow()
    })
    return {"success": True, "message": f"{request.amount} coins credited", "new_balance": new_balance}

@router.get("/admin/all-transactions")
async def admin_all_transactions(
    page: int = 1,
    limit: int = 20,
    db=Depends(get_db),
    admin=Depends(get_current_admin)
):
    """Admin: View all transactions"""
    skip = (page - 1) * limit
    txns = await db.transactions.find().sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    total = await db.transactions.count_documents({})

    # Calculate stats
    pipeline = [
        {"$group": {"_id": "$type", "total": {"$sum": "$amount"}, "count": {"$sum": 1}}}
    ]
    stats = await db.transactions.aggregate(pipeline).to_list(10)
    stats_dict = {s["_id"]: {"total": s["total"], "count": s["count"]} for s in stats}

    return {
        "success": True,
        "transactions": [serialize_doc(t) for t in txns],
        "total": total,
        "stats": stats_dict
    }

# ========== ADMIN: RECHARGE APPROVAL FLOW ==========

@router.get("/admin/recharges")
async def admin_list_recharges(
    status: Optional[str] = Query(None, enum=["pending", "approved", "rejected"]),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db=Depends(get_db),
    admin=Depends(get_current_admin)
):
    """Admin: Recharge requests list (payment verify karne ke liye)"""
    query = {}
    if status:
        query["status"] = status
    skip = (page - 1) * limit
    reqs = await db.recharge_requests.find(query).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    total = await db.recharge_requests.count_documents(query)
    pending = await db.recharge_requests.count_documents({"status": "pending"})
    return {
        "success": True,
        "recharges": [serialize_doc(r) for r in reqs],
        "total": total,
        "pending_count": pending,
        "page": page
    }

@router.post("/admin/recharges/{request_id}/approve")
async def admin_approve_recharge(
    request_id: str,
    db=Depends(get_db),
    admin=Depends(get_current_admin)
):
    """
    Admin: Payment verify karke recharge approve karo — coins user ko credit honge.
    Atomic: dobara approve ho hi nahi sakta (status race-safe).
    """
    try:
        oid = ObjectId(request_id)
    except (InvalidId, TypeError):
        raise HTTPException(status_code=400, detail="Invalid request ID")

    # Pehle "pending" se "approved" karo — agar dobara call aaya toh matched 0
    req = await db.recharge_requests.find_one_and_update(
        {"_id": oid, "status": "pending"},
        {"$set": {"status": "approved", "approved_at": datetime.utcnow()}},
        return_document=ReturnDocument.BEFORE
    )
    if not req:
        existing = await db.recharge_requests.find_one({"_id": oid})
        if not existing:
            raise HTTPException(status_code=404, detail="Recharge request not found")
        raise HTTPException(status_code=400, detail=f"Request already {existing['status']}")

    try:
        user_oid = ObjectId(req["user_id"])
    except (InvalidId, TypeError):
        raise HTTPException(status_code=400, detail="Invalid user ID on request")

    updated = await db.users.find_one_and_update(
        {"_id": user_oid},
        {"$inc": {"wallet_balance": req["coins_to_credit"]}},
        return_document=ReturnDocument.AFTER
    )
    if not updated:
        # User deleted ho gaya — request wapas pending karo
        await db.recharge_requests.update_one(
            {"_id": oid},
            {"$set": {"status": "pending"}, "$unset": {"approved_at": ""}}
        )
        raise HTTPException(status_code=404, detail="User not found")

    new_balance = updated.get("wallet_balance", 0)
    await db.users.update_one(
        {"_id": user_oid},
        {"$set": {"has_recharged": True}},
    )
    await db.transactions.insert_one({
        "user_id": req["user_id"],
        "type": "credit",
        "amount": req["coins_to_credit"],
        "base_amount": req["amount_inr"],
        "bonus_coins": req.get("bonus_coins", 0),
        "payment_method": req.get("payment_method", "upi"),
        "transaction_ref": req.get("transaction_ref") or f"RCH{request_id[-8:]}",
        "description": f"Wallet Recharge - ₹{req['amount_inr']} (approved)",
        "status": "success",
        "balance_before": new_balance - req["coins_to_credit"],
        "balance_after": new_balance,
        "recharge_request_id": request_id,
        "created_at": datetime.utcnow()
    })

    return {
        "success": True,
        "message": f"{req['coins_to_credit']} coins credited to {req.get('user_name', 'user')}",
        "new_balance": new_balance
    }

@router.post("/admin/recharges/{request_id}/reject")
async def admin_reject_recharge(
    request_id: str,
    body: Optional[RejectRechargeRequest] = None,
    db=Depends(get_db),
    admin=Depends(get_current_admin)
):
    """Admin: Recharge request reject karo (payment nahi mili / ref mismatch)"""
    try:
        oid = ObjectId(request_id)
    except (InvalidId, TypeError):
        raise HTTPException(status_code=400, detail="Invalid request ID")

    req = await db.recharge_requests.find_one_and_update(
        {"_id": oid, "status": "pending"},
        {"$set": {
            "status": "rejected",
            "reject_reason": (body.reason if body else None) or "Payment not verified",
            "rejected_at": datetime.utcnow()
        }},
        return_document=ReturnDocument.BEFORE
    )
    if not req:
        existing = await db.recharge_requests.find_one({"_id": oid})
        if not existing:
            raise HTTPException(status_code=404, detail="Recharge request not found")
        raise HTTPException(status_code=400, detail=f"Request already {existing['status']}")

    return {"success": True, "message": "Recharge request rejected"}


# ========== ADMIN: TALKTIME PACKS CRUD ==========

class PackRequest(BaseModel):
    pay_amount: float
    get_amount: float
    bonus: Optional[float] = None
    is_best: bool = False
    sort: int = 0
    is_active: bool = True


@router.post("/wallet/admin/packs")
async def admin_add_pack(
    body: PackRequest,
    db=Depends(get_db),
    admin=Depends(get_current_admin),
):
    """Admin: add a talktime pack."""
    if body.pay_amount <= 0 or body.get_amount <= 0:
        raise HTTPException(status_code=400, detail="Amounts must be positive")
    if body.bonus is None:
        body.bonus = body.get_amount - body.pay_amount
    # only one best pack
    if body.is_best:
        await db.talktime_packs.update_many({"is_best": True}, {"$set": {"is_best": False}})
    doc = {
        "pay_amount": body.pay_amount,
        "get_amount": body.get_amount,
        "bonus": body.bonus,
        "is_best": bool(body.is_best),
        "sort": body.sort,
        "is_active": bool(body.is_active),
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow(),
    }
    result = await db.talktime_packs.insert_one(doc)
    doc["id"] = str(result.inserted_id)
    return {"success": True, "message": "Pack added", "pack": doc}


@router.put("/wallet/admin/packs/{pack_id}")
async def admin_update_pack(
    pack_id: str,
    body: PackRequest,
    db=Depends(get_db),
    admin=Depends(get_current_admin),
):
    """Admin: update a talktime pack."""
    try:
        oid = ObjectId(pack_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid pack ID")
    if body.bonus is None:
        body.bonus = body.get_amount - body.pay_amount
    if body.is_best:
        await db.talktime_packs.update_many({"is_best": True, "_id": {"$ne": oid}}, {"$set": {"is_best": False}})
    update = {
        "pay_amount": body.pay_amount,
        "get_amount": body.get_amount,
        "bonus": body.bonus,
        "is_best": bool(body.is_best),
        "sort": body.sort,
        "is_active": bool(body.is_active),
        "updated_at": datetime.utcnow(),
    }
    res = await db.talktime_packs.update_one({"_id": oid}, {"$set": update})
    if res.matched_count == 0:
        raise HTTPException(status_code=404, detail="Pack not found")
    return {"success": True, "message": "Pack updated"}


@router.delete("/wallet/admin/packs/{pack_id}")
async def admin_delete_pack(
    pack_id: str,
    db=Depends(get_db),
    admin=Depends(get_current_admin),
):
    """Admin: deactivate a talktime pack (soft delete)."""
    try:
        oid = ObjectId(pack_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid pack ID")
    res = await db.talktime_packs.update_one(
        {"_id": oid}, {"$set": {"is_active": False, "updated_at": datetime.utcnow()}}
    )
    if res.matched_count == 0:
        raise HTTPException(status_code=404, detail="Pack not found")
    return {"success": True, "message": "Pack deactivated"}


# ========== RAZORPAY PAYMENTS ==========

class CreateOrderRequest(BaseModel):
    pack_id: Optional[str] = None  # "pack_800"
    amount: Optional[float] = None  # custom INR amount


class VerifyPaymentRequest(BaseModel):
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str


def _razorpay_auth() -> tuple:
    key_id = settings.RAZORPAY_KEY_ID
    key_secret = settings.RAZORPAY_KEY_SECRET
    if not key_id or not key_secret:
        raise HTTPException(status_code=500, detail="Razorpay not configured on server")
    return (key_id, key_secret)


async def _razorpay_request(method: str, path: str, json: Optional[dict] = None):
    auth = _razorpay_auth()
    url = f"https://api.razorpay.com/v1/{path.lstrip('/')}"
    async with httpx.AsyncClient(timeout=30, auth=auth) as client:
        if method == "POST":
            r = await client.post(url, json=json)
        else:
            r = await client.get(url)
    if r.status_code >= 400:
        raise HTTPException(status_code=502, detail=f"Razorpay error: {r.text[:200]}")
    return r.json()


def _verify_razorpay_signature(order_id: str, payment_id: str, signature: str) -> bool:
    key_secret = settings.RAZORPAY_KEY_SECRET
    if not key_secret:
        return False
    body = f"{order_id}|{payment_id}".encode()
    expected = hmac.new(key_secret.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)


async def _credit_payment(user_id: str, amount_coins: float, order_id: str, payment_id: str, db):
    """Idempotent credit: only if this order hasn't been credited yet."""
    already = await db.payments.find_one({"razorpay_order_id": order_id, "status": "paid"})
    if already:
        return False  # already credited
    await db.users.update_one(
        {"_id": ObjectId(user_id)},
        {"$inc": {"wallet_balance": amount_coins}, "$set": {"has_recharged": True}},
    )
    await db.payments.update_one(
        {"razorpay_order_id": order_id},
        {"$set": {"status": "paid", "payment_id": payment_id, "paid_at": datetime.utcnow()}},
    )
    await db.transactions.insert_one({
        "user_id": user_id,
        "type": "credit",
        "amount": amount_coins,
        "base_amount": amount_coins,
        "bonus_coins": 0,
        "payment_method": "razorpay",
        "transaction_ref": payment_id,
        "description": f"Wallet Recharge - ₹{amount_coins:g} (Razorpay)",
        "status": "success",
        "balance_before": 0,
        "balance_after": 0,
        "recharge_request_id": order_id,
        "created_at": datetime.utcnow(),
    })
    return True


@router.post("/wallet/pay/create-order")
async def pay_create_order(
    body: CreateOrderRequest,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Create a Razorpay order for a talktime pack or custom amount."""
    if body.pack_id:
        pack = await db.talktime_packs.find_one({"id": body.pack_id, "is_active": True})
        # support both stored _id and public pack_{pay_amount} id
        if not pack:
            pack = await db.talktime_packs.find_one({"_id": ObjectId(body.pack_id), "is_active": True}) \
                if ObjectId.is_valid(body.pack_id) else None
        if not pack:
            raise HTTPException(status_code=404, detail="Pack not found")
        pay_amount = float(pack["pay_amount"])
        get_amount = float(pack["get_amount"])
    elif body.amount and body.amount > 0:
        pay_amount = float(body.amount)
        get_amount = float(body.amount)
    else:
        raise HTTPException(status_code=400, detail="pack_id or amount required")

    order_data = {
        "amount": int(round(pay_amount * 100)),  # paise
        "currency": "INR",
        "receipt": f"order_{current_user['_id']}_{int(datetime.utcnow().timestamp())}",
        "notes": {"user_id": str(current_user["_id"]), "pay_amount": str(pay_amount)},
    }
    order = await _razorpay_request("POST", "/orders", order_data)

    await db.payments.update_one(
        {"razorpay_order_id": order["id"]},
        {"$setOnInsert": {
            "razorpay_order_id": order["id"],
            "user_id": str(current_user["_id"]),
            "pay_amount": pay_amount,
            "get_amount": get_amount,
            "status": "created",
            "created_at": datetime.utcnow(),
        }},
        upsert=True,
    )

    return {
        "success": True,
        "order_id": order["id"],
        "amount": order["amount"],
        "currency": order["currency"],
        "key_id": settings.RAZORPAY_KEY_ID,
        "pay_amount": pay_amount,
        "get_amount": get_amount,
    }


@router.post("/wallet/pay/verify")
async def pay_verify(
    body: VerifyPaymentRequest,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Verify Razorpay payment signature and credit coins (idempotent)."""
    if not _verify_razorpay_signature(body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature):
        raise HTTPException(status_code=400, detail="Invalid payment signature")

    payment = await db.payments.find_one({"razorpay_order_id": body.razorpay_order_id})
    if not payment:
        raise HTTPException(status_code=404, detail="Order not found")
    if str(payment["user_id"]) != str(current_user["_id"]):
        raise HTTPException(status_code=403, detail="Order not owned by this user")

    credited = await _credit_payment(
        str(payment["user_id"]), float(payment["get_amount"]),
        body.razorpay_order_id, body.razorpay_payment_id, db,
    )

    return {
        "success": True,
        "message": "Payment verified" if credited else "Already credited",
        "credited": credited,
        "get_amount": float(payment["get_amount"]),
    }


@router.post("/wallet/pay/webhook")
async def pay_webhook(
    request: Request,
    db=Depends(get_db),
):
    """Razorpay webhook (signature verified, idempotent credit)."""
    secret = settings.RAZORPAY_WEBHOOK_SECRET
    body = await request.body()
    signature = request.headers.get("x-razorpay-signature", "")
    if secret:
        expected = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, signature):
            raise HTTPException(status_code=400, detail="Invalid webhook signature")
    try:
        import json
        payload = json.loads(body)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON")

    event = payload.get("event", "")
    if event == "payment.captured":
        ent = payload.get("payload", {}).get("payment", {}).get("entity", {})
        order_id = ent.get("order_id")
        payment_id = ent.get("id")
        if order_id and payment_id:
            payment = await db.payments.find_one({"razorpay_order_id": order_id})
            if payment and payment.get("status") != "paid":
                await _credit_payment(
                    str(payment["user_id"]), float(payment["get_amount"]),
                    order_id, payment_id, db,
                )
    return {"success": True}


@router.get("/wallet/pay/upi-qr")
async def pay_upi_qr(
    amount: float,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Build a UPI deep-link payload for the QR screen."""
    if amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be positive")
    upid_doc = await db.upid_config.find_one({})
    upi_id = upid_doc["upid"] if upid_doc else ""
    upi_url = (
        f"upi://pay?pa={upi_id}&pn=OnlineDost&am={amount:g}&cu=INR"
        if upi_id else ""
    )
    return {
        "success": True,
        "upi_url": upi_url,
        "amount": amount,
        "note": "Pay via any UPI app, then share the UTR with admin (manual approval) or use Razorpay.",
    }


# ========== QR CONFIG (admin set QR/UPI for deposits) ==========

class QrConfigRequest(BaseModel):
    upi_id: str
    qr_image_url: Optional[str] = None


@router.get("/wallet/qr-config")
async def get_qr_config(db=Depends(get_db)):
    """Get QR config for deposits (UPI ID + QR image URL). Public."""
    doc = await db.qr_config.find_one({})
    if not doc:
        upid_doc = await db.upid_config.find_one({})
        return {
            "success": True,
            "upi_id": upid_doc["upid"] if upid_doc else "",
            "qr_image_url": "",
        }
    return {
        "success": True,
        "upi_id": doc.get("upi_id", ""),
        "qr_image_url": doc.get("qr_image_url", ""),
    }


@router.post("/wallet/admin/qr-config")
async def set_qr_config(
    body: QrConfigRequest,
    db=Depends(get_db),
    admin=Depends(get_current_admin),
):
    """Admin: set QR config for deposits (UPI ID + QR image URL)."""
    await db.qr_config.update_one(
        {},
        {
            "$set": {
                "upi_id": body.upi_id,
                "qr_image_url": body.qr_image_url or "",
                "updated_at": datetime.utcnow(),
            }
        },
        upsert=True,
    )
    return {"success": True, "message": "QR config saved"}


# ========== DEPOSIT REQUEST (user uploads screenshot + UTR) ==========

class DepositApproveRequest(BaseModel):
    amount: float
    reason: Optional[str] = "Deposit approved"


@router.post("/wallet/deposit")
async def create_deposit(
    amount: float = Form(...),
    transaction_ref: Optional[str] = Form(None),
    screenshot: UploadFile = File(...),
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """
    User: UPI payment karke screenshot upload kare, UTR daale.
    Admin approve karega toh coins credit honge.
    """
    if current_user.get("is_guest"):
        raise HTTPException(status_code=403, detail="Guests cannot deposit. Please register first.")
    if amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be positive")

    # Save screenshot
    screenshot_url = None
    if screenshot and screenshot.filename:
        ext = (screenshot.filename or "").rsplit(".", 1)[-1].lower() if "." in (screenshot.filename or "") else ""
        if ext not in {"jpg", "jpeg", "png", "webp"}:
            raise HTTPException(status_code=400, detail="Only JPG/PNG/WEBP screenshots allowed")
        filename = f"{uuid.uuid4()}.{ext}"
        filepath = f"static/uploads/deposits/{filename}"
        import os
        os.makedirs("static/uploads/deposits", exist_ok=True)
        async with aiofiles.open(filepath, "wb") as f:
            await f.write(await screenshot.read())
        screenshot_url = f"/static/uploads/deposits/{filename}"

    req_doc = {
        "user_id": str(current_user["_id"]),
        "user_name": current_user.get("name"),
        "user_mobile": current_user.get("mobile"),
        "amount_inr": amount,
        "transaction_ref": transaction_ref,
        "screenshot_url": screenshot_url,
        "status": "pending",  # pending -> approved / rejected
        "created_at": datetime.utcnow(),
    }
    result = await db.deposit_requests.insert_one(req_doc)

    return {
        "success": True,
        "message": "Deposit request submitted. Admin verify karke coins credit karega.",
        "request_id": str(result.inserted_id),
        "amount_inr": amount,
        "status": "pending",
    }


@router.get("/wallet/my-deposits")
async def my_deposits(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=50),
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    """User: Apni deposit requests ka status dekho."""
    skip = (page - 1) * limit
    query = {"user_id": str(current_user["_id"])}
    reqs = await db.deposit_requests.find(query).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    total = await db.deposit_requests.count_documents(query)
    return {
        "success": True,
        "deposits": [serialize_doc(r) for r in reqs],
        "total": total,
        "page": page,
    }


# ========== ADMIN: DEPOSIT APPROVAL ==========

@router.get("/wallet/admin/deposits")
async def admin_list_deposits(
    status: Optional[str] = Query(None, enum=["pending", "approved", "rejected"]),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db=Depends(get_db),
    admin=Depends(get_current_admin),
):
    """Admin: All deposit requests (verify screenshot + UTR, approve with manual amount)."""
    query = {}
    if status:
        query["status"] = status
    skip = (page - 1) * limit
    reqs = await db.deposit_requests.find(query).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)
    total = await db.deposit_requests.count_documents(query)
    pending = await db.deposit_requests.count_documents({"status": "pending"})
    return {
        "success": True,
        "deposits": [serialize_doc(r) for r in reqs],
        "total": total,
        "pending_count": pending,
        "page": page,
    }


@router.post("/wallet/admin/deposits/{request_id}/approve")
async def admin_approve_deposit(
    request_id: str,
    body: DepositApproveRequest,
    db=Depends(get_db),
    admin=Depends(get_current_admin),
):
    """
    Admin: Deposit approve karo — manual amount enter karke user ko coins credit karo.
    Idempotent: dobara approve ho hi nahi sakta.
    """
    try:
        oid = ObjectId(request_id)
    except (InvalidId, TypeError):
        raise HTTPException(status_code=400, detail="Invalid request ID")

    if body.amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be positive")

    req = await db.deposit_requests.find_one_and_update(
        {"_id": oid, "status": "pending"},
        {"$set": {"status": "approved", "approved_at": datetime.utcnow()}},
        return_document=ReturnDocument.BEFORE,
    )
    if not req:
        existing = await db.deposit_requests.find_one({"_id": oid})
        if not existing:
            raise HTTPException(status_code=404, detail="Deposit request not found")
        raise HTTPException(status_code=400, detail=f"Request already {existing['status']}")

    try:
        user_oid = ObjectId(req["user_id"])
    except (InvalidId, TypeError):
        raise HTTPException(status_code=400, detail="Invalid user ID on request")

    updated = await db.users.find_one_and_update(
        {"_id": user_oid},
        {"$inc": {"wallet_balance": body.amount}, "$set": {"has_recharged": True}},
        return_document=ReturnDocument.AFTER,
    )
    if not updated:
        await db.deposit_requests.update_one(
            {"_id": oid},
            {"$set": {"status": "pending"}, "$unset": {"approved_at": ""}},
        )
        raise HTTPException(status_code=404, detail="User not found")

    new_balance = updated.get("wallet_balance", 0)
    await db.transactions.insert_one(
        {
            "user_id": req["user_id"],
            "type": "credit",
            "amount": body.amount,
            "base_amount": req["amount_inr"],
            "bonus_coins": 0,
            "payment_method": "upi_deposit",
            "transaction_ref": req.get("transaction_ref") or f"DEP{request_id[-8:]}",
            "description": f"UPI Deposit - ₹{body.amount} (approved by admin)",
            "status": "success",
            "balance_before": new_balance - body.amount,
            "balance_after": new_balance,
            "deposit_request_id": request_id,
            "created_at": datetime.utcnow(),
        }
    )

    return {
        "success": True,
        "message": f"₹{body.amount} coins credited to {req.get('user_name', 'user')}",
        "new_balance": new_balance,
    }


@router.post("/wallet/admin/deposits/{request_id}/reject")
async def admin_reject_deposit(
    request_id: str,
    body: Optional[RejectRechargeRequest] = None,
    db=Depends(get_db),
    admin=Depends(get_current_admin),
):
    """Admin: Deposit request reject karo."""
    try:
        oid = ObjectId(request_id)
    except (InvalidId, TypeError):
        raise HTTPException(status_code=400, detail="Invalid request ID")

    req = await db.deposit_requests.find_one_and_update(
        {"_id": oid, "status": "pending"},
        {"$set": {
            "status": "rejected",
            "reject_reason": (body.reason if body else None) or "Payment not verified",
            "rejected_at": datetime.utcnow(),
        }},
        return_document=ReturnDocument.BEFORE,
    )
    if not req:
        existing = await db.deposit_requests.find_one({"_id": oid})
        if not existing:
            raise HTTPException(status_code=404, detail="Deposit request not found")
        raise HTTPException(status_code=400, detail=f"Request already {existing['status']}")

    return {"success": True, "message": "Deposit request rejected"}
