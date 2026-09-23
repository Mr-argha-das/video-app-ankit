from fastapi import APIRouter, HTTPException, Depends, Body
from datetime import datetime
import re

from app.core.database import get_db
from app.core.security import get_current_admin, get_any_authenticated

router = APIRouter(prefix="/upid", tags=["Single UPID Module"])

# UPI handle format: username@bank  ya  9876543210@upi
UPID_REGEX = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9._\-]{1,49}@[A-Za-z]{2,64}$")

def validate_upid(upid: str) -> str:
    upid = (upid or "").strip()
    if not UPID_REGEX.match(upid):
        raise HTTPException(
            status_code=400,
            detail="Invalid UPID format. Example: business@paytm ya 9876543210@upi"
        )
    return upid

@router.post("/add")
async def add_upid(
    upid: str = Body(..., embed=False),
    db=Depends(get_db),
    admin=Depends(get_current_admin)  # FIX: pehle koi bhi set kar sakta tha!
):
    upid = validate_upid(upid)
    existing = await db.upid_config.find_one({})

    if existing:
        raise HTTPException(status_code=400, detail="UPID already exists. Use update.")

    doc = {
        "upid": upid,
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow()
    }

    await db.upid_config.insert_one(doc)

    return {
        "success": True,
        "message": "UPID created",
        "upid": upid
    }

@router.get("/get")
async def get_upid(
    db=Depends(get_db),
    requester=Depends(get_any_authenticated)  # FIX: pehle public tha — ab login zaroori
):
    doc = await db.upid_config.find_one({})

    if not doc:
        raise HTTPException(status_code=404, detail="UPID not found")

    return {
        "success": True,
        "upid": doc["upid"]
    }

@router.put("/update")
async def update_upid(
    upid: str = Body(..., embed=False),
    db=Depends(get_db),
    admin=Depends(get_current_admin)  # FIX: pehle koi bhi replace kar sakta tha!
):
    upid = validate_upid(upid)
    existing = await db.upid_config.find_one({})

    if not existing:
        raise HTTPException(status_code=404, detail="UPID not found. Create first.")

    await db.upid_config.update_one(
        {"_id": existing["_id"]},  # FIX: pehle {} filter tha (koi bhi doc update ho sakta tha)
        {
            "$set": {
                "upid": upid,
                "updated_at": datetime.utcnow()
            }
        }
    )

    return {
        "success": True,
        "message": "UPID updated",
        "upid": upid
    }
