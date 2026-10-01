# Flutter 프론트엔드 구조

`frontend/lib`은 Flutter Web과 Windows에서 같은 화면 코드를 사용한다. API 계약이 아직 없으므로
fixture와 로컬 상태는 화면 구조 검증용 임시 구현이며 실제 서버 모델이 아니다.

## 진입과 공통 영역

- `app.dart`: 로그인 목업과 작업 공간의 최상위 전환
- `workspace.dart`: 선택 메뉴, 목업 데이터 표시, AI 도킹·분리 창 상태 조정
- `app_shell/workspace_shell.dart`: 좌측 탐색, 반응형 본문, AI 도킹/오버레이 배치
- `shared/widgets/`: 카드·상태 배지처럼 도메인 상태가 없는 표현 위젯
- `chat_window*.dart`: 플랫폼별 AI 분리 창 어댑터

## 기능 소유권

| 모듈 | 소유 화면·로컬 상태 |
| --- | --- |
| `features/auth` | 로그인·회원가입 목업 |
| `features/home` | 빠른 이동 카드가 있는 시작 화면 |
| `features/graduation` | 탭, 개인 기준 설정 폼, 개인 기준 상태, 졸업요건 fixture |
| `features/records/course` | 수강 관리와 수강 직접 입력 상태 |
| `features/records/activity` | 활동 입력 상태 |
| `features/records/experience` | 경험 입력 상태 |
| `features/records/credential` | 자격 입력 상태 |
| `features/records/portfolio` | 포트폴리오·성과 입력 상태 |
| `features/assistant` | 도킹 AI 패널, 목업 대화, 분리 창 본문 |
| `features/settings` | 설정 진입 화면 |

## 임시 데이터와 API 전환

- 기록 예시 행은 `features/records/fixtures/`, 졸업요건 표 행은
  `features/graduation/graduation_mock_fixture.dart`에 둔다.
- `목업용` 스위치는 예시 행만 표시·숨김 처리한다. 이번 실행에서 직접 추가한 기록은 유지한다.
- OpenAPI 계약이 확정되면 feature별 fixture와 로컬 상태를 repository/adapter로 교체한다.
  클라이언트는 OpenAPI에 없는 필드·상태·판정을 제품 계약으로 만들지 않는다.

## 문서 갱신

기능별 사용자 동작·fixture·후속 API 요구는 `features/`의 해당 문서에, 공통 UX는
`docs/product-ux.md`에 기록한다. 기능 구조·상태 소유권을 바꿀 때만 이 문서를 갱신한다.
