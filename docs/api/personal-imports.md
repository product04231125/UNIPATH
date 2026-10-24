# 계정별 개인 자료 일괄 이전

`POST /api/v1/me/personal-imports`는 사용자가 확인한 본인 계정의 로컬 자료를 한 트랜잭션으로
추가한다. 중간 실패 시 프로필·자료·순서 참조·생성 영수증·이전 영수증을 모두 취소한다.
현재 세션의 UUID가 실제 소유자이며 관리자도 다른 사람에게 전송할 수 없다. 기존
[개인 자료 API](personal.md)의 검증·관계·재시도 로직을 함께 사용한다.

Flutter의 학업 프로필·일정은 [서버 저장과 동의 후 기기 자료 이전](planning-integration.md)에 연결했다. [다른 개인 자료 10종](personal-workspace-integration.md)의 동의·변환·참조 보존·서버 저장소 전환도 연결했다. 서버는 실제 로컬 저장소를 볼 수 없으므로 클라이언트가
계정 namespace와 자료 권한을 검증해야 한다. 익명·다른 계정·debug fixture를 자동 귀속하거나
로컬 원본을 지우지 않는다.

## 요청과 범위

- `import_id`: 한 번 생성하고 재시도 때 유지할 UUID.
- `source_owner_id`: 자료가 속한 현재 계정 UUID. 세션과 다르면 403이며 소유권 부여 수단이 아니다.
- `consent_confirmed`: 엄격한 boolean true. 문자열·숫자·false는 422다.
- `profile`: 선택 개인 프로필. 아직 저장된 서버 프로필이 없을 때만 초기화한다. 기존 프로필은
  409로 보호하며 별도 버전 PATCH로 수정한다.
- `events`, `course_records`, `activity_records`, `experience_records`, `credential_records`,
  `achievement_records`, `personal_curricula`, `personal_curriculum_courses`,
  `personal_graduation_rules`, `portfolio_compositions`, `application_documents`: 타입이 있는 배열.
  생략은 빈 배열이며 기존 서버 목록을 삭제하지 않는다.

각 항목은 `client_id`가 필수다. 모든 참조 대상도 같은 요청에 포함한다. 이전된 의존 자료를
동일 생성 내용으로 다시 포함하면 기존 ID를 재사용할 수 있다. 컬렉션당 100개·전체 500개·
구성/지원 문서의 순서 참조 전체 2000개, 원본과 정상화된 JSON은 2 MiB 이내다.
자료가 없으면 프로필 초기화가 필요하다. 큰 자료는 의존 자료를 포함한 별도 묶음으로 나눈다.
Nginx가 원본 2 MiB 초과를 거절하면 공통 `HTTP_ERROR` envelope·request ID·no-store와 413을
반환한다. 파싱 후 정상화된 자료의 한도 위반은 공통 422이며 어느 경우에도 부분 저장하지 않는다.
HTTPS 바깥 게이트웨이와 앱 프록시의 한도를 함께 적용한다. 배포 설정은
[릴리스 문서](../releases.md)를 따르며 두 단계 프록시 테스트가 CI에 포함된다.

## 로컬 참조

기존 생성 DTO와 같은 값을 검증하지만 다음 관계는 로컬 client UUID로만 받는다.
일반 CRUD의 서버 UUID 필드명으로 보내면 422다.

| 이전 항목 | 로컬 참조 필드 |
| --- | --- |
| 개인 교육과정 과목 | `curriculum_client_id`, 선택 `course_record_client_id` |
| 개인 규칙 | `curriculum_client_id`, 선택 `curriculum_course_client_id` |
| 개인 규칙의 `related_record` | `{kind, client_id}` |
| 구성/지원 문서의 `sources` | 순서가 있는 `{kind, client_id}` 배열 |

kind는 기존 `course/activity/experience/credential/achievement`다. 구성은 achievement만,
지원 문서는 achievement/experience만 허용한다. 중복 식별자·빠진 참조·다른 개인 교육과정의
과목을 연결한 규칙을 쓰기 전에 거부한다. 학교 카탈로그 UUID를 개인 참조로 해석하지 않는다.
프로필의 선택 카탈로그 ID는 기존 소속 검증을 따르며 공식 학적이 아니다.

일정은 offset이 명시된 시각과 확인된 IANA `time_zone`이 필요하다. offset 없는 기존 시각에
Z를 붙이거나 시간대를 추정하지 않는다. 화면에서 원래 시간대를 확인한 뒤 변환한다.
원 성적·승인 상태 설명·개인 규칙 설명을 학교 확정값이나 실행 조건으로 승격하지 않는다.

## 커밋·재시도·이력

201 응답은 `import_id`, `owner_id`, `committed_at`, `record_count`,
`profile_version_at_import`, `mappings`, `replayed`, `origin=personal`, `official=false`다.
mapping은 `resource`, `client_id`, 서버 `record_id`, `version_at_import`,
`outcome=created/reused`다. 프로필 초기화만 있으면 record_count는 0이다.

현재 세션·계정 상태를 신원 변경과 같은 transaction lock에서 재확인한다. 기존 생성 영수증은
정확한 생성 내용만 재사용하며 현재 편집 내용을 덮어쓰지 않는다. 해당 자료가 삭제됐으면 새
이전 요청도 409다. 같은 client/import UUID를 다른 계정에서 쓰더라도 소유자와 대응표는 별도다.

같은 `(owner, import_id)`·같은 정상화된 요청은 이전 커밋 영수증만 반환하며 동시 요청도
커밋은 한 번이다. 같은 import_id의 내용 변경은 409다. 컬렉션 항목의 나열 순서는 지문에
영향을 주지 않지만 sources 순서는 의미가 있으므로 보존한다. 전송한 원본 요청·ID를 유지한다.

영수증은 이전 당시 이력이다. 이후 수정/삭제된 자료의 존재나 최신 버전을 보증하지 않는다.
삭제 후 재시도도 과거 ID를 반환할 뿐 되살리지 않는다. 현재 상태는 개별 GET으로 확인한다.
시간 초과 뒤에는 같은 요청을 재전송하거나 `GET /api/v1/me/personal-imports/{import_id}`로
확인한다. GET 404만으로 진행 중 트랜잭션의 실패를 단정하거나 새 import_id를 만들지 않는다.

조회는 본인만 가능하고 다른 사람·관리자는 미존재와 같은 404다. 응답은 no-store다.
영수증에는 UUID 대응·당시 버전·결과·시각·요청 지문만 보관하고 원문을 중복 저장하지 않는다.
자동 만료 정책은 없으며 기존 생성 영수증과 함께 재시도에 의한 재생성을 막는다.

## 프론트 연결

`personal_import_models.dart`의 16개 DTO와 `PersonalImportApi`를 사용한다. API 객체는 한 계정에
묶고 계정 전환/로그아웃 시 폐기한다. adapter는 전송 전 동의·source_owner 일치와 응답의
소유자·이전 ID·대응표 중복·개수·버전·개인 표시를 검증한다. 저장소를 읽거나 원본을 업로드·
삭제하는 부수 효과는 없다. UI 연결 시 검토·자료 변환·시간대·원본 보존·실패 재개·충돌 해결을
함께 구현하며 영수증만으로 로컬 원본을 지우지 않는다.
