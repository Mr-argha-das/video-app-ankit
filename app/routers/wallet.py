from fastapi import APIRouter, HTTPException, Depends, Body, Query
from datetime import datetime
from bson import ObjectId
from bson.errors import InvalidId
from pymongo import ReturnDocument
from typing import Optional, List
from pydantic import BaseModel

from app.core.database import get_db
from app.core.security import get_current_user, get_current_admin
from app.utils.helpers import serialize_doc

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

@router.get("/packages")
async def get_coin_packages():
    """Get available coin/recharge packages"""
    return {"success": True, "packages": COIN_PACKAGES}

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
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Get transaction history"""
    query = {"user_id": str(current_user["_id"])}
    if txn_type:
        query["type"] = txn_type

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
