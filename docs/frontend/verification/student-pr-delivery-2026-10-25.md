# 학생 수강·졸업 기준 PR 분리 검증 — 2026-10-25

origin/develop 535cd69에서 수강 fd32126과 학생 졸업 기준 배치 5b84db1 두 단위만 옮겼다.
가입 PR #38 및 관리자 UI PR #39의 코드에 의존하지 않는다. 원본의 공식 감사·PDF·검색·근거 검토도 제외했다.

- 수강: 수정 가능한 학년도/자유 학기 분리 입력, 기존 term 문자열 인코딩, 연도+학기 필터·개인 합계,
  기존 연도 미지정 표시/직접 보완·기간 미변경 원문 보존·입력 검증/폐기/실패 재시도.
- 졸업 개인 기준: 대상별 한 틀에 상단 목록/기본 정보·하단 전체 폭 상세/버튼, 짧은 입력2열과 긴 설명 전체 폭.
  기존 한 폼·서버/로컬 저장·CRUD·관계/입력 보호·프로필 적용 유지.
- 분리 코드에서 course_period_test/student_graduation_layout_test/personal_records_test/personal_graduation_test/
  remote_personal_ui_test/page_header_test/input_dialog_test 관련50개 통과.
- --name으로 Size(480),480x520,narrow,student creates school department(마지막에 좁은 크기로 바꾸는 복합 사례),
  course prioritizes personal records 사례를 제외했다. 나머지는 원본과 같은 데스크톱 검증이다.
- 분석·Web/Windows 빌드 각1회 성공. 원본 수강55개·졸업19개와 분리 검증50개는 서로 다른 범위다.
- 화면 렌더링은 원본의 동일 변경에서 확인했다. 원본 검증 문서의 로컬 캡처 경로를 참고한다.
  운영 서버·Windows 네이티브 실기는 미검증. 새 API·DTO·DB·판정 로직 변경 없음.
