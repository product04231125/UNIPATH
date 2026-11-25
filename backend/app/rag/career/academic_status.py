"""The academic stage a student picked, as one citable record for degree requirements.

Degree requirements (4년제 대학 졸업, 학사 등) need a cited record to count as met, but the stage is
chosen in the search form rather than saved as a record. This builds that record from the
student's planning profile and the chosen stage, cited like a document chunk.
"""

from uuid import NAMESPACE_URL, uuid5

TITLE = "학적 정보"
STAGES = {
    "year1": "1학년",
    "year2": "2학년",
    "year3": "3학년",
    "year4": "4학년",
    "graduating": "졸업예정",
    "graduate": "졸업",
}


def academic_status(owner_id, stage, profile=None):
    """(record, location) for the analysis; profile fields that are missing are left out."""
    lines = [TITLE]
    for label, field in (
        ("학교", "school"),
        ("학과", "department"),
        ("입학연도", "admission_year"),
    ):
        value = getattr(profile, field, None)
        if isinstance(value, (str, int)) and str(value).strip():
            lines.append(f"{label}: {value}")
    lines.append(f"현재 학년: {STAGES[stage]}")
    record_id = str(uuid5(NAMESPACE_URL, f"unipath:academic-status:{owner_id}:{stage}"))
    record = dict(
        kind="experience", record_id=record_id, version=1, text="\n".join(lines), truncated=False
    )
    location = dict(filename=TITLE, location="공고 찾기에서 고른 학년", offset=0, method="academic")
    return record, location
