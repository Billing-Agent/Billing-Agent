from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging

from app.core.config import settings
from app.api.v1 import health

logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting up Billing Agent API...")
    yield
    logger.info("Shutting down Billing Agent API...")

def get_application() -> FastAPI:
    application = FastAPI(
        title=settings.PROJECT_NAME,
        openapi_url=f"{settings.API_V1_STR}/openapi.json",
        lifespan=lifespan,
    )

    # Set all CORS enabled origins
    if settings.BACKEND_CORS_ORIGINS:
        application.add_middleware(
            CORSMiddleware,
            allow_origins=[str(origin) for origin in settings.BACKEND_CORS_ORIGINS],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    from fastapi.responses import JSONResponse
    from fastapi import Request
    from app.core.exceptions import EntityNotFoundError, BusinessLogicError, ConcurrencyConflictError

    @application.exception_handler(EntityNotFoundError)
    async def not_found_exception_handler(request: Request, exc: EntityNotFoundError):
        return JSONResponse(status_code=404, content={"detail": str(exc)})

    @application.exception_handler(BusinessLogicError)
    async def business_logic_exception_handler(request: Request, exc: BusinessLogicError):
        return JSONResponse(status_code=400, content={"detail": str(exc)})

    @application.exception_handler(ConcurrencyConflictError)
    async def concurrency_conflict_exception_handler(request: Request, exc: ConcurrencyConflictError):
        return JSONResponse(status_code=409, content={"detail": str(exc)})

    from app.api.v1.endpoints import bills, payments, dev, users, auth, me, payhere, agent
    application.include_router(health.router, prefix=settings.API_V1_STR, tags=["health"])
    application.include_router(bills.router, prefix=f"{settings.API_V1_STR}/bills", tags=["bills"])
    application.include_router(payments.router, prefix=f"{settings.API_V1_STR}/payments", tags=["payments"])
    application.include_router(dev.router, prefix=f"{settings.API_V1_STR}/dev", tags=["development"])
    application.include_router(users.router, prefix=f"{settings.API_V1_STR}/users", tags=["users"])
    application.include_router(auth.router, prefix=f"{settings.API_V1_STR}/auth", tags=["auth"])
    application.include_router(me.router, prefix=f"{settings.API_V1_STR}/me", tags=["me"])
    application.include_router(payhere.router, prefix=f"{settings.API_V1_STR}/payhere", tags=["payhere"])
    application.include_router(agent.router, prefix=f"{settings.API_V1_STR}/agent", tags=["agent"])

    return application

app = get_application()
