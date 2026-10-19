# 계정·세션·역할 API

2026-10-19 기준. 계약 원본은 [OpenAPI](openapi.json)다. 이메일 소유 확인·비밀번호
찾기·학교 담당자 신원 확인·SSO는 후속 작업이다. 비밀번호 변경은 아래 API로 구현했다.
학사 관리 메타데이터는 [학사 API](academic.md)로 구현했다. 가입 이메일은
로그인 식별자이며 공식 학생/학교 소속이나 관리자 자격을 증명하지 않는다.

## 계정·세션

| 메서드·경로 (`/api/v1` 아래) | 동작 |
| --- | --- |
| POST `/auth/register` | `display_name`, `email`, `password`, 선택 `session_mode`로 학생 계정 생성과 로그인, 201 |
| POST `/auth/login` | 이메일·비밀번호 확인 후 새 세션 발급 |
| GET `/auth/me` | 사용자·역할·활성 학교 범위·권한 버전·절대 만료 시각 |
| POST `/auth/logout` | 현재 서버 세션 무효화·쿠키 삭제, 204 |
| POST `/auth/logout-all` | 본인 서버 세션 모두 무효화, 204 |
| POST `/auth/change-password` | 현재 비밀번호 확인 후 변경·모든 기존 세션 종료·쿠키 삭제, 204 |

- 가입 역할은 항상 `user`. 역할·owner 등 추가 필드는 422. 이메일은 ASCII mailbox
  형식·최대 254자이며 공백 제거·소문자 정규화 후 UNIQUE다. 이름은 공백 제거 후 1~128자,
  신규 비밀번호는 15~128자다. 비밀번호를 정규화하거나 잘라 저장하지 않는다.
- Argon2id (`m=19456 KiB,t=2,p=1`)와 매번 다른 salt를 사용하고 로그인 시 필요한 해시를
  갱신한다. 비밀번호 원문은 DB·로그·명령 인자에 저장하지 않는다.
- 256bit 난수 URL-safe 세션 토큰을 발급하고 DB에는 SHA-256 digest만 저장한다.
  절대 만료는 `AUTH_SESSION_HOURS`(기본 12, 1~72)다. refresh/영구 로그인은 없으며
  만료되면 재로그인한다. 쿠키로 재로그인하면 이전 쿠키 세션을 무효화한다.
- Web은 기본 `session_mode=cookie`: 응답 토큰은 null이며 HttpOnly·SameSite=Strict·Path=/
  쿠키를 설정한다. staging/production은 Secure와 `__Host-unipath_session` 이름을 사용한다.
  local HTTP만 `unipath_session` 이름이다. 쿠키 변경 요청·쿠키 로그인/가입에는 Origin이
  필요하며 `CORS_ORIGINS`에 정확히 일치해야 한다. Web HTTP 클라이언트는 credentials를
  포함한다. 로컬 Web/API는 모두 `localhost`로 접속하고 127.0.0.1과 혼용하지 않는다.
- Windows는 `session_mode=bearer`를 보내고 응답 `access_token`을 실행 중 메모리에만 둔다.
  `Authorization: Bearer ...`로 전송하며 재시작 후 다시 로그인한다. 쿠키용 토큰을 bearer로
  사용할 수 없다. 네이티브 bearer 요청은 Origin 생략을 허용하지만 다른 Origin은 거부한다.
- 로그인은 이메일별 15분 8회, 가입은 15분 3회의 PostgreSQL 원자적 한도다. 실패 요청도
  커밋되며 여러 워커가 공유한다. 공개 nginx는 IP별 로그인 10회/분(burst 10), 가입 3회/분
  (burst 3)을 추가한다. 실패한 로그인은 이메일 부재·비밀번호 오류·정지 모두 같은 401이다.
- 공통 오류 envelope와 no-store 응답을 사용한다. 만료/폐기 401, 권한 403, 중복/버전 409,
  검증 422, 한도 429다. 응답·로그에 비밀번호·토큰·DB 예외/입력을 노출하지 않는다.

비밀번호 변경은 인증된 본인의 `old_password`(1~128자), `new_password`(15~128자)를 받는다.
현재 비밀번호 오류/동일한 새 비밀번호는 422이며 유효 세션을 만료로 처리하지 않는다.
사용자별 15분 5회 한도, 쿠키 Origin 검증을 적용한다. 성공하면 Argon2id 해시·권한 버전을
갱신하고 현재를 포함한 모든 세션을 폐기하므로 새 비밀번호로 다시 로그인해야 한다.
감사에는 변경 행동만 남기며 이메일 발송·비밀번호 재설정·기존 개인 자료 삭제는 수행하지 않는다.

## 역할·학교 범위

| 역할 | 권한 |
| --- | --- |
| `user` | 본인 세션 조회/종료. 관리자 API 접근 불가 |
| `school_admin` | 본인 범위 조회, 활성 범위 안 학사 자료 관리·검토·감사 조회 |
| `super_admin` | 전체 학사 관리, 계정 역할/상태 변경, 학교 범위 부여/회수·감사 조회 |

모든 보호 요청은 DB에서 현재 계정·역할·유효 세션을 확인한다. 학교별 직접 ID 요청에도
활성 범위를 재검증한다. 클라이언트가 보낸 역할/학교 ID로 권한을 부여하지 않으며,
관리자 역할이 학생 개인 기록 열람 권한을 주지 않는다.

| 메서드·경로 (`/api/v1` 아래) | 계약 |
| --- | --- |
| GET `/admin/users?cursor=&limit=` | 슈퍼관리자, UUID cursor·최대 100, `items/next_cursor` |
| PATCH `/admin/users/{id}/role` | `role`, `expected_version` |
| PATCH `/admin/users/{id}/status` | `account_status: active/suspended`, `expected_version` |
| GET/POST `/admin/institutions` | 허용 학교 목록(cursor/최대 100, `query` 검색), 생성은 슈퍼관리자·`name` |
| GET `/admin/institutions/{id}` | 직접 ID 접근에도 범위 확인 |
| GET/POST `/admin/scopes` | 학교관리자는 본인 범위만, UUID cursor/최대 100, 슈퍼관리자는 user_id 필터·부여 |
| POST `/admin/scopes/{id}/revoke` | `expected_version`으로 활성 범위 회수 |

부여 입력은 `user_id`, `institution_id`, `reason`. 활성 일반 계정에 최초 범위를 부여할 때
학교관리자 승격·범위 생성이 한 트랜잭션이다. 활성 중복은 부분 UNIQUE 인덱스로 거부한다.
현재 **학교 전체 범위만** 지원하며 학과/교육과정 하위 범위는 미구현이다. 하위 필드를 받아
전체 학교 권한으로 바꾸지 않는다. 마지막 범위를 회수해도 역할 이름은 유지하되 학교 접근은
차단된다. 다른 역할로 변경하면 기존 범위를 회수한다. 정지는 모든 세션을 폐기하고 재활성화도
이전 세션을 되살리지 않는다. 자신의 역할/상태는 변경할 수 없다. 권한 변경과 최초 관리자
생성은 advisory transaction lock으로 직렬화한다. 수행자·행동·대상·학교·request ID·시각을
감사 테이블에 기록하며 자유 입력 사유·비밀번호·토큰·학생 기록 원문을 감사 로그에 복제하지 않는다.

## 최초 슈퍼관리자

기본 계정/공유 비밀번호/공개 관리자 가입은 없다. 서버에서 마이그레이션 후 운영자가
실제 담당자의 이메일·이름을 지정한다. 비밀번호는 숨겨진 대화형 입력을 두 번 받는다.

```bash
cd backend
uv run --frozen python -m app.operations.users --environment staging \
  --email YOUR_EMAIL --display-name YOUR_NAME
```

자동화는 비밀 파이프로 `--password-stdin`을 사용하며 비밀번호를 셸 인자/로그에 넣지 않는다.
선택 환경 파일만 읽고 셸 DB 환경변수는 무시한다. 기존 계정을 덮어쓰거나 두 번째 최초
관리자를 만들지 않는다. 이후 승격은 인증된 슈퍼관리자 역할 API로 한다. 운영자 복구는 별도다.

## 프론트·자료 경계

- 일반 로그인/가입은 실제 HTTP이며 입력 보존·중복 제출 방지·서버 로그아웃을 제공한다.
  Release에는 샘플 버튼이 없다. 실제 관리자 로그인은 서버의 학사/계정 관리 작업 공간을 사용하고,
  기존 합성 학사 편집기는 debug 샘플 진입에만 남는다.
- Web은 쿠키로 신원을 복원하고 60초 간격/앱 복귀 시 갱신한다. 401이면 로그인으로 돌아가며
  통신 실패를 세션 폐기로 간주하지 않는다. API 권한은 매 요청 서버가 확인한다.
- 실제 일반 계정의 개인 프로필·일정·기록·포트폴리오는 서버 저장이다. 기기 원본은 사용자 UUID별 키로 분리하고
  객체는 생성 당시 계정을 유지해 지연 저장이 다른 계정을 덮어쓰지 않는다. 기존 익명 자료는
  자동 귀속·업로드·삭제하지 않는다. namespace는 암호화/공유 OS 접근 통제를 대신하지 않는다.
- [개인 자료 API](personal.md)와 [학생용 학사 조회](student-catalog.md)는 서버에 구현했다.
  생성 DTO/프론트 전송 adapter와 [프로필·일정 화면 연결/동의 이전](planning-integration.md)을 제공한다. [나머지 개인 기록·구성·문서 화면](personal-workspace-integration.md)도 서버 저장과 동의 이전에 연결했다.
- 이메일 검증/복구·MFA·학교 담당자 심사·자동 실시간 동기화·세션/한도 데이터
  정리 주기는 후속이다. 공식 학적/학교 자격을 검증했다고 표시하지 않는다.

검증은 합성 데이터와 독립 PostgreSQL 스키마로 수행한다. 권한 우회·CSRF·쿠키 속성·토큰
종료/만료·정지·범위 회수·버전/중복·동시 한도와 `alembic check`, Flutter의 입력 보존·역할
진입·계정별 자료 격리를 검사한다. Web/Windows Release 빌드와 실제 Web 흐름도 확인한다.

근거: [OWASP 비밀번호 저장](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html),
[세션](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html),
[CSRF](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html),
[argon2-cffi API](https://argon2-cffi.readthedocs.io/en/stable/api.html).
