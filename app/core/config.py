from typing import Optional
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # NOTE: Secrets (MONGODB_URL, SECRET_KEY, admin creds) .env se hi aane chahiye.
    # Code me real credentials kabhi mat rakho — .env ko git me commit mat karo.
    MONGODB_URL: str = "mongodb://localhost:27017"
    DATABASE_NAME: str = "videocall_app"
    SECRET_KEY: str = ""  # required — .env me set karo (min 32 chars)
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 10080
    ADMIN_USERNAME: str = "admin"
    ADMIN_PASSWORD: str = ""  # required — .env me set karo
    UPLOAD_DIR: str = "static/uploads"
    MAX_FILE_SIZE: int = 10485760          # images (10 MB)
    MAX_VIDEO_SIZE: int = 104857600        # videos (100 MB)

    # Optional: force TLS on/off for MongoDB. None = auto
    # (mongodb+srv:// URLs use TLS automatically, plain mongodb:// follow URL options)
    MONGODB_TLS: Optional[bool] = None

    # ---- AI chat bot (any OpenAI-compatible Chat Completions API) ----
    # OpenAI:      AI_BASE_URL=https://api.openai.com/v1       AI_MODEL=gpt-4o-mini
    # Groq:        AI_BASE_URL=https://api.groq.com/openai/v1  AI_MODEL=llama-3.3-70b-versatile
    # OpenRouter:  AI_BASE_URL=https://openrouter.ai/api/v1    AI_MODEL=<any>
    # Gemini:      AI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai  AI_MODEL=gemini-2.0-flash
    # Khali AI_API_KEY = built-in rule-based Hindi/English/Hinglish fallback bot.
    AI_API_KEY: str = ""
    AI_BASE_URL: str = "https://api.openai.com/v1"
    AI_MODEL: str = "gpt-4o-mini"
    AI_TIMEOUT_SECONDS: float = 25.0
    AI_MAX_HISTORY: int = 16

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()

if not settings.SECRET_KEY:
    raise RuntimeError("SECRET_KEY is not set. Configure it in your .env file.")
if len(settings.SECRET_KEY) < 32:
    raise RuntimeError("SECRET_KEY is too short — use at least 32 characters.")
if not settings.ADMIN_PASSWORD:
    raise RuntimeError("ADMIN_PASSWORD is not set. Configure it in your .env file.")
