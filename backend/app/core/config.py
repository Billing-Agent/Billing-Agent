import logging
from typing import Literal

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url
from sqlalchemy.exc import ArgumentError

class Settings(BaseSettings):
    PROJECT_NAME: str = "Billing Agent API"
    API_V1_STR: str = "/api/v1"
    APP_ENVIRONMENT: Literal["production", "development", "test"] = "production"
    ENABLE_DEV_PAYMENT_SIMULATOR: bool = False
    DEV_PAYMENT_SIMULATOR_TOKEN: SecretStr | None = None
    
    # CORS
    BACKEND_CORS_ORIGINS: list[str] = ["http://localhost", "http://localhost:8080", "http://localhost:3000"]
    
    # Future Config (not used yet)
    DATABASE_URL: str | None = None
    GEMINI_API_KEY: str | None = None
    GEMINI_MODEL: str = "gemini-2.5-flash"
    PAYHERE_MERCHANT_ID: str | None = None
    PAYHERE_SECRET: str | None = None
    PAYHERE_API_KEY: str | None = None
    # PayHere Merchant Retrieval API (OAuth & Payment Search)
    PAYHERE_API_APP_ID: str | None = None
    PAYHERE_API_APP_SECRET: str | None = None
    PAYHERE_MERCHANT_API_BASE_URL: str = "https://sandbox.payhere.lk/merchant/v1"
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
    # Payment Confirmation (Phase 8C)
    PAYMENT_CONFIRMATION_TTL_SECONDS: int = 300

    model_config = SettingsConfigDict(env_file=(".env", "../.env"), env_ignore_empty=True, extra="ignore")

    @property
    def dev_payment_simulator_enabled(self) -> bool:
        if not self.ENABLE_DEV_PAYMENT_SIMULATOR or self.APP_ENVIRONMENT == "production":
            return False
        if not self.DEV_PAYMENT_SIMULATOR_TOKEN or len(self.DEV_PAYMENT_SIMULATOR_TOKEN.get_secret_value()) < 32:
            return False
        if not self.DATABASE_URL:
            return False
        try:
            url = make_url(self.DATABASE_URL)
        except (ArgumentError, ValueError):
            return False
        database = url.database or ""
        return url.drivername == "postgresql+asyncpg" and (
            database == "billing_agent_test" or database.startswith("billing_agent_test_")
        )

settings = Settings()

# Basic logging configuration
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
