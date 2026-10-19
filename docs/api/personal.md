# 학생 개인 자료 API

2026-10-19 구현. prefix는 `/api/v1/me`, 모든 요청에 기존 로그인 세션이 필요하다.
계약 원본은 [OpenAPI](openapi.json)다. **API는 서버에 저장하지만 현재 Flutter 개인 화면은
여전히 로컬 저장소를 사용한다.** 자동 업로드·계정 자동 귀속·로컬 삭제는 수행하지 않는다.

## 소유권과 공통 계약

- `owner_id`는 서버 세션으로 결정한다. 일반/학교관리자/슈퍼관리자 모두 자기 자료만
  접근한다. 다른 소유자의 ID·참조는 미존재와 같은 404이며 관리 권한으로 우회하지 못한다.
- 본문은 명시적 DTO만 허용한다. 요청의 owner·역할·공식 검증 플래그는 422다.
  응답의 `origin=personal`, `official=false`는 학교 학적·승인·공식 성적을 의미하지 않는다.
- 아래 11개 컬렉션에 `GET/POST`, `GET/PATCH/DELETE /{id}`와 `GET /{id}/references`를 제공한다.
  생성 201, 읽기/수정 200, 삭제 204. 참조 있는 삭제·중복 생성 키·버전 충돌은 409다.
- 공통 생성 필드는 `title`(1~128자), `detail`(기본 빈 문자열, 최대 8000자), 선택 `client_id` UUID다.
  서버가 `id`를 생성하고 owner·version·생성/수정 시각을 반환한다. 서버 ID와 client ID는 구별한다.
- PATCH는 **부분 수정**이다. `expected_version`과 바꿀 필드만 보낸다. 생략은 유지하며
  nullable 필드의 null만 제거를 의미한다. 필수 필드에 null을 보내면 422다.
  수정 시 생성 DTO 전체로 관계·기간을 다시 검증한다. `client_id`는 변경할 수 없다.
- 목록은 UUID `cursor`, `limit`(1~100), 제목 부분 검색 `query`, 정확한 `client_id` 필터와
  `items/next_cursor`를 제공한다. 모든 페이지를 읽어야 전체 목록이다. 응답은 no-store다.
- 관계는 같은 소유자로 제한하며 DB의 `(id, owner_id)` 복합 FK도 적용한다.
  개인 교육과정 과목과 규칙의 교육과정 일치도 복합 FK로 검사한다.
- 수정은 역할·정지 변경과 같은 신원 잠금 안에서 세션을 다시 검사한다. 감사 관리자 API에
  개인 기록 내용·목록을 노출하지 않으며 입력·비밀번호·토큰을 오류에 포함하지 않는다.

## 컬렉션

| 경로 | 공통 필드 외 주요 입력 |
| --- | --- |
| `/events` | `starts_at`, `ends_at`(시간대 offset 필수), `time_zone`(IANA), `category=academic/personal/activity/deadline` |
| `/course-records` | `term`, `category`, `credits`(0 초과~100, 소수 3자리), 선택 `section/course_code/grade`, `completion=planned/in_progress/recorded` |
| `/activity-records` | 기관·역할, 시작/종료일, `reported_hours`, 관찰한 `approved_hours/approval/observed_on` |
| `/experience-records` | `experience_type`, 기관·역할·기간·결과, 자유 서술 `status_label` |
| `/credential-records` | `provider/level`, 취득/만료일, `status_label`, `evidence_url` |
| `/achievement-records` | `achievement_type`, 필수 `role/result`, 기간·링크, 개인 논문 유형/상태 설명/원 성적/확인일 |
| `/personal-curricula` | 개인 `school/department`, 정수 `admission_year/curriculum_year`, 선택 `evidence_url` |
| `/personal-curriculum-courses` | `curriculum_id`, 선택 `course_record_id`, 과목 코드·이수구분·양수 학점, boolean `required` |
| `/personal-graduation-rules` | `curriculum_id`, 선택 `curriculum_course_id`, `rule_type`, `scope=institution/department/curriculum`, 필수 `condition`, 선택 수치·기간·출처·`related_record` |
| `/portfolio-compositions` | 사용 의도 `audience=private/application/public_review`, boolean `reviewed`, 순서 있는 `sources` |
| `/application-documents` | 필수 `target/role/document_type`, 선택 `body`(최대 32000자), 순서 있는 `sources` |

날짜는 실제 `YYYY-MM-DD`만 받으며 숫자 timestamp나 날짜/시각 혼용을 허용하지 않는다.
기간·취득/만료·유효기간은 역전을 거부한다. 숫자는 유한한 0 이상이며 학점은 0을 허용하지 않는다.
URL은 로그인 정보가 없는 HTTP(S) 링크이며 서버에서 가져오거나 학교 증빙을 검증하지 않는다.
자유 서술 상태는 `status_label` 등으로 보존하며 기계적 승인 상태로 해석하지 않는다.

`approved_hours > 0`을 기록하려면 사용자가 관찰한 `approval=approved`와 `observed_on`이
필요하다. 이것도 **사용자 입력**이며 서버의 봉사 승인·검증된 실적이 아니다.
개인 `condition`·`rule_type`·`required_value/current_value`는 저장용 설명/관찰 값이다.
실행 코드나 공식 졸업 판정 조건으로 자동 해석하지 않는다.

## 프로필과 일정

- `GET /planning-profile`: 미저장은 기본값과 `version=0`, 시각 null을 반환한다.
  GET으로 빈 DB 행을 생성하지 않는다.
- `PATCH /planning-profile`: 최초 `expected_version=0`, 이후 현재 버전으로 부분 수정한다.
  학교/학과 표시명·입학연도(1900~현재+1)·이수경로·개인 계획 학년·주 시작 요일을 저장한다.
  선택 `institution_id/department_id/curriculum_id`는 등록된 소속 관계를 검사하지만 공식 학적을
  증명하지 않는다. 자유 입력 이름으로 FK를 자동 추론하지 않는다. 선택 중인 학과/교육과정의
  삭제는 FK로 차단하며 관리자 참조 조회에는 학생 정보가 없는 보호된 참조 표시만 반환한다.
  이후 학교가 보관 처리돼도 기존 개인 선택은 보존하고 주 시작 요일 등 무관한 부분 수정은
  허용한다. 보관된 학교를 새로 선택할 수는 없으며 이 선택은 관리 권한을 부여하지 않는다.
- `/events?ends_after=...&starts_before=...`는 해당 순간 구간과 겹치는 일정을 반환한다.
  종료/시작 경계는 각각 `end > ends_after`, `start < starts_before`다. 시각은 PostgreSQL
  timestamptz로 보존하고 표시용 IANA time_zone을 함께 보존한다. UUID 페이지 순서는 시간순이 아니다.

## 개인 관계와 초안 보존

`related_record`와 `sources`의 참조는 `{kind, record_id}`다. kind는
`course/activity/experience/credential/achievement` 중 하나이며 record_id는 **서버 ID**다.
구성의 sources는 achievement만, 지원 문서는 achievement/experience만 허용한다.
중복을 거부하고 최대 100개를 순서대로 한 트랜잭션에서 교체한다.

구성·지원 문서 삭제는 연결 행만 제거하며 원 성과/경험을 지우지 않는다. 참조 중인 원본의
삭제는 차단한다. 성과 수정은 이를 참조하는 구성의 reviewed를 false로 만들고 버전을 올린다.
구성 내용·순서 변경도 명시적 새 reviewed 확인이 없으면 검토 표시를 초기화한다.
원본 수정으로 작성된 지원 문서 본문을 자동 덮어쓰지 않는다.
audience와 reviewed는 사용 의도/개인 확인 기록이며 실제 공개·공유·제출 권한이 아니다.

## 재시도와 기존 로컬 자료 이전

생성 시 안정적인 client_id를 보내면 `(owner, collection, client_id)`별 생성 영수증을
같은 트랜잭션에 저장한다. 같은 본문의 동시/반복 요청은 같은 자료를 반환하며 중복 생성하지 않는다.
본문이 달라지면 409다. 이미 수정한 자료의 재시도는 현재 버전을 반환하므로 원래 생성 응답과
동일한 snapshot을 보장하지 않는다. 자료 삭제 뒤에도 영수증이 남아 같은 생성 재시도가 자료를
되살리지 않으며 409다. 영수증에는 원문 대신 SHA-256 지문·식별자만 저장한다. client_id를
생략한 생성은 이 보장을 제공하지 않는다. 현재 영수증 자동 만료/정리 정책은 없다.

프론트 이전 adapter는 사용자 확인 후 **현재 계정의 로컬 자료만** 다음 순서로 전송해야 한다.

1. 원본을 보존하고 기존 UUID를 client_id로 사용한다. 서버 ID 대응표를 계정별로 저장한다.
2. 개인 교육과정과 수강/활동/경험/자격/성과를 먼저 저장하고 응답의 서버 ID를 확보한다.
3. 개인 과목 연결, 개인 규칙, 구성/지원 문서 순서로 참조를 서버 ID로 치환한다.
4. 실패 시 원본을 지우지 않고 client_id 조회와 같은 본문 재시도로 재개한다. 바뀐 내용은
   현재 version을 읽은 PATCH로 저장한다. 익명/다른 계정 자료를 자동 귀속하지 않는다.
5. 로컬 일정의 offset 없는 시각은 원래 시간대 확인 후 변환해야 한다. 임의로 Z를 붙이거나
   서버 시간대로 해석하지 않는다. 기존 자료를 이전하는 동의/변환 UI와 저장소 연결은 후속이다.
   `frontend/lib/features/api/`의 공통 AuthApi 전송 adapter·생성 DTO는 사용할 수 있다.

주요 프론트 매핑: camelCase는 snake_case, 수강 상태 `계획/수강 중/이수 기록`은
`planned/in_progress/recorded`, 개인 필수 여부는 boolean, 개인 scope 한글 값은 위 enum으로
변환한다. 로컬 `portfolio` 기록은 achievement-records, `type`은 자원별
experience_type/achievement_type/document_type, 자유 status는 status_label이다.
포트폴리오 description은 detail, `publicReview`는 public_review이며 기존 `portfolio/id`
참조는 achievement와 서버 ID로 변환한다. 로컬 문자열 Map을 그대로 전송하지 않는다.
