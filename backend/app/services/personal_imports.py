"""Append a reviewed local graph atomically; never upload or infer ownership."""

import hashlib
import json

from app.core.auth_errors import conflict, forbidden
from app.models.personal import PersonalCreationReceipt
from app.models.personal_imports import PersonalImportReceipt
from app.schemas import personal as personal_dto
from app.schemas import personal_imports as dto
from app.services import personal
from app.services.access import locked_identity


def fingerprint(payload):
    normalized = payload.model_dump(mode="json", by_alias=True)
    for name in dto.COLLECTIONS:
        normalized[name].sort(key=lambda item: item["client_id"])
    return hashlib.sha256(
        json.dumps(normalized, sort_keys=True, ensure_ascii=False).encode()
    ).hexdigest()


def view(receipt, *, replayed):
    return dto.PersonalImportView(
        import_id=receipt.import_id,
        owner_id=receipt.owner_id,
        committed_at=receipt.committed_at,
        record_count=receipt.record_count,
        profile_version_at_import=receipt.profile_version,
        mappings=receipt.mappings_json,
        replayed=replayed,
    )


def detail(db, owner_id, import_id):
    receipt = db.get(PersonalImportReceipt, (owner_id, import_id))
    if receipt is None:
        raise personal.missing()
    return view(receipt, replayed=True)


def translated(item, name, identities):
    """Convert explicitly named local references only after parent IDs exist."""
    data = item.model_dump(exclude_unset=True)

    def identifier(collection, local_id):
        return identities[collection, local_id]

    if name in ("personal_curriculum_courses", "personal_graduation_rules"):
        data["curriculum_id"] = identifier("personal_curricula", item.curriculum_id)
    if name == "personal_curriculum_courses" and item.course_record_id:
        data["course_record_id"] = identifier("course_records", item.course_record_id)
    if name == "personal_graduation_rules":
        if item.curriculum_course_id:
            data["curriculum_course_id"] = identifier(
                "personal_curriculum_courses", item.curriculum_course_id
            )
        if item.related_record:
            reference = item.related_record
            data["related_record"] = {
                "kind": reference.kind,
                "record_id": identifier(
                    dto.REFERENCE_RESOURCES[reference.kind], reference.record_id
                ),
            }
    if name in ("portfolio_compositions", "application_documents") and "sources" in data:
        data["sources"] = [
            {
                "kind": reference.kind,
                "record_id": identifier(
                    dto.REFERENCE_RESOURCES[reference.kind], reference.record_id
                ),
            }
            for reference in item.sources
        ]
    return data


def create(db, request, payload):
    identity = locked_identity(db, request)
    owner_id = identity.user.id
    if payload.source_owner_id != owner_id:
        raise forbidden()
    digest = fingerprint(payload)
    receipt = db.get(PersonalImportReceipt, (owner_id, payload.import_id))
    if receipt:
        if receipt.digest != digest:
            raise conflict()
        result = view(receipt, replayed=True)
        db.commit()
        return result
    identities, mappings, profile_version = {}, [], None
    try:
        if payload.profile is not None:
            # Initialization only: an existing server profile needs a separate
            # versioned PATCH reviewed by the user, never an import overwrite.
            profile = personal.save_profile_record(
                db,
                owner_id,
                personal_dto.ProfilePatch(expected_version=0, **payload.profile.model_dump()),
            )
            profile_version = profile["version"]
        for name in dto.COLLECTIONS:
            resource = name.replace("_", "-")
            _, prefix = personal.RESOURCES[resource]
            for item in sorted(getattr(payload, name), key=lambda entry: entry.client_id):
                data = translated(item, name, identities)
                schema = getattr(personal_dto, prefix + "Create")
                record = schema.model_validate(data)
                previous = db.get(PersonalCreationReceipt, (owner_id, resource, item.client_id))
                saved = personal.save_record(db, owner_id, resource, record)
                identities[name, item.client_id] = saved["id"]
                mappings.append(
                    dto.ImportMapping(
                        resource=resource,
                        client_id=item.client_id,
                        record_id=saved["id"],
                        version_at_import=saved["version"],
                        outcome="reused" if previous else "created",
                    )
                )
        receipt = PersonalImportReceipt(
            owner_id=owner_id,
            import_id=payload.import_id,
            digest=digest,
            record_count=len(mappings),
            profile_version=profile_version,
            mappings_json=[mapping.model_dump(mode="json") for mapping in mappings],
        )
        db.add(receipt)
        db.flush()
        result = view(receipt, replayed=False)
        personal.commit(db)
        return result
    except Exception:
        db.rollback()
        raise
