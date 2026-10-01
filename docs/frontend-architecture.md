# Flutter 프론트엔드 구조

`frontend/lib`은 Flutter Web과 Windows의 같은 화면 코드를 사용한다. 현재는 API 계약이
아직 없으므로 fixture와 로컬 상태는 화면 구조를 검증하기 위한 임시 구현이며 실제 서버
모델이 아니다.

## 화면 진입과 공통 영역

- `app.dart`: 로그인 목업과 작업 공간의 최상위 전환을 담당한다.
- `workspace.dart`: 선택 메뉴, 목업 데이터 표시, AI 도킹·분리 창 상태만 조정한다.
- `app_shell/workspace_shell.dart`: 좌측 탐색, 반응형 본문, AI 도킹/오버레이 배치를 담당한다.
- `shared/widgets/`: 카드와 상태 배지처럼 도메인 상태가 없는 표현 위젯만 둔다.

## 기능 모듈

각 메뉴는 `features/` 아래에서 화면과 화면 전용 상태를 소유한다.

- `auth`: 로그인·회원가입 목업
- `home`: 빠른 이동 카드가 있는 시작 화면
- `graduation`: 탭, 개인 기준 설정 폼, 개인 기준 상태와 공식 표 fixture
- `records/course`, `activity`, `experience`, `credential`, `portfolio`: 메뉴별 진입 화면과 직접 입력 상태
- `assistant`: 도킹 AI 패널과 목업 대화 상태
- `settings`: 계약이 확정되기 전의 설정 진입 화면

## 임시 데이터와 API 전환

- 기록 예시 행은 `features/records/fixtures/`에, 졸업요건 표 행은
  `features/graduation/graduation_mock_fixture.dart`에 둔다.
- `목업용` 스위치는 예시 행만 표시·숨김 처리한다. 이번 실행에서 직접 추가한 기록은 유지한다.
- FastAPI OpenAPI 계약이 생기면 fixture와 로컬 상태를 기능별 repository/adapter로 교체한다.
  클라이언트는 OpenAPI에 없는 필드·상태·판정을 제품 계약으로 만들지 않는다.

## 검증

화면·상태 변경 시 `flutter analyze`, 관련 위젯 테스트, Web·Windows 빌드를 실행한다. AI
대화, 공식 졸업감사, 역할 권한, 학교 데이터는 API 계약이 확정되기 전까지 목업 화면이
실제 기능 또는 공식 판정을 대신하지 않는다.
