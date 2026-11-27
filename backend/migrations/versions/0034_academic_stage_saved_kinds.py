"""학업 프로필 학년을 1~4학년·졸업예정·졸업 단계로, 활동·자격증 추천 결과도 저장.

planning_profiles.academic_year_override(1~4) becomes academic_stage (year1~year4, graduating,
graduate), the same values the recommendation requests send; a set year carries over as yearN.
analysis_results also keeps 활동 추천 (activity) and 자격증 추천 (certificate) results.

Revision ID: 0034_academic_stage_saved_kinds
Revises: 0033_drop_legacy_portfolio
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0034_academic_stage_saved_kinds"
down_revision: str | Sequence[str] | None = "0033_drop_legacy_portfolio"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

STAGES = "('year1','year2','year3','year4','graduating','graduate')"


def upgrade() -> None:
    op.add_column("planning_profiles", sa.Column("academic_stage", sa.String(16), nullable=True))
    op.execute(
        "UPDATE planning_profiles SET academic_stage = 'year' || academic_year_override "
        "WHERE academic_year_override IS NOT NULL"
    )
    op.drop_constraint(op.f("ck_planning_profiles_academic_year"), "planning_profiles")
    op.drop_column("planning_profiles", "academic_year_override")
    op.create_check_constraint(
        op.f("ck_planning_profiles_academic_stage"),
        "planning_profiles",
        f"academic_stage IS NULL OR academic_stage IN {STAGES}",
    )
    op.drop_constraint(op.f("ck_analysis_results_kind"), "analysis_results")
    op.create_check_constraint(
        op.f("ck_analysis_results_kind"),
        "analysis_results",
        "kind IN ('posting','gap','search','activity','certificate')",
    )


def downgrade() -> None:
    op.execute("DELETE FROM analysis_results WHERE kind IN ('activity','certificate')")
    op.drop_constraint(op.f("ck_analysis_results_kind"), "analysis_results")
    op.create_check_constraint(
        op.f("ck_analysis_results_kind"), "analysis_results", "kind IN ('posting','gap','search')"
    )
    op.add_column(
        "planning_profiles", sa.Column("academic_year_override", sa.Integer(), nullable=True)
    )
    # 졸업예정·졸업 have no 1~4 year: they fall back to the automatic year.
    op.execute(
        "UPDATE planning_profiles SET academic_year_override = "
        "CAST(substr(academic_stage, 5) AS INTEGER) WHERE academic_stage LIKE 'year_'"
    )
    op.drop_constraint(op.f("ck_planning_profiles_academic_stage"), "planning_profiles")
    op.drop_column("planning_profiles", "academic_stage")
    op.create_check_constraint(
        op.f("ck_planning_profiles_academic_year"),
        "planning_profiles",
        "academic_year_override IS NULL OR academic_year_override BETWEEN 1 AND 4",
    )
