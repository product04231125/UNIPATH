from collections.abc import Iterator

from fastapi import Request
from sqlalchemy.orm import Session

from app.rag.school.service import SchoolRagService


def get_session(request: Request) -> Iterator[Session]:
    with request.app.state.session_factory() as session:
        yield session


def get_school_rag_service(request: Request) -> SchoolRagService:
    return request.app.state.school_rag_service
