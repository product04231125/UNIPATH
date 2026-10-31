"""Assemble only selected records with a bounded, explicitly personal projection."""

from app.core.auth_errors import conflict
from app.schemas.personalization import PersonalEvidence, PersonalizationContext
from app.services import personal

FIELDS = {
    "course": ("term", "category", "credits", "course_code", "grade", "completion"),
    "activity": ("role", "reported_hours", "started_on", "ended_on"),
    "experience": ("experience_type", "role", "result", "started_on", "ended_on"),
    "credential": ("provider", "level", "earned_on", "expires_on", "status_label"),
    "achievement": ("achievement_type", "role", "result"),
}


def assemble(db, identity, selections):
    records = []
    for selection in selections:
        item = personal.get(
            db, identity.user.id, personal.RECORD_MODELS[selection.kind], selection.record_id
        )
        if item.version != selection.expected_version:
            raise conflict()
        # Exclude owner/contact information, links, observations of school approval,
        # and unselected records. These strings remain untrusted personal claims.
        fields = ("title", "detail", *FIELDS[selection.kind])
        text = "\n".join(
            f"{key}: {getattr(item, key)}"
            for key in fields
            if getattr(item, key) is not None and str(getattr(item, key))
        )
        records.append(
            PersonalEvidence(
                kind=selection.kind,
                record_id=item.id,
                version=item.version,
                title=item.title,
                text=text[:8000],
                truncated=len(text) > 8000,
            )
        )
    return PersonalizationContext(records=records)
