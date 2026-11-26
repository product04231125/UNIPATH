# PR #48 프런트 수정 검증 — 2026-11-08

기준 시작 커밋은 `d42d968`이다. 백엔드 구현과 PR #52 코드는 변경하지 않았다.
공식 문서 운영·사용자 실기 확인은 이번 검증에서 재개하지 않았다.

| 항목 | 최종 동작 | 근거 |
| --- | --- | --- |
| 학점표 가로 이동 | 공통 HorizontalScrollArea에 헤더·열·행·비고를 함께 배치. 열 추가/창 축소 후 손잡이와 마우스 가로 이동 제공 | `ccc30d0`, graduation_template_test의 `credit grid exposes mouse horizontal scrolling after adding columns and resizing`: 6열 추가 → 760×1000 → 마우스 이동 → 오른쪽 비고 입력 통과 |
| 규칙 묶음 | 같은 화면 위쪽에서 등록한 동일 학교 draft를 아래 요건에서 선택. 없으면 등록 위치와 선택이 필수가 아님을 안내 | `7467734`, admin_rule_metadata_flow_test: 실제 등록 폼 저장→선택→요건 저장. 타 학교·적용된 묶음 제외 |
| 요건 근거 URL | 공개 가능한 규정 주소 입력 안내. 관리자 수정 화면의 원문 열기용. 현재 학생 화면에는 이 필드를 직접 표시하지 않음 | `7467734`, AdminEditor의 sourceUrl 필드/원문 열기, RemoteAdminRepository source_url 매핑. 학생이 보는 승인 문서 근거 URL과 구별 |
| 논문 오해 정정 | 새 개인 계산 선택에서 논문 조건 제외. 과거 조건/이력은 읽되 requires_approval true/false를 임의 변경하지 않음 | `2eb7b5a`, personal_calculation_test 2개(승인 정책/신규 선택 제외·이전 조건 표시), personal_requirement_panel_test 1개(등록·동일 요청 재시도) 통과 |
| 수동 체크·활동 설명 | 수동 조건의 빈 근거는 단건/선택 조회에서 허용하되 needs_review 유지. 일반 조건의 빈 근거는 거부. 활동 설명은 크롬 플래그와 로딩/오류/정상 상태에 무관하게 유지 | `2707d02`, rule_program_api_test 7개 + activity_header_contract_test 2개 통과. 수동 선택 경계 1개 재검증 통과 |
| 문서 5개 | 학생 화면에 없는 신청 이력 경로, 이미 연결된 승인/회수 UI, 자료 파일/개인 기록 저장 경계, 사용자 수정 access 계약 및 미리보기 경로 정정 | `1c81a7a`, 아래 문서. 목표 가입·심사 정책은 미구현 절에 그대로 유지 |

## 정정한 문서와 확인 기준

- [인증 API](../../api/authentication.md): 현재 OpenAPI의 `/admin/users/{user_id}/access` 입력, FE 사용자 수정과 개인 파일 저장 경계.
- [최초 가입](../../api/initial-school-admin-signups.md): 현재 가입 응답/계속하기와 실제 이력 진입점. 승인 전 세션 없는 목표와 구별.
- [추가 신청](../../api/school-admin-applications.md): 현재 서버의 일반 계정 요청 허용과 학생 설정의 진입점 없음 구별.
- [관리자](../features/admin.md): 묶음/URL/학점표/승인·회수의 현재 구현과 과거 합성 편집기 기록 구별.
- [인증 화면](../features/auth.md): 관리자 미리보기 진입/복귀 및 자료 파일의 기기 보관 경계.

다섯 문서의 로컬 링크에 누락이 없음을 검사했다. 게시 OpenAPI의 access 입력은
`role`, `account_status`, `expected_version`이며, 서버 스키마를 변경하지 않았다.

## 검증 범위

- 관련 테스트 명령 9회. 첫 스크롤 테스트의 대상 찾기와 새 메타데이터 테스트의 컴파일 오류를 고친 뒤 해당 사례만 재실행했다. 통과한 범위는 서로 겹치므로 실행별 개수를 단순 합산하지 않는다.
- 최종 `flutter analyze` 1회: 문제 없음.
- 최종 `flutter build web` 1회, `flutter build windows` 1회: 성공.
- 로컬 SDK는 Flutter 3.47.5. 저장소 CI는 고정 SDK로 전체 분석·테스트를 별도 수행한다.
- 창 축소 회귀는 사용자가 요청한 학점표 문제에 한해 추가했다. 활동 휴대폰 숨김 검사는 데스크톱 크기에서 PhoneChromeScope 플래그를 바꿔 수행했다.
- 실제 서버 권한 경쟁·학교 자료 운영, 브라우저 및 Windows 네이티브 수동 조작, DPI/스크린리더 실기는 이 자동 검증의 완료 범위가 아니다.
