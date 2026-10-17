# Flutter 프론트엔드 구조

`frontend/lib`은 Flutter Web과 Windows에서 같은 화면 코드를 사용한다. 학교 질의는
`POST /api/v1/assistant/queries`를 호출한다. 다른 도메인의 fixture와 기기 로컬 상태는
합성 학사 모델은 실제 서버 모델이 아니다. 인증·역할·학교 범위는 실제 API이며,
기록 CRUD·공식 졸업 판정 API는 아직 연결하지 않았다. [인증 계약](../api/authentication.md)을 따른다.

## 진입과 공통 영역

- `app.dart`: 테마와 Router 구성, 플랫폼 URL 제공자 수명주기
- `shared/app_style.dart`: 3개 제품 테마·오류/삭제/제목표시줄 색상과 독립 기기 로컬 `AppAppearance`. 메인 선택은 저장 성공 뒤 IPC로 열린 AI 창에도 전달하며 새 창은 저장값을 읽는다. 학업·로그인·채팅 저장소와 분리한다.
- `shared/widgets/task_focus_group.dart`: 위젯 작업 순서 기반 Tab 탐색. Router는 본문 작업 공간을 상단보다 먼저 두며 반응형 열은 각 열의 작업을 마친 뒤 다음 열로 이동한다.
- `app_navigation.dart`: 주요 메뉴 경로 parser/delegate와 기존 메모리 로그인 목업 경계.
  주소와 Workspace 선택 메뉴를 연결하며 개인 기록·팝업·빠른 추가 의도는 경로에 저장하지 않는다.
- `workspace.dart`: 선택 메뉴, 목업 데이터 표시, AI 도킹·분리 창 상태 조정
- `shared/pending_ui_action.dart`: 메뉴 이동에 동반되는 일회성 UI 의도. 목적 화면은 필요한 상태가
  준비된 뒤 소비한다. URL·저장소에 영속화하지 않으며 일반 탐색과 명시적 빠른 추가를 구분한다.
- `app_shell/workspace_shell.dart`: 좌측 탐색, 반응형 본문, AI 도킹/오버레이 배치
  - 화면의 `minimumContentWidth`와 도킹 폭으로 메뉴를 먼저 접을지 결정한다.
    홈은 공통 주간표 최소 폭을 사용하고, 졸업요건은 탭·개인 작업 공간 전환에서
    `onMinimumWidthChanged`로 필요한 폭을 전달한다. 목업 표가 숨겨지면 요구 폭도 제외한다.
- `shared/widgets/`: 카드·상태 배지처럼 도메인 상태가 없는 표현 위젯
- `shared/widgets/equal_height_row.dart`: 같은 행의 관련 카드 높이를 실제 콘텐츠에 맞춰 정렬한다.
  홈·기록 메뉴·일정이 재사용하며 세로 배치 임계값과 데이터 소유권은 각 기능에 유지한다.
- `shared/widgets/input_dialog.dart`: 다중 입력 모달·최신 작성 내용의 바깥 클릭 보호·수정/저장 중
  암묵적 닫기 차단을 공유한다. 기능은 `hasContent`, 변경 신호와 저장 상태를 제공한다.
  `showInputDialog`는 종료 애니메이션 완료 뒤 반환해 입력 controller의 조기 폐기를 방지한다.
  명시적 취소는 `InputDialog.cancel`을 사용하고 기능별 `hasUnsavedChanges`로 원본 대비 변경을
  판단한다. 신규 폼은 기본값을 제외한다. `confirmInputDiscard`는 채팅 내부 폼도 공유하며
  계속 작성 기본 포커스와 이전 포커스 복귀를 제공한다. 저장 성공은 직접 pop한다.
- `shared/widgets/content_scroll_view.dart`: 자체 controller와 16px 스크롤바 여백을 소유한다.
  모든 메뉴의 세로 본문·입력 폼·초안 미리보기에서 내용과 스크롤바를 분리한다.
  작업 공간의 화면 최소 폭에는 여백을 포함하며, 기록 카드 안의 중첩 세로 스크롤은 제거했다.
- `shared/widgets/horizontal_scroll_area.dart`: 비교 축의 하단 여백과 폭 전환 후 손잡이·가로 입력을
  공유한다. controller/비교 내용은 기능 소유다. 홈은 작업 공간에서 전달한 가려지는 폭을 제외해
  주간표를 배치하며 채팅 상태를 주간표 도메인에 넣지 않는다.
- `shared/widgets/page_header.dart`: 한글 제목·선택 문맥/설명·헤더 버튼의 정렬과 재배치,
  접근성 heading 표현. 문구·상태·데이터 소유권은 각 기능에 유지한다.
- `shared/app_typography.dart`: 역할별 공통 글자 크기·줄높이, 학생·관리자 공통 테마 적용.
  Pretendard Regular/Medium/SemiBold/Bold를 앱에 포함해 Web·Windows에서 사용한다.
  글자 단계는 페이지 26, 섹션 18, 본문 14, 보조문 13이며 시스템 확대를 유지한다.
  원본 글꼴과 SIL OFL 라이선스는 `frontend/assets/fonts/pretendard/`에 보관한다.
- `shared/widgets/anchored_select_field.dart`: 트리거 기준 배치·키보드 포커스를 공유하는 선택 제어
- `shared/external_links.dart`, `widgets/external_link_button.dart`: 브라우저 URL 검증·플랫폼 열기와
  이동 확인·실패·복사 UI. 저장 입력도 같은 URL 검증을 사용한다.
- `features/planning/planning_dates.dart`, `weekly_schedule.dart`: 홈·일정의 공통 날짜 계산과 홈 7일 표
- `chat_window*.dart`: 플랫폼별 AI 분리 창 어댑터
- `features/assistant/assistant_window_host.dart`: 작업 공간의 native 창 호출/상태 신호 경계.
  테스트는 가짜 host를 사용하며 실제 창 검증과 구분한다.
- `features/settings/chat_preferences.dart`: 별도 기기 로컬 키의 채팅 열기 방식과 실패/재시도 상태.
  Workspace가 소유하고 설정 UI에 주입한다. 학업 repository·계정·대화 데이터와 독립이다.

## 기능 소유권

| 모듈 | 소유 화면·로컬 상태 |
| --- | --- |
| `features/auth` | 로그인·회원가입 목업 |
| `features/admin` | 공통 관리자 셸·입력 스키마·역할/범위·메모리 fake·변경 이력 |
| `features/home` | 개인 계획 기반 이번 주 일정·준비 목록·우선 링크 |
| `features/planning` | 기기 로컬 개인 계획 프로필·일정 repository |
| `features/schedule` | 월간 개인 일정과 선택 날짜 목록, 일정 CRUD |
| `features/graduation` | 졸업요건 fixture, 개인 교육과정·과목·규칙 입력과 로컬 관계 검증 |
| `features/records/course` | 수강 관리와 수강 직접 입력 상태 |
| `features/records/activity` | 활동 입력 상태 |
| `features/records/experience` | 경험 입력 상태 |
| `features/records/credential` | 자격 입력 상태 |
| `features/records/portfolio` | 성과 원본, 포트폴리오 구성·지원 문서의 독립 로컬 초안 |
| `features/assistant` | 학교 질의 HTTP 어댑터·응답 DTO, 메인 소유 대화 상태와 IPC 원격 상태, 공통 응답 UI |
| `features/settings` | 설정 진입 화면 |

## 임시 데이터와 API 전환

- AppNavigation은 개발 역할과 관리자 repository를 소유한다. AdminRepository는 교체 경계,
  FakeAdminRepository는 학생 저장소와 분리된 메모리 구현이다. 위젯은 입력·표시를 담당하고
  fake는 최신 계정·범위·관계·버전을 검사한다. 실제 관리자 API는 서버 권한 검증이 필수다.
- `features/admin/admin_shell.dart`는 역할별로 전달받은 메뉴의 반응형 탐색과 선택 상태만 담당한다.
  학교 문맥·목록 검색/필터·현황·권한별 상세 작업은 AdminWorkspace, 필드 그룹과 작성 보호는
  AdminEditor가 소유한다. 표시용 필드 그룹은 repository 모델·검증/전송 계약을 바꾸지 않는다.

- `assistant_api.dart`는 Web/Windows 공통 `http.Client`와 명시적 요청·응답 모델을 사용한다.
  `API_BASE_URL`은 빌드 환경에서 주입한다. `AssistantGateway`는 테스트 주입 경계다.
- `AssistantConversation`은 요청 중복 차단, 늦은 응답 폐기, 입력 보존과 같은 항목의 재시도를
  담당한다. 서버에는 질문과 사용자가 확인한 학교 문맥만 보내며 로컬 예시·개인 기록·로그인
  입력을 보내지 않는다. 메인 창이 요청·대화를 계속 소유하고 분리 창은 `RemoteConversation`으로
  상태를 표시하며 입력·보내기·재시도를 IPC로 전달한다. 창 전환은 HTTP 클라이언트를 재생성하지 않는다.
- `ConversationBridge`는 상태 revision과 명령 ID를 사용해 오래된 상태·중복 명령을 구분한다.
  학교 문맥은 저장에 성공한 기기 프로필에서 공유하며 미저장 폼 값을 요청에 적용하지 않는다.

- 기록 예시 행은 `features/records/fixtures/`, 졸업요건 표 행은
  `features/graduation/graduation_mock_fixture.dart`에 둔다.
- `planning`의 프로필·일정은 `SharedPreferences`에 저장하는 기기 로컬 개인 계획이다. 학교 공식
  학사정보·일정·졸업 판정 데이터가 아니며, API 계약이 정해지면 repository를 교체한다.
- `planning_repository.dart`는 읽기 성공 전 쓰기를 차단하고 저장 성공 뒤에만 메모리 상태를
  확정한다. `planning_storage_state.dart`는 홈·일정·설정의 읽기 오류·재시도 표현을 공유한다.
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

### 개인 기록 저장 직렬화 (2026-10-15)
- PersonalRecordRepository는 같은 기기/메인 isolate에서 종류별 작업 큐를 공유한다. 저장/삭제 직전 최신 저장 상태를 읽어 다른 객체의 변경을 덮어쓰지 않는다. 저장 키가 없어졌다면 재읽기의 메모리 목록도 비운다. 실패한 읽기 뒤 쓰기는 차단하며 실패가 후속 큐를 막지 않는다.
- personal_records_test의 concurrent personal writes로 서로 다른 객체의 동시 추가·이전 객체 삭제·빈 저장 재읽기를 검증한다. 서버 동기화나 다른 OS 프로세스 사이의 잠금은 제공하지 않는다.

- 작업 큐는 완료 전에 공유 슬롯을 해제한다. 완료 Future를 계속 보관하지 않아 종료된 비동기 실행 영역을 다음 화면/검사로 가져오지 않는다. 최종 전체 275개 및 저장 관련 42개 회귀 통과.

### 개인 학업 본문 관리 (2026-10-17)
- `LocalRecordWorkbench`는 개인 로컬 기록의 목록·본문 입력·작성 보호·실패 상태를 소유한다. 학업 필드/관계는 `personal_graduation_fields.dart`, 학교/학과/교육과정 탭은 `PersonalGraduationWorkspace`가 조정한다.
- 개인 학교/학과 종류는 기존 PersonalRecordRepository의 독립 키를 사용한다. 프로필 적용만 기존 메인 소유 PlanningRepository를 주입하며 관리자 모델/권한과 공유하지 않는다.

### 개인 자료 보관 (2026-10-17)
- `MaterialsPage`는 등록 폼·선택 PDF·실패/수정/내보내기를, `MaterialRepository`는 자료 설명/바이너리의 원자적 보관과 한도 검증을 담당한다. 기존 성과/구성/지원 문서 저장소는 유지한다.
- `MaterialDatabase`는 플랫폼 어댑터 경계다. Web은 IndexedDB(sembast_web), Windows는 앱 지원 디렉터리(sembast_io)이며 PDF를 SharedPreferences나 서버 DTO에 넣지 않는다. 테스트는 이 경계를 독립 메모리 DB로 주입한다.
- 실제 자료 업로드·AI 요청·색인·삭제 전파는 아직 없다. 학교 질의 API에 개인 PDF/설명을 임의로 전송하지 않는다.
