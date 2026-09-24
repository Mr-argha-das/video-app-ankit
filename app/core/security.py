from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from app.core.config import settings
from app.core.database import get_db

security = HTTPBearer()
admin_security = HTTPBearer()
any_auth_security = HTTPBearer()

BCRYPT_ROUNDS = 12

def _truncate_bcrypt_input(password: str) -> bytes:
    """bcrypt ki limit 72 *bytes* hai — characters nahi.
    Unicode passwords ko bhi sahi se handle karta hai (byte-level truncate).
    NOTE: passlib ke bajaye direct bcrypt use karte hain —
    passlib 1.7.4 bcrypt>=4.1 ke saath crash hota hai."""
    return password.encode("utf-8")[:72]

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(_truncate_bcrypt_input(plain_password), hashed_password.encode("utf-8"))
    except (ValueError, TypeError):
        return False

def get_password_hash(password: str) -> str:
    return bcrypt.hashpw(
        _truncate_bcrypt_input(password),
        bcrypt.gensalt(rounds=BCRYPT_ROUNDS)
    ).decode("utf-8")

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

def create_admin_token():
    return create_access_token({"sub": "admin", "role": "admin"})

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db=Depends(get_db)
):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        token = credentials.credentials
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None or payload.get("role") == "admin":
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    from bson import ObjectId
    user = await db.users.find_one({"_id": ObjectId(user_id)})
    if user is None:
        raise credentials_exception
    if user.get("is_blocked"):
        raise HTTPException(status_code=403, detail="Your account has been blocked")
    return user

async def get_current_admin(
    credentials: HTTPAuthorizationCredentials = Depends(admin_security)
):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Admin authentication required",
    )
    try:
        token = credentials.credentials
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        role = payload.get("role")
        if role != "admin":
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    return {"role": "admin"}

async def get_any_authenticated(
    credentials: HTTPAuthorizationCredentials = Depends(any_auth_security),
    db=Depends(get_db)
):
    """Accepts either a normal user token OR an admin token.
    Sensitive shared resources (jaise payment UPID) ke liye — logged-in koi bhi ho,
    lekin unauthenticated nahi."""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Authentication required",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        token = credentials.credentials
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("role") == "admin":
            return {"role": "admin"}
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    from bson import ObjectId
    try:
        user = await db.users.find_one({"_id": ObjectId(user_id)})
    except Exception:
        raise credentials_exception
    if user is None:
        raise credentials_exception
    if user.get("is_blocked"):
        raise HTTPException(status_code=403, detail="Your account has been blocked")
    return user

async def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(HTTPBearer(auto_error=False)),
    db=Depends(get_db)
):
    if not credentials:
        return None
    try:
        token = credentials.credentials
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id and payload.get("role") != "admin":
            from bson import ObjectId
            user = await db.users.find_one({"_id": ObjectId(user_id)})
            return user
    except Exception:
        pass
    return None