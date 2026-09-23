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
    MAX_FILE_SIZE: int = 10485760

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
