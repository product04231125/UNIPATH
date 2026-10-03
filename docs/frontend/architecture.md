# Flutter 프론트엔드 구조

`frontend/lib`은 Flutter Web과 Windows에서 같은 화면 코드를 사용한다. API 계약이 아직 없으므로
fixture와 로컬 상태는 화면 구조 검증용 임시 구현이며 실제 서버 모델이 아니다.

## 진입과 공통 영역

- `app.dart`: 로그인 목업과 작업 공간의 최상위 전환
- `workspace.dart`: 선택 메뉴, 목업 데이터 표시, AI 도킹·분리 창 상태 조정
- `app_shell/workspace_shell.dart`: 좌측 탐색, 반응형 본문, AI 도킹/오버레이 배치
- `shared/widgets/`: 카드·상태 배지처럼 도메인 상태가 없는 표현 위젯
- `shared/app_typography.dart`: 역할별 공통 글자 크기·줄높이, 앱 테마 적용
- `shared/widgets/anchored_select_field.dart`: 트리거 기준 배치·키보드 포커스를 공유하는 선택 제어
- `shared/external_links.dart`, `widgets/external_link_button.dart`: 브라우저 URL 검증·플랫폼 열기와
  이동 확인·실패·복사 UI. 저장 입력도 같은 URL 검증을 사용한다.
- `features/planning/planning_dates.dart`, `weekly_schedule.dart`: 홈·일정의 공통 날짜 범위·7일 표
- `chat_window*.dart`: 플랫폼별 AI 분리 창 어댑터

## 기능 소유권

| 모듈 | 소유 화면·로컬 상태 |
| --- | --- |
| `features/auth` | 로그인·회원가입 목업 |
| `features/home` | 개인 계획 기반 이번 주 일정·준비 목록·우선 링크 |
| `features/planning` | 기기 로컬 개인 계획 프로필·일정 repository |
| `features/schedule` | 월간 개인 일정과 이번 주 목록, 일정 CRUD |
| `features/graduation` | 졸업요건 fixture, 개인 교육과정·과목·규칙 입력과 로컬 관계 검증 |
| `features/records/course` | 수강 관리와 수강 직접 입력 상태 |
| `features/records/activity` | 활동 입력 상태 |
| `features/records/experience` | 경험 입력 상태 |
| `features/records/credential` | 자격 입력 상태 |
| `features/records/portfolio` | 성과 원본, 포트폴리오 구성·지원 문서의 독립 로컬 초안 |
| `features/assistant` | 도킹 AI 패널, 목업 대화, 분리 창 본문 |
| `features/settings` | 설정 진입 화면 |

## 임시 데이터와 API 전환

- 기록 예시 행은 `features/records/fixtures/`, 졸업요건 표 행은
  `features/graduation/graduation_mock_fixture.dart`에 둔다.
- `planning`의 프로필·일정은 `SharedPreferences`에 저장하는 기기 로컬 개인 계획이다. 학교 공식
  학사정보·일정·졸업 판정 데이터가 아니며, API 계약이 정해지면 repository를 교체한다.
- `features/records/personal_record_repository.dart`는 메뉴별 v1 키의 기기 로컬 개인 기록을 소유한다.
  `personal_record_fields.dart`는 메뉴별 로컬 입력 스키마·검증이며 서버 DTO가 아니다.
  `RecordMenuPage`는 해당 메뉴 저장소를 읽고 구조화 입력·수정·삭제를 제공한다.
- 개인 졸업 작업 공간도 같은 저장소의 세 종류를 사용한다. `personal_graduation_fields.dart`는
  저장된 개인 교육과정·과목·기록의 선택 목록과 관계 검증을 소유하며 규칙을 실행하지 않는다.
- `목업용` 스위치는 예시 행만 표시·숨김 처리한다. 개인 기록은 메뉴 전환·재시작 뒤에도 유지한다.
- `portfolio_workspace_repository.dart`는 구성·지원 문서를 별도 v1 키에 저장하고, 경험·성과
  원본 저장소를 참조한다. `portfolio_editor_dialog.dart`는 입력·선택·정렬,
  `portfolio_drafts_page.dart`는 읽기·실패·목록·미리보기·삭제 UI를 소유한다.
- OpenAPI 계약이 확정되면 feature별 fixture와 로컬 상태를 repository/adapter로 교체한다.
  클라이언트는 OpenAPI에 없는 필드·상태·판정을 제품 계약으로 만들지 않는다.

## 문서 갱신

기능별 사용자 동작·fixture·후속 API 요구는 `features/`의 해당 문서에, 공통 UX는
`docs/product-ux.md`에 기록한다. 기능 구조·상태 소유권을 바꿀 때만 이 문서를 갱신한다.
