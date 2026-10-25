# 학교별 신청 접수 필터 PR 분리 검증 — 2026-10-25

기존 가입/접수 PR #38에 원본 9c31922 중 기존 심사 목록의 학교 선택만 추가했다. 접근 가능한 학교와
조회한 신청의 학교를 선택지로 제공하고 institution_id/status/cursor 계약을 유지한다. 필터 변경 시
기존 목록과 cursor를 지우고 재시도/추가 조회는 같은 조건을 유지한다. 최초 가입 접수 API 요청은 그대로다.

- 분리 코드에서 admin_application_school_filter_test/school_admin_application_inbox_test/school_admin_applications_ui_test/admin_application_api_test 통과.
- 해당 실행은 총15개이며 데스크톱/비레이아웃14개와 기존 Size(480,720)1개가 포함됐다.
  기존 좁은 사례를 선택식에서 제외하지 못한 실행 실수로 기록한다. 별도 좁은 검증을 추가하거나 통과 요구로 삼지 않는다.
- 분석·Web/Windows 빌드 각1회 성공. 원본 51개 통과와 구분한다.
- 운영 서버·네이티브 실기는 미검증. 원래 최초 학교명/홈페이지 접수는 API 계약 대기이며 성공/대기 이력을 만들지 않는다.
