import json
from uuid import UUID, uuid4

import pytest
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_student_academic import ME, activation, requirement
from test_student_academic import academic_student as academic_student
from test_student_course_records import create

from app.models import Base
from app.models.identity import AuthSession, User
from app.models.personal import CourseRecord
from app.operations.demo_bundle import ADMIN, STUDENT, encode, export_data, import_data
from app.services.auth import PASSWORDS
from app.services.student_academic import read_requirements

pytestmark = pytest.mark.integration


def test_demo_roundtrip_excludes_identity_and_preserves_source_and_demo_edits(
    academic_student, auth_db
):
    e = academic_student
    item = str(uuid4())
    doc = requirement(e, {"kind": "checklist", "lines": [{"id": item, "text": "합성 체크"}]})
    active = activation(e)
    response = e["c"].put(
        ME + f"academic-requirements/{doc['id']}/responses/{item}",
        headers=e["student"],
        json={
            "client_id": str(uuid4()),
            "expected_version": 0,
            "activation_id": active["activation_id"],
            "value": True,
            "records": [],
        },
    )
    assert response.status_code == 200, response.text
    course = create(e, completion="in_progress", category="전공선택", credits="3.125")
    with auth_db() as db:
        owner = db.scalar(
            select(CourseRecord.owner_id).where(CourseRecord.id == UUID(course["id"]))
        )
        original_users = list(db.scalars(select(User)))
        before = read_requirements(db, owner).model_dump(mode="json")
        bundle = export_data(db, owner)
        serialized = json.dumps(bundle, default=encode)
        assert "auth_sessions" not in bundle["tables"] and "users" not in bundle["tables"]
        for user in original_users:
            assert user.email not in serialized and user.password_hash not in serialized
        assert str(owner) not in serialized
        assert read_requirements(db, owner).model_dump(mode="json") == before
        with pytest.raises(ValueError, match="other accounts"):
            import_data(
                db,
                bundle,
                {"student": "synthetic-student-password", "admin": "synthetic-admin-password"},
            )
        engine = db.get_bind().engine
    schema = "demo_test_" + uuid4().hex
    with engine.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    target = engine.execution_options(schema_translate_map={None: schema})
    passwords = {"student": "synthetic-student-password", "admin": "synthetic-admin-password"}
    try:
        Base.metadata.create_all(target)
        with Session(target) as db, db.begin():
            assert import_data(db, bundle, passwords)
        with Session(target) as db, db.begin():
            assert set(db.scalars(select(User.id))) == {STUDENT, ADMIN}
            assert PASSWORDS.verify(db.get(User, STUDENT).password_hash, passwords["student"])
            assert db.scalar(select(func.count()).select_from(AuthSession)) == 0
            current = read_requirements(db, STUDENT)
            assert current.issues == []
            assert current.documents[0].responses[0].value is True
            record = db.get(CourseRecord, UUID(course["id"]))
            assert record.owner_id == STUDENT and str(record.credits) == "3.125"
            record.title = "시연 중 수정한 기록"
        with Session(target) as db, db.begin():
            assert import_data(db, bundle, passwords) is False
            assert db.get(CourseRecord, UUID(course["id"])).title == "시연 중 수정한 기록"
            bad = {**bundle, "tables": {**bundle["tables"], "auth_sessions": []}}
            with pytest.raises(ValueError, match="allowlist"):
                import_data(db, bad, passwords)
    finally:
        with engine.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
