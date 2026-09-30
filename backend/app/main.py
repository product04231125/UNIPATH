from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.health import health, router
from app.core.config import Settings, get_settings
from app.core.database import create_session_factory
from app.core.errors import register_error_handlers
from app.schemas.common import ErrorResponse
from app.schemas.health import HealthResponse


def create_app(settings: Settings | None = None) -> FastAPI:
    config = settings or get_settings()

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        application.state.session_factory = create_session_factory(config)
        try:
            yield
        finally:
            application.state.session_factory.kw["bind"].dispose()

    application = FastAPI(
        title="UniversityPath AI API",
        version="0.1.0",
        lifespan=lifespan,
        openapi_url="/api/v1/openapi.json",
        docs_url="/api/v1/docs",
        redoc_url="/api/v1/redoc",
        responses={
            404: {"model": ErrorResponse},
            422: {"model": ErrorResponse},
            500: {"model": ErrorResponse},
        },
    )
    register_error_handlers(application)
    application.add_middleware(
        CORSMiddleware,
        allow_origins=config.cors_origins,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
        expose_headers=["X-Request-ID"],
    )
    application.include_router(router, prefix="/api/v1")
    # Compatibility alias for the README's infrastructure smoke check.
    application.add_api_route(
        "/health", health, response_model=HealthResponse, include_in_schema=False
    )
    return application


app = create_app()
