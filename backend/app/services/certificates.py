"""Global identities managed by root; reference protection never exposes student data."""

from datetime import UTC, datetime

from sqlalchemy import exists, select
from sqlalchemy.exc import IntegrityError

from app.core.auth_errors import AuthError, conflict, forbidden
from app.models.certificates import Certificate, CertificateProvider
from app.models.identity import AdminScope, Role
from app.models.official_records import OfficialRecordCertificateRef
from app.models.rule_programs import ProgramCertificateRef, ProgramRule, RuleProgram
from app.schemas.common import ErrorCode
from app.services import access


def missing():
    return AuthError(404, ErrorCode.NOT_FOUND, "요청한 자격증 마스터를 찾을 수 없습니다.")


def administrator(identity):
    if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
        raise forbidden()


def listing(
    db,
    model,
    *,
    identity=None,
    public=False,
    provider_id=None,
    status=None,
    query="",
    cursor=None,
    limit=100,
):
    if not public:
        administrator(identity)
    statement = select(model)
    if public:
        statement = statement.where(model.status == "active")
        if model is Certificate:
            statement = statement.where(
                exists().where(
                    CertificateProvider.id == Certificate.provider_id,
                    CertificateProvider.status == "active",
                )
            )
    elif status:
        statement = statement.where(model.status == status)
    if provider_id is not None and model is Certificate:
        statement = statement.where(Certificate.provider_id == provider_id)
    if query:
        statement = statement.where(model.name.icontains(query, autoescape=True))
    if cursor:
        statement = statement.where(model.id > cursor)
    return list(db.scalars(statement.order_by(model.id).limit(limit + 1)))


def get(db, model, identifier, *, identity=None, public=False):
    if not public:
        administrator(identity)
    item = db.get(model, identifier)
    if item is None or public and item.status != "active":
        raise missing()
    if public and model is Certificate:
        provider = db.get(CertificateProvider, item.provider_id)
        if provider is None or provider.status != "active":
            raise missing()
    return item


def active_certificate(db, identifier):
    return get(db, Certificate, identifier, public=True)


def audit(db, identity, action, item, request):
    kind = "certificate_provider" if isinstance(item, CertificateProvider) else "certificate"
    access.audit(db, identity.user.id, kind + ":" + action, item.id, request.state.request_id)


def commit(db):
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise conflict() from None


def mutate(db, request):
    identity = access.locked_identity(db, request)
    access.require_super(db, identity)
    return identity


def create(db, request, model, payload):
    identity = mutate(db, request)
    values = payload.model_dump()
    if model is Certificate:
        provider = get(db, CertificateProvider, payload.provider_id, identity=identity)
        if provider.status != "active":
            raise conflict()
    item = model(**values, created_by=identity.user.id, updated_by=identity.user.id)
    db.add(item)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise conflict() from None
    audit(db, identity, "create", item, request)
    commit(db)
    return item


def update(db, request, model, identifier, payload):
    identity = mutate(db, request)
    item = get(db, model, identifier, identity=identity)
    if item.version != payload.expected_version:
        raise conflict()
    item.name, item.official_url = payload.name, payload.official_url
    item.version += 1
    item.updated_by, item.updated_at = identity.user.id, datetime.now(UTC)
    audit(db, identity, "update", item, request)
    commit(db)
    return item


def reference_statement(model, identifier):
    certificate_ids = (
        select(Certificate.id).where(Certificate.provider_id == identifier)
        if model is CertificateProvider
        else [identifier]
    )
    return (
        select(RuleProgram)
        .join(ProgramRule, ProgramRule.program_id == RuleProgram.id)
        .join(ProgramCertificateRef, ProgramCertificateRef.program_rule_id == ProgramRule.id)
        .where(
            ProgramCertificateRef.certificate_id.in_(certificate_ids),
            RuleProgram.status == "approved",
        )
        .distinct()
    )


def references(db, identity, model, identifier):
    get(db, model, identifier, identity=identity)
    statement = reference_statement(model, identifier)
    result = []
    key = "provider_id" if model is CertificateProvider else "certificate_id"
    if db.scalar(select(exists().where(getattr(OfficialRecordCertificateRef, key) == identifier))):
        result.append({"id": identifier, "kind": "protected_reference", "name": "보호된 연결 참조"})
    for program in db.scalars(statement.order_by(RuleProgram.id)):
        if identity.user.role == Role.SUPER_ADMIN or db.scalar(
            select(
                exists().where(
                    AdminScope.user_id == identity.user.id,
                    AdminScope.institution_id == program.institution_id,
                    AdminScope.status == "active",
                )
            )
        ):
            result.append({"id": program.id, "kind": "rule_program", "name": program.name})
        elif not any(row["kind"] == "protected_reference" for row in result):
            result.append(
                {"id": identifier, "kind": "protected_reference", "name": "보호된 연결 참조"}
            )
    return result


def status(db, request, model, identifier, payload, *, active):
    identity = mutate(db, request)
    item = get(db, model, identifier, identity=identity)
    if item.version != payload.expected_version:
        raise conflict()
    target = "active" if active else "inactive"
    if item.status == target:
        raise conflict()
    if active and model is Certificate:
        provider = get(db, CertificateProvider, item.provider_id, identity=identity)
        if provider.status != "active":
            raise conflict()
    if not active and db.scalar(
        reference_statement(model, identifier).with_only_columns(RuleProgram.id).limit(1)
    ):
        raise AuthError(409, ErrorCode.CONFLICT, "승인된 실행 규칙의 참조를 먼저 확인해 주세요.")
    item.status = target
    item.version += 1
    item.updated_by, item.updated_at = identity.user.id, datetime.now(UTC)
    audit(db, identity, "activate" if active else "deactivate", item, request)
    commit(db)
    return item
