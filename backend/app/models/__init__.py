from app.models.academic import (
    Course,
    Curriculum,
    CurriculumCourse,
    Department,
    GraduationRule,
    OfficialDocument,
    RuleSet,
)
from app.models.base import Base
from app.models.identity import (
    AdminScope,
    AuthSession,
    AuthThrottle,
    IdentityAudit,
    Institution,
    User,
)

__all__ = [
    "Base",
    "User",
    "AuthSession",
    "AuthThrottle",
    "Institution",
    "AdminScope",
    "IdentityAudit",
    "Department",
    "Curriculum",
    "Course",
    "CurriculumCourse",
    "RuleSet",
    "GraduationRule",
    "OfficialDocument",
]
