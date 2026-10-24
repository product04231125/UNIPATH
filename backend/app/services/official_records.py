"""Normalize verified originals without promoting personal inputs or inferring grades."""

import hashlib
import json
from contextlib import contextmanager
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID, uuid4, uuid5

from pydantic import TypeAdapter, ValidationError
from sqlalchemy import delete, exists, func, select
from sqlalchemy.exc import IntegrityError

from app.core.auth_errors import AuthError, conflict, forbidden
from app.models.academic import Course
from app.models.certificates import Certificate, CertificateProvider
from app.models.identity import AdminScope, Institution, Role
from app.models.official_records import OfficialRecordBatch as Batch
from app.models.official_records import OfficialRecordBatchEvent as Event
from app.models.official_records import OfficialRecordCertificateRef as CertificateRef
from app.models.official_records import OfficialRecordCourseRef as CourseRef
from app.models.record_sources import OfficialRecordSource as Source
from app.rules import contracts as core
from app.schemas import official_records as dto
from app.schemas.common import ErrorCode
from app.services import access, catalog, certificates
from app.services import record_sources as originals

payload_adapter = TypeAdapter(dto.Payload)
MAX_BATCH_BYTES = 256 * 1024
MAX_OWNER_BATCHES = 200
CONTEXT_FIELDS = ("institution_id", "department_id", "curriculum_id", "admission_year", "track")


def invalid(message="원본·기록·적용 문맥과 검토 내용을 확인해 주세요."):
    return AuthError(422, ErrorCode.VALIDATION_ERROR, message)


def missing():
    return AuthError(404, ErrorCode.NOT_FOUND, "요청한 학교 기록을 찾을 수 없습니다.")


def corrupt():
    return AuthError(503, ErrorCode.SERVICE_UNAVAILABLE, "학교 기록의 무결성을 확인할 수 없습니다.")


@contextmanager
def writes(db):
    try:
        yield
    except IntegrityError:
        db.rollback()
        raise conflict() from None


def wire(value):
    if hasattr(value, "model_dump"):
        return wire(value.model_dump(mode="python"))
    if isinstance(value, Decimal):
        if value.is_zero():
            return "0"
        text = format(value, "f")
        return text.rstrip("0").rstrip(".") if "." in text else text
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: wire(item) for key, item in value.items()}
    if isinstance(value, (tuple, list)):
        return [wire(item) for item in value]
    return value


def encoded(value):
    return json.dumps(
        wire(value), sort_keys=True, ensure_ascii=False, separators=(",", ":")
    ).encode()


def digest(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def read(db, identity, batch_id, *, admin):
    if admin and identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
        raise forbidden()
    batch = db.get(Batch, batch_id)
    if batch is None:
        raise missing()
    if admin:
        originals.admin_read(db, identity, batch.source_id)
    elif batch.owner_id != identity.user.id or batch.approved_at is None:
        raise missing()
    return batch


def context(batch):
    return dto.ReviewedContext(**{key: getattr(batch, key) for key in CONTEXT_FIELDS[1:]})


def reference_rows(db, batch):
    courses = list(
        db.scalars(
            select(CourseRef).where(CourseRef.batch_id == batch.id).order_by(CourseRef.course_id)
        )
    )
    credentials = list(
        db.scalars(
            select(CertificateRef)
            .where(CertificateRef.batch_id == batch.id)
            .order_by(CertificateRef.certificate_id)
        )
    )
    return courses, credentials


def load_data(batch):
    try:
        data = payload_adapter.validate_python(batch.data_json)
        if digest(data) != batch.data_digest or any(
            [
                data.kind != batch.kind,
                data.coverage != batch.coverage,
                data.page_count != batch.page_count,
                data.records_as_of != batch.records_as_of,
                len(data.records) != batch.record_count,
                data.context != context(batch),
            ]
        ):
            raise corrupt()
        return data
    except (ValidationError, ValueError, TypeError):
        raise corrupt() from None


def source_intact(db, source):
    data = source.file_data
    correct = hashlib.sha256(data).hexdigest() == source.sha256
    db.expire(source, ["file_data"])
    return correct


def current_references(db, rows):
    courses, credentials = rows
    for reference in courses:
        item = db.get(Course, reference.course_id)
        if item is None or any(
            [
                item.institution_id != reference.institution_id,
                item.version != reference.catalog_version,
                item.code != reference.code,
                item.name != reference.name,
            ]
        ):
            return False
    for reference in credentials:
        item = db.get(Certificate, reference.certificate_id)
        provider = db.get(CertificateProvider, reference.provider_id)
        if (
            item is None
            or provider is None
            or any(
                [
                    item.status != "active",
                    provider.status != "active",
                    item.version != reference.catalog_version,
                    item.provider_id != reference.provider_id,
                    provider.version != reference.provider_version,
                    item.code != reference.code,
                    item.name != reference.name,
                    provider.name != reference.provider_name,
                ]
            )
        ):
            return False
    return True


def readiness(db, batch, *, cache=None, as_of=None):
    cache = cache if cache is not None else {}
    data = load_data(batch)
    rows = reference_rows(db, batch)
    expected_courses = (
        {r.course_id: r.expected_course_version for r in data.records}
        if data.kind == "academics"
        else {}
    )
    expected_certificates = (
        {r.certificate_id: r.expected_certificate_version for r in data.records}
        if data.kind == "certificates"
        else {}
    )
    if {r.course_id: r.catalog_version for r in rows[0]} != expected_courses or {
        r.certificate_id: r.catalog_version for r in rows[1]
    } != expected_certificates:
        raise corrupt()
    source = db.get(Source, batch.source_id)
    school = db.get(Institution, batch.institution_id)
    issues = []
    if batch.status != "approved":
        issues.append("not_approved")
    if (
        source is None
        or source.status != "verified"
        or school is None
        or school.deleted_at is not None
    ):
        issues.append("source_unavailable")
    elif source.version != batch.source_version or source.sha256 != batch.source_sha256:
        issues.append("source_changed")
    else:
        if source.id not in cache:
            cache[source.id] = source_intact(db, source)
        if not cache[source.id]:
            issues.append("source_changed")
    if not current_references(db, rows):
        issues.append("reference_changed")
    if batch.department_id is None or batch.admission_year is None or batch.track is None:
        issues.append("context_incomplete")
    if batch.coverage != "complete":
        issues.append("partial_records")
    if as_of is not None and batch.records_as_of != as_of:
        issues.append("snapshot_date_mismatch")
    return data, rows, issues


def view(db, batch, *, detail=False, cache=None):
    data, rows, issues = readiness(db, batch, cache=cache)
    result = {
        key: getattr(batch, key)
        for key in (
            "id",
            "owner_id",
            "source_id",
            "source_version",
            "source_sha256",
            "institution_id",
            "client_id",
            "kind",
            "status",
            "version",
            "coverage",
            "page_count",
            "records_as_of",
            "record_count",
            "created_at",
            "updated_at",
        )
    }
    result.update(
        context=context(batch),
        usable_for_audit=not issues,
        issues=issues,
        graduation_eligible=False,
    )
    if detail:
        references = [
            {
                "kind": "course",
                "id": r.course_id,
                "version": r.catalog_version,
                "code": r.code,
                "name": r.name,
            }
            for r in rows[0]
        ]
        references.extend(
            {
                "kind": "certificate",
                "id": r.certificate_id,
                "version": r.catalog_version,
                "code": r.code,
                "name": r.name,
                "provider_id": r.provider_id,
                "provider_version": r.provider_version,
                "provider_name": r.provider_name,
            }
            for r in rows[1]
        )
        result.update(data=data, references=references)
    return result


def listing(
    db,
    identity,
    *,
    admin,
    source_id=None,
    institution_id=None,
    kind=None,
    status=None,
    cursor=None,
    limit=20,
):
    statement = select(Batch)
    if admin:
        if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
            raise forbidden()
        statement = (
            statement.join(Source, Source.id == Batch.source_id)
            .join(Institution, Institution.id == Batch.institution_id)
            .where(Source.status != "withdrawn", Institution.deleted_at.is_(None))
        )
        if identity.user.role == Role.SCHOOL_ADMIN:
            statement = statement.where(
                exists().where(
                    AdminScope.user_id == identity.user.id,
                    AdminScope.institution_id == Batch.institution_id,
                    AdminScope.status == "active",
                )
            )
    else:
        statement = statement.where(
            Batch.owner_id == identity.user.id, Batch.approved_at.is_not(None)
        )
    for key, value in [
        ("source_id", source_id),
        ("institution_id", institution_id),
        ("kind", kind),
        ("status", status),
    ]:
        if value is not None:
            statement = statement.where(getattr(Batch, key) == value)
    if cursor:
        statement = statement.where(Batch.id > cursor)
    rows = list(db.scalars(statement.order_by(Batch.id).limit(limit + 1)))
    cache = {}
    return {
        "items": [view(db, row, cache=cache) for row in rows[:limit]],
        "next_cursor": rows[limit - 1].id if len(rows) > limit else None,
    }


def normalized(db, source, data):
    if source.status != "verified":
        raise conflict()
    _, department_id, curriculum_id = catalog.context(
        db, source.institution_id, data.context.department_id, data.context.curriculum_id
    )
    if data.records_as_of > source.issued_on:
        raise invalid("기록 기준일은 확인한 원본의 발급일을 넘을 수 없습니다.")
    checked_context = data.context.model_copy(
        update={"department_id": department_id, "curriculum_id": curriculum_id}
    )
    data = data.model_copy(update={"context": checked_context})
    if len(encoded(data)) > MAX_BATCH_BYTES:
        raise AuthError(413, ErrorCode.HTTP_ERROR, "정규화 기록은 최대 256 KiB입니다.")
    references = []
    expected = {}
    if data.kind == "academics":
        for record in data.records:
            if (
                record.course_id in expected
                and expected[record.course_id] != record.expected_course_version
            ):
                raise invalid()
            expected[record.course_id] = record.expected_course_version
        for identifier, version in sorted(expected.items()):
            item = db.get(Course, identifier)
            if item is None or item.institution_id != source.institution_id:
                raise invalid()
            if item.version != version:
                raise conflict()
            references.append(
                (
                    CourseRef,
                    {
                        "course_id": item.id,
                        "catalog_version": item.version,
                        "code": item.code,
                        "name": item.name,
                    },
                )
            )
    elif data.kind == "certificates":
        for record in data.records:
            if (
                record.certificate_id in expected
                and expected[record.certificate_id] != record.expected_certificate_version
            ):
                raise invalid()
            expected[record.certificate_id] = record.expected_certificate_version
        for identifier, version in sorted(expected.items()):
            item = certificates.active_certificate(db, identifier)
            provider = db.get(CertificateProvider, item.provider_id)
            if item.version != version:
                raise conflict()
            references.append(
                (
                    CertificateRef,
                    {
                        "certificate_id": item.id,
                        "catalog_version": item.version,
                        "code": item.code,
                        "name": item.name,
                        "provider_id": provider.id,
                        "provider_version": provider.version,
                        "provider_name": provider.name,
                    },
                )
            )
    return data, references


def set_data(db, batch, data, references):
    batch.kind, batch.coverage = data.kind, data.coverage
    batch.page_count, batch.records_as_of = data.page_count, data.records_as_of
    batch.record_count = len(data.records)
    for key in CONTEXT_FIELDS[1:]:
        setattr(batch, key, getattr(data.context, key))
    batch.data_json = wire(data)
    batch.data_digest = digest(data)
    db.add(batch)
    db.flush()
    for model in (CourseRef, CertificateRef):
        db.execute(delete(model).where(model.batch_id == batch.id))
    for model, fields in references:
        db.add(model(batch_id=batch.id, institution_id=batch.institution_id, **fields))


def event(db, request, identity, batch, action, reason=""):
    db.add(
        Event(
            batch_id=batch.id,
            actor_id=identity.user.id,
            version=batch.version,
            action=action,
            reason=reason,
        )
    )
    access.audit(
        db,
        identity.user.id,
        "school_records_" + action,
        batch.id,
        request_id=request.state.request_id,
        institution_id=batch.institution_id,
    )


def create(db, request, payload):
    with writes(db):
        identity = access.locked_identity(db, request)
        source = originals.admin_read(db, identity, payload.source_id)
        if source.status != "verified" or source.version != payload.expected_source_version:
            raise conflict()
        creation = digest(payload)
        existing = db.scalar(
            select(Batch).where(
                Batch.owner_id == source.owner_id, Batch.client_id == payload.client_id
            )
        )
        if existing is not None:
            if existing.creation_digest != creation:
                raise conflict()
            return view(db, existing, detail=True)
        if (
            db.scalar(
                select(func.count()).select_from(Batch).where(Batch.owner_id == source.owner_id)
            )
            >= MAX_OWNER_BATCHES
        ):
            raise conflict()
        data, references = normalized(db, source, payload.data)
        batch = Batch(
            id=uuid4(),
            source_id=source.id,
            owner_id=source.owner_id,
            institution_id=source.institution_id,
            source_version=source.version,
            source_sha256=source.sha256,
            client_id=payload.client_id,
            creation_digest=creation,
            created_by=identity.user.id,
            status="draft",
            version=1,
        )
        set_data(db, batch, data, references)
        event(db, request, identity, batch, "created")
        db.commit()
        db.refresh(batch)
        return view(db, batch, detail=True)


def draft(db, request, batch_id, expected_version):
    identity = access.locked_identity(db, request)
    batch = read(db, identity, batch_id, admin=True)
    source = originals.admin_read(db, identity, batch.source_id)
    if batch.version != expected_version or batch.status != "draft":
        raise conflict()
    if (
        source.status != "verified"
        or source.version != batch.source_version
        or source.sha256 != batch.source_sha256
    ):
        raise conflict()
    return identity, batch, source


def replace(db, request, batch_id, payload):
    with writes(db):
        identity, batch, source = draft(db, request, batch_id, payload.expected_version)
        if payload.data.kind != batch.kind:
            raise invalid()
        data, references = normalized(db, source, payload.data)
        batch.version += 1
        batch.updated_at = datetime.now(UTC)
        set_data(db, batch, data, references)
        event(db, request, identity, batch, "replaced")
        db.commit()
        db.refresh(batch)
        return view(db, batch, detail=True)


def approve(db, request, batch_id, payload):
    with writes(db):
        identity, batch, source = draft(db, request, batch_id, payload.expected_version)
        if batch.owner_id == identity.user.id:
            raise forbidden()
        if source.sha256 != payload.expected_source_sha256:
            raise conflict()
        _, _, issues = readiness(db, batch)
        if any(issue not in ("not_approved", "partial_records") for issue in issues):
            raise conflict()
        previous = db.scalar(
            select(Batch).where(
                Batch.status == "approved",
                Batch.owner_id == batch.owner_id,
                Batch.kind == batch.kind,
                *(getattr(Batch, key) == getattr(batch, key) for key in CONTEXT_FIELDS),
            )
        )
        if previous is None:
            if payload.replaces_batch_id is not None:
                raise conflict()
        else:
            if (
                previous.id != payload.replaces_batch_id
                or previous.version != payload.expected_replaced_version
            ):
                raise conflict()
            previous.status = "superseded"
            previous.version += 1
            previous.updated_at = datetime.now(UTC)
            event(db, request, identity, previous, "superseded")
            db.flush()
        batch.status = "approved"
        batch.version += 1
        batch.updated_at = datetime.now(UTC)
        batch.approved_at = datetime.now(UTC)
        batch.approved_by = identity.user.id
        event(db, request, identity, batch, "approved")
        db.commit()
        db.refresh(batch)
        return view(db, batch, detail=True)


def end(db, request, batch_id, payload, *, discard=False):
    with writes(db):
        identity = access.locked_identity(db, request)
        batch = read(db, identity, batch_id, admin=True)
        if batch.version != payload.expected_version or batch.status != (
            "draft" if discard else "approved"
        ):
            raise conflict()
        batch.status = "discarded" if discard else "revoked"
        batch.version += 1
        batch.updated_at = datetime.now(UTC)
        event(db, request, identity, batch, batch.status, payload.reason)
        db.commit()
        db.refresh(batch)
        return view(db, batch, detail=True)


def invalidate_source(db, request, identity, source, action):
    # The caller holds the same identity lock and commits source + batches together.
    for batch in db.scalars(
        select(Batch).where(Batch.source_id == source.id, Batch.status.in_(["draft", "approved"]))
    ):
        batch.status = "revoked" if batch.status == "approved" else "discarded"
        batch.version += 1
        batch.updated_at = datetime.now(UTC)
        event(db, request, identity, batch, "source_" + action)


def events(db, batch):
    return {
        "items": list(
            db.scalars(select(Event).where(Event.batch_id == batch.id).order_by(Event.version))
        )
    }


def owned_snapshot(db, identity, academic_context, records_as_of, *, kinds=None):
    """Internal input for a future audit; no personal-profile fallback or verdict."""
    values = {kind: None for kind in ("academics", "volunteers", "certificates", "theses")}
    kinds = set(values) if kinds is None else set(kinds)
    if not kinds <= values.keys():
        raise ValueError("Unknown school record kind")
    batches, issues = [], []
    if any(
        getattr(academic_context, key) is None
        for key in ("institution_id", "department_id", "admission_year", "track")
    ):
        return core.Snapshot(), (), ((None, "context_incomplete"),)
    selected = list(
        db.scalars(
            select(Batch)
            .where(
                Batch.owner_id == identity.user.id,
                Batch.status == "approved",
                Batch.kind.in_(kinds),
                *(getattr(Batch, key) == getattr(academic_context, key) for key in CONTEXT_FIELDS),
            )
            .order_by(Batch.kind)
        )
    )
    by_kind = {batch.kind: batch for batch in selected}
    if len(by_kind) != len(selected):
        return core.Snapshot(), (), ((None, "ambiguous_records"),)
    cache = {}
    for kind in values:
        if kind not in kinds:
            continue
        batch = by_kind.get(kind)
        if batch is None:
            issues.append((kind, "records_unavailable"))
            continue
        data, _, problems = readiness(db, batch, cache=cache, as_of=records_as_of)
        if problems:
            issues.extend((kind, problem) for problem in problems)
            continue
        records = []
        for item in data.records:
            body = item.model_dump(
                mode="python",
                exclude={
                    "client_id",
                    "source_page",
                    "expected_course_version",
                    "expected_certificate_version",
                    "original_grade",
                },
            )
            body["id"] = uuid5(batch.id, str(item.client_id))
            model = {
                "academics": core.AcademicRecord,
                "volunteers": core.VolunteerRecord,
                "certificates": core.CertificateRecord,
                "theses": core.ThesisRecord,
            }[kind]
            records.append(model.model_validate(body))
        values[kind] = tuple(records)
        batches.append(batch.id)
    return core.Snapshot(**values), tuple(batches), tuple(issues)
