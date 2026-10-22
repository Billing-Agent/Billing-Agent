import logging
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    PROJECT_NAME: str = "Billing Agent API"
    API_V1_STR: str = "/api/v1"
    
    # CORS
    BACKEND_CORS_ORIGINS: list[str] = ["http://localhost", "http://localhost:8080", "http://localhost:3000"]
    
    # Future Config (not used yet)
    DATABASE_URL: str | None = None
    GEMINI_API_KEY: str | None = None
    PAYHERE_MERCHANT_ID: str | None = None
    PAYHERE_SECRET: str | None = None
    PAYHERE_API_KEY: str | None = None
    # PayHere URLs (environment-specific)
    PAYHERE_BASE_URL: str = "https://sandbox.payhere.lk/pay/checkout"
    PAYHERE_NOTIFY_URL: str | None = None   # e.g. https://<ngrok>/api/v1/payhere/callback
    PAYHERE_RETURN_URL: str | None = None   # deep-link or URL PayHere redirects user to
    PAYHERE_CANCEL_URL: str | None = None   # deep-link or URL PayHere redirects on cancel
    # PayHere payer address defaults (used when user has no address on record)
    PAYHERE_DEFAULT_ADDRESS: str = "No. 1 Main Street"
    PAYHERE_DEFAULT_CITY: str = "Colombo"
    PAYHERE_DEFAULT_COUNTRY: str = "Sri Lanka"
    # Authentication & Security
    JWT_SECRET: str | None = None
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60

    model_config = SettingsConfigDict(env_file=(".env", "../.env"), env_ignore_empty=True, extra="ignore")

settings = Settings()

# Basic logging configuration
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
