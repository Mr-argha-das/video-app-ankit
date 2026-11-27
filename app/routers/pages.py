"""Static pages (privacy, terms, etc.) — admin-editable HTML/markdown.

GET /api/v1/pages/{slug}  — public
PUT   /api/v1/admin/pages/{slug}  — admin create/update
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel

from app.core.database import get_db
from app.core.security import get_current_admin
from app.utils.helpers import serialize_doc

router = APIRouter(prefix="/pages", tags=["Static Pages"])

DEFAULT_PAGES = [
    {"slug": "privacy-policy", "title": "Privacy Policy", "content": "<p>OnlineDost Privacy Policy...</p>"},
    {"slug": "terms", "title": "Terms and Conditions", "content": "<p>Terms of Use...</p>"},
    {"slug": "community-guidelines", "title": "Community Guidelines", "content": "<p>Community rules...</p>"},
    {"slug": "content-moderation", "title": "Content Moderation", "content": "<p>Moderation policy...</p>"},
    {"slug": "compliance", "title": "Compliance", "content": "<p>Compliance information...</p>"},
    {"slug": "subscription-privacy", "title": "Subscription Privacy", "content": "<p>Subscription privacy...</p>"},
    {"slug": "refund-cancellation", "title": "Refund & Cancellation", "content": "<p>Refund policy...</p>"},
]


class PageContent(BaseModel):
    title: Optional[str] = None
    content: str


async def _seed_pages(db):
    now = datetime.utcnow()
    for p in DEFAULT_PAGES:
        await db.pages.update_one(
            {"slug": p["slug"]},
            {"$setOnInsert": {**p, "created_at": now, "updated_at": now}},
            upsert=True,
        )


@router.get("/{slug}")
async def get_page(slug: str, db=Depends(get_db)):
    """Public page content."""
    await _seed_pages(db)
    page = await db.pages.find_one({"slug": slug})
    if not page:
        raise HTTPException(status_code=404, detail="Page not found")
    return {"success": True, "page": serialize_doc(page)}


@router.put("/admin/{slug}")
async def admin_put_page(
    slug: str,
    body: PageContent,
    db=Depends(get_db),
    admin=Depends(get_current_admin),
):
    """Admin: create or update a page."""
    await _seed_pages(db)
    update = {"content": body.content, "updated_at": datetime.utcnow()}
    if body.title is not None:
        update["title"] = body.title
    res = await db.pages.update_one({"slug": slug}, {"$set": update}, upsert=True)
    page = await db.pages.find_one({"slug": slug})
    return {"success": True, "message": "Page saved", "page": serialize_doc(page)}
