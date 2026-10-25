# 관리자 혼합형 배치 — 2026-10-25

## 적용

사용자가 비교 시안 중 4번(위 2열·아래 전체 폭)을 선택했다. 기존 메뉴별 등록 대상은 유지하고 각 대상의 목록과 기본 정보(이름·학교)를 위쪽에, 나머지 범위·기간·출처/연결·상세와 취소/등록을 아래 전체 폭에 표시했다. 필드가 없는 이름/학교를 임의로 추가하지 않는다.

AdminEditor가 하나의 FormState와 controller 집합을 소유한다. 목록 검색은 별도 Form으로 분리하여 등록 초기화가 검색 입력을 바꾸지 않게 한다. 모든 기존 필드를 한 번씩 렌더링하고 하단의 관련 필드를 가능한 폭에서 2열로 배치한다. 수정/회수 모달, DTO·API·권한·저장 계약은 변경하지 않았다. 별도 탭 탐색이나 상단 문맥 헤더 개편은 이번 변경에 포함하지 않았다.

## 검증

- 관련 신규/갱신 5개·기존 관리자 22개 통과. 혼합형 상하/좌우 경계, 전체 폭 상세, 필드 중복 없음, 하단 필수값 오류 시 저장 차단, 취소/계속 작성, 두 역할 저장 실패/입력 보존·재시도/성공 후 초기화·검색 빈 결과, 읽기 전용 전체 폭을 확인했다.
- 명령: flutter test test/admin_list_panel_test.dart 1회 통과. 최초 제품 루트에서 시도한 1회는 pubspec 부재로 검사 시작 전 종료하여 frontend에서 실행했다. 기존 회귀는 flutter test test/admin_workspace_test.dart --name '^(?!.*(compact admin|compact=true|narrow|two columns and stack|inline registration)).*$' 1회 통과.
- flutter analyze 1회 문제 없음. Web/Windows build 각 1회 성공.
- 실제 Web 개발 샘플 1440×1000 크림·브라운: 슈퍼관리자 빈 규칙 묶음/등록 후 목록, 학교관리자 공식 문서의 위쪽 기본 정보와 아래 전체 폭 상세를 확인했다. 로컬 frontend/build/admin-audit/mixed-super-empty.jpg, mixed-super-populated.jpg, mixed-school-documents.jpg에 캡처했으며 Git에는 포함하지 않는다.
- 좁은 화면은 사용자 결정으로 검증하지 않았다. 실제 서버 저장·Windows 네이티브·다른 테마·대량 목록·스크린리더 실기는 미검증이다.
