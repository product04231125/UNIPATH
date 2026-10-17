# Flutter 프론트엔드 문서

이 폴더는 Flutter Web·Windows 클라이언트의 구현 구조와 기능별 화면 상태를 기록한다. 공통
접근성·레이아웃·AI 보조 원칙은 [제품 UX 기준](product-ux.md), API의 실제 계약은 FastAPI
OpenAPI(`/api/v1/docs`)가 기준이다.

## 현재 기준과 구현

- [product-ux.md](product-ux.md): 화면을 만들고 검토할 때 적용하는 UI·UX 기준
- [architecture.md](architecture.md): 모듈 경계·상태 소유권·저장소/API 전환
- [platform-differences.md](platform-differences.md): 현재 Web·Windows 동작 차이
- [manual-input-boundaries.md](manual-input-boundaries.md): 개인 입력과 공식 데이터의 경계
- [manual-input-audit.md](manual-input-audit.md): ERD/HTML 입력·관계의 구현 대조표와 계약 의존성
- [백엔드 API 요구 명세](../api/frontend-backend-requirements.md): 서버 연결 요구와 미확정 계약
- `features/`: 기능별 현재 동작·상태·계약 경계
- `specs/`: 사용자 흐름과 수용 조건(Gherkin 등)

기능 문서는 현재 동작을 중심으로 유지하고, 상세 테스트 횟수·캡처·작업별 리뷰 결과는
아래 검증 이력에서 참조한다. 에이전트 운영 지침과 스킬 절차는 개인 지침 저장소에서 관리한다.

## 검토·검증 이력

`verification/`은 작업 시점의 결과를 보존한다. 과거 시안이나 검증 성공을 현재 정책 또는
현재 버전의 전체 검증으로 해석하지 않는다. 기능 변경 시 필요한 관련 기록만 참고한다.

| 기록 | 범위 |
| --- | --- |
| [구조 변경](verification/structure-registration-verification.md) | 개인 학업·자료/PDF·관리자 본문 등록 |
| [PR #14 버그](verification/pr14-bug-verification.md) | 세션/저장/포커스 결함 수정·검증 |
| [확정 UI](verification/ui-ux-final-verification.md) | 3테마·관리자 배치·Tab 순서 |
| [UI 검토 보완](verification/ui-ux-review-fixes.md) | 입력 보존·AI 전용 보기·용어/헤더 |
| [탐색·플랫폼](verification/ux-124-verification.md) | 반응형·창·메뉴 개편 |
| [공통 입력·카드](verification/ux-ui-verification.md) | 입력 보호·글꼴·탐색 검증 |
| [과거 스타일 비교](verification/style-preview.md) | 이후 결정으로 대체된 팔레트/삭제/배치 시안 |

## 기능 문서

| 기능 | 문서 | 현재 상태 |
| --- | --- | --- |
| 인증 | [auth](features/auth.md) | 실제 가입·로그인·서버 세션·역할/학교 범위 |
| 관리자 | [admin](features/admin.md) | 실제 API 학사 관리·역할/범위·검토 버전/감사, debug 합성 샘플 |
| 메뉴 탐색 | [navigation](features/navigation.md) | 주요 메뉴 hash URL·뒤로/앞으로·직접 진입 |
| 홈 | [home](features/home.md) | 개인 계획 기반 시작 화면 |
| 일정 | [schedule](features/schedule.md) | 기기 로컬 개인 일정 |
| 수강 관리 | [course](features/course.md) | 기기 로컬 개인 수강 CRUD·학기 필터 |
| 졸업 요건 | [graduation](features/graduation.md) | 개인 학교·학과·교육과정·과목·규칙 CRUD·연결 |
| 활동 | [activity](features/activity.md) | 기기 로컬 개인 활동·봉사 CRUD |
| 경험 | [experience](features/experience.md) | 기기 로컬 개인 경험 CRUD |
| 자격 | [credential](features/credential.md) | 기기 로컬 개인 자격 CRUD |
| 포트폴리오·성과 | [portfolio](features/portfolio.md) | 설명/PDF 기기 보관·성과 기록·기존 구성/지원 초안 |
| AI 도우미 | [assistant](features/assistant.md) | 학교 질의 API·상태/인용 표시·창별 메모리 대화 |
| 설정 | [settings](features/settings.md) | 학업과 계획 로컬 설정 |
| 외부 링크 | [external-links](features/external-links.md) | 1365·Q-Net·개인 증빙 URL 확인·열기·복사 |
