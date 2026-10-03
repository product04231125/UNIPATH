# Flutter 프론트엔드 문서

이 폴더는 Flutter Web·Windows 클라이언트의 구현 구조와 기능별 화면 상태를 기록한다. 공통
접근성·레이아웃·AI 보조 원칙은 [제품 UX 기준](../product-ux.md), API의 실제 계약은 FastAPI
OpenAPI(`/api/v1/docs`)가 기준이다.

## 문서 구분

- [architecture.md](architecture.md): 모듈 경계, 상태 소유권, fixture와 API 전환 방식
- [platform-differences.md](platform-differences.md): 현재 구현된 Web·Windows 동작 차이
- [manual-input-boundaries.md](manual-input-boundaries.md): ERD 기준 개인 입력·공식 데이터 경계와 현재 구현
- `features/`: 로그인부터 메뉴별 목적, 현재 구현, 목업 경계, 후속 계약과 검증

기능 문서는 구현된 동작과 계획을 섞지 않는다. API가 없는 현재의 입력·행 데이터는 fake
fixture 또는 로컬 상태이며, 제품 계약이나 학교 공식 데이터가 아니다.

## 기능 문서

| 기능 | 문서 | 현재 상태 |
| --- | --- | --- |
| 인증 | [auth](features/auth.md) | 로그인·회원가입 목업 |
| 홈 | [home](features/home.md) | 개인 계획 기반 시작 화면 |
| 일정 | [schedule](features/schedule.md) | 기기 로컬 개인 일정 |
| 수강 관리 | [course](features/course.md) | 기기 로컬 개인 수강 CRUD·학기 필터 |
| 졸업 요건 | [graduation](features/graduation.md) | 개인 기준 설정 목업 |
| 활동 | [activity](features/activity.md) | 기기 로컬 개인 활동·봉사 CRUD |
| 경험 | [experience](features/experience.md) | 기기 로컬 개인 경험 CRUD |
| 자격 | [credential](features/credential.md) | 기기 로컬 개인 자격 CRUD |
| 포트폴리오·성과 | [portfolio](features/portfolio.md) | 기기 로컬 개인 성과 CRUD |
| AI 도우미 | [assistant](features/assistant.md) | 로컬 대화·도킹/분리 창 목업 |
| 설정 | [settings](features/settings.md) | 학업과 계획 로컬 설정 |
