# 관리자 사용자 필터 PR 분리 검증 — 2026-10-25

기존 관리자 UI PR #39에 원본 9c31922 중 사용자 역할/상태·이름/이메일/활성 학교 범위 검색만 추가했다.
신청 접수 학교 필터는 PR #38로 분리했으며 최초 가입·감사·원본 PDF·학교 근거 검토는 포함하지 않는다.

- 분리 코드에서 admin_user_filters_test/admin_workspace_test/admin_list_panel_test/remote_admin_test의 데스크톱 38개 통과.
- compact admin/compact=true/narrow/inline registration/Size(480) 사례는 --name 선택식으로 제외했다.
- 정적 분석 및 Web/Windows 빌드 각1회 성공. 원본 51개 결과와 구분한다.
- 원본 데스크톱 렌더링 증거는 작업 공간의 account-role-filters.jpg/account-filtered-school.jpg이며 새 시각 변경은 없다.
- 운영 서버·Windows 네이티브 실기는 미검증이다. 새 API·권한 변경·학생 개인 기록 접근 없음.
