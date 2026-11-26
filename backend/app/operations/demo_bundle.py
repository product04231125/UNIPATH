"""Read-only demo export and atomic import into an empty, isolated demo database.

No authentication rows, passwords, sessions, receipts or private files are exported.
"""

import argparse
import json
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from uuid import NAMESPACE_URL, UUID, uuid5

from sqlalchemy import Date, DateTime, Numeric, Uuid, create_engine, func, select, text
from sqlalchemy.orm import Session

import app.models  # noqa: F401 -- register every dependency in the metadata
from app.core.config import Settings
from app.models.base import Base
from app.models.identity import User
from app.services.auth import PASSWORDS

STUDENT = uuid5(NAMESPACE_URL, "unipath:windows-demo:student")
ADMIN = uuid5(NAMESPACE_URL, "unipath:windows-demo:administrator")
CATALOG = {
    "institutions",
    "departments",
    "curricula",
    "courses",
    "curriculum_courses",
    "rule_sets",
    "graduation_rules",
    "official_documents",
    # School classifications and the guidance bundle link, so the demo school reads as staged.
    "academic_guidance_bindings",
    "academic_classification_revisions",
    "academic_classification_nodes",
    "academic_study_tracks",
    "academic_curriculum_revisions",
    "academic_curriculum_courses",
    "academic_curriculum_department_refs",
    "academic_curriculum_track_refs",
    "academic_requirement_revisions",
    "academic_requirement_department_refs",
    "academic_requirement_node_refs",
    "academic_requirement_track_refs",
    "academic_credit_record_bindings",
}
PERSONAL = {
    "planning_profiles",
    "personal_course_records",
    "student_academic_workspaces",
    "student_academic_contexts",
    "student_academic_activations",
    "student_academic_documents",
    "student_academic_responses",
    "student_academic_course_links",
}
ALLOWED = CATALOG | PERSONAL


def encode(value):
    if isinstance(value, (UUID, Decimal, date, datetime)):
        return str(value)
    raise TypeError(type(value).__name__)


def rewrite(value, identities):
    if isinstance(value, dict):
        return {k: rewrite(v, identities) for k, v in value.items()}
    if isinstance(value, list):
        return [rewrite(v, identities) for v in value]
    return identities.get(value, value) if isinstance(value, str) else value


def export_data(db, owner):
    """Caller owns a REPEATABLE READ, READ ONLY transaction."""
    profile = Base.metadata.tables["planning_profiles"]
    school = db.scalar(select(profile.c.institution_id).where(profile.c.owner_id == owner))
    if school is None:
        raise ValueError("The selected student has no registered institution")
    identities = {str(key): str(ADMIN) for key in db.scalars(select(User.id))}
    identities[str(owner)] = str(STUDENT)
    activations = Base.metadata.tables["student_academic_activations"]
    activation_ids = list(
        db.scalars(select(activations.c.id).where(activations.c.owner_id == owner))
    )
    data = {}
    for table in Base.metadata.sorted_tables:
        if table.name not in ALLOWED:
            continue
        if table.name == "institutions":
            predicate = table.c.id == school
        elif table.name == "student_academic_documents":
            predicate = table.c.activation_id.in_(activation_ids)
        elif table.name in PERSONAL:
            predicate = table.c.owner_id == owner
        else:
            predicate = table.c.institution_id == school
        rows = [dict(row) for row in db.execute(select(table).where(predicate)).mappings()]
        # Old requirement record references are no longer used by the student UI.
        if table.name == "student_academic_responses":
            for row in rows:
                row["records_json"] = []
        encoded = json.loads(json.dumps(rows, default=encode))
        data[table.name] = rewrite(encoded, identities)
    if not data.get("personal_course_records"):
        raise ValueError("The selected student has no course records")
    return {"format": 1, "student_id": str(STUDENT), "admin_id": str(ADMIN), "tables": data}


def decode_row(table, row):
    if set(row) - set(table.c.keys()):
        raise ValueError(f"Unknown columns in {table.name}")
    result = {}
    for key, value in row.items():
        kind = table.c[key].type
        if value is not None:
            if isinstance(kind, Uuid):
                value = UUID(value)
            elif isinstance(kind, DateTime):
                value = datetime.fromisoformat(value)
            elif isinstance(kind, Date):
                value = date.fromisoformat(value)
            elif isinstance(kind, Numeric):
                value = Decimal(value)
        result[key] = value
    return result


def import_data(db, bundle, passwords):
    if bundle.get("format") != 1 or set(bundle.get("tables", {})) != ALLOWED:
        raise ValueError("Unexpected demo bundle format or table allowlist")
    if bundle.get("student_id") != str(STUDENT) or bundle.get("admin_id") != str(ADMIN):
        raise ValueError("Unexpected demo account identity")
    # A seeded demo stays editable: subsequent launches never restore over its records.
    users = list(db.scalars(select(User.id)))
    if users:
        if set(users) == {STUDENT, ADMIN}:
            return False
        raise ValueError("Refusing to seed a database containing other accounts")
    if any(
        db.scalar(select(func.count()).select_from(Base.metadata.tables[name])) for name in ALLOWED
    ):
        raise ValueError("Refusing to seed a non-empty database")
    for key in ("student", "admin"):
        if len(passwords.get(key, "")) < 16:
            raise ValueError("Demo passwords must be independently generated")
    db.add_all(
        [
            User(
                id=STUDENT,
                email="student@demo.example",
                display_name="시연 학생",
                password_hash=PASSWORDS.hash(passwords["student"]),
                role="user",
                account_status="active",
            ),
            User(
                id=ADMIN,
                email="admin@demo.example",
                display_name="시연 관리자",
                password_hash=PASSWORDS.hash(passwords["admin"]),
                role="super_admin",
                account_status="active",
            ),
        ]
    )
    db.flush()
    for table in Base.metadata.sorted_tables:
        if table.name not in ALLOWED:
            continue
        rows = [decode_row(table, row) for row in bundle["tables"][table.name]]
        if rows:
            # One statement also preserves self-referencing classification trees.
            db.execute(table.insert().values(rows))
    db.flush()
    from app.services.student_academic import read_requirements

    # Context digests omit the owner, so original activations and history stay intact.
    current = read_requirements(db, STUDENT)
    if current.issues:
        raise ValueError(f"Demo academic context invalid: {current.issues}")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["export", "seed"])
    parser.add_argument("--file", required=True, type=Path)
    parser.add_argument("--owner", type=UUID)
    parser.add_argument("--password-file", type=Path)
    args = parser.parse_args()
    settings = Settings()
    if settings.app_env.value != "local":
        raise SystemExit("Demo tooling is restricted to local databases")
    engine = create_engine(settings.sqlalchemy_url, hide_parameters=True)
    if args.action == "export":
        with Session(engine) as db, db.begin():
            db.execute(text("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY"))
            owner = args.owner
            if owner is None:
                courses = Base.metadata.tables["personal_course_records"]
                owners = list(db.scalars(select(courses.c.owner_id).distinct()))
                if len(owners) != 1:
                    raise ValueError("Select a student explicitly when several owners have courses")
                owner = owners[0]
            data = export_data(db, owner)
            args.file.write_text(
                json.dumps(data, default=encode, ensure_ascii=False), encoding="utf-8"
            )
            print(
                json.dumps(
                    {
                        "tables": len(data["tables"]),
                        "courses": len(data["tables"]["personal_course_records"]),
                        "responses": len(data["tables"]["student_academic_responses"]),
                    }
                )
            )
    else:
        if args.password_file is None:
            parser.error("--password-file is required for seed")
        with Session(engine) as db, db.begin():
            # Serialize first-run launches before checking whether the demo is already seeded.
            db.execute(text("SELECT pg_advisory_xact_lock(20261109)"))
            changed = import_data(
                db,
                json.loads(args.file.read_text(encoding="utf-8-sig")),
                json.loads(args.password_file.read_text(encoding="utf-8-sig")),
            )
            print("Demo data restored" if changed else "Existing demo data preserved")


if __name__ == "__main__":
    main()
