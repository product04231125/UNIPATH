from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.academic import router as academic_router
from app.api.access import router as access_router
from app.api.assistant import router as assistant_router
from app.api.auth import router as auth_router
from app.api.health import health, router
from app.core.config import Settings, get_settings
from app.core.database import create_session_factory
from app.core.errors import register_error_handlers
from app.schemas.common import ErrorResponse
from app.schemas.health import HealthResponse
from app.services.assistant import create_school_rag_service


def create_app(settings: Settings | None = None) -> FastAPI:
    config = settings or get_settings()

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        application.state.settings = config
        application.state.school_rag_service = create_school_rag_service(config)
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
            401: {"model": ErrorResponse},
            403: {"model": ErrorResponse},
            409: {"model": ErrorResponse},
            429: {"model": ErrorResponse},
            404: {"model": ErrorResponse},
            422: {"model": ErrorResponse},
            500: {"model": ErrorResponse},
        },
    )
    register_error_handlers(application)
    application.add_middleware(
        CORSMiddleware,
        allow_origins=config.cors_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
        expose_headers=["X-Request-ID"],
    )
    application.include_router(router, prefix="/api/v1")
    application.include_router(assistant_router, prefix="/api/v1")
    application.include_router(auth_router, prefix="/api/v1")
    application.include_router(access_router, prefix="/api/v1")
    application.include_router(academic_router, prefix="/api/v1")
    # Compatibility alias for the README's infrastructure smoke check.
    application.add_api_route(
        "/health", health, response_model=HealthResponse, include_in_schema=False
    )
    return application


app = create_app()
