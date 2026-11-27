"""Upload helpers for host media (images / videos).

Files are streamed to disk in chunks so large videos don't have to fit in
memory, and every upload is validated by extension + size.
"""
import os
import uuid
from typing import Optional

import aiofiles
from fastapi import HTTPException, UploadFile

from app.core.config import settings

IMAGE_EXTS = {"jpg", "jpeg", "png", "webp", "gif"}
VIDEO_EXTS = {"mp4", "webm", "mov", "m4v"}

UPLOAD_DIR_PIC = "static/uploads/hosts/pics"
UPLOAD_DIR_VID = "static/uploads/hosts/videos"
os.makedirs(UPLOAD_DIR_PIC, exist_ok=True)
os.makedirs(UPLOAD_DIR_VID, exist_ok=True)

_CHUNK = 1024 * 1024  # 1 MB


def _has_file(f: Optional[UploadFile]) -> bool:
    return bool(f is not None and getattr(f, "filename", None))


async def save_upload(file: UploadFile, kind: str) -> str:
    """Save an uploaded image/video and return its public /static URL."""
    if kind == "image":
        allowed, folder, max_size = IMAGE_EXTS, UPLOAD_DIR_PIC, settings.MAX_FILE_SIZE
    elif kind == "video":
        allowed, folder, max_size = VIDEO_EXTS, UPLOAD_DIR_VID, settings.MAX_VIDEO_SIZE
    else:  # pragma: no cover - programming error
        raise ValueError(kind)

    ext = (file.filename or "").rsplit(".", 1)[-1].lower() if "." in (file.filename or "") else ""
    if ext not in allowed:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid {kind} format '{ext or '?'}'. Allowed: {', '.join(sorted(allowed))}",
        )

    filename = f"{uuid.uuid4()}.{ext}"
    path = os.path.join(folder, filename)
    written = 0
    try:
        async with aiofiles.open(path, "wb") as out:
            while True:
                chunk = await file.read(_CHUNK)
                if not chunk:
                    break
                written += len(chunk)
                if written > max_size:
                    raise HTTPException(
                        status_code=413,
                        detail=f"{kind.capitalize()} too large (max {max_size // (1024 * 1024)} MB)",
                    )
                await out.write(chunk)
    except HTTPException:
        try:
            os.remove(path)
        except OSError:
            pass
        raise

    sub = "pics" if kind == "image" else "videos"
    return f"/static/uploads/hosts/{sub}/{filename}"


async def save_many(files, kind: str) -> list:
    urls = []
    for f in files or []:
        if _has_file(f):
            urls.append(await save_upload(f, kind))
    return urls


def delete_media_file(url: Optional[str]) -> None:
    """Best-effort removal of a locally stored upload."""
    if not url or not url.startswith("/static/uploads/hosts/"):
        return
    path = url.lstrip("/")
    # safety: stay inside the uploads folder
    real = os.path.realpath(path)
    if not real.startswith(os.path.realpath("static/uploads/hosts")):
        return
    try:
        os.remove(real)
    except OSError:
        pass
