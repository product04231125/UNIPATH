# 관리자 학사 기준 데이터 API

2026-10-18 구현. 계약 원본은 [OpenAPI](openapi.json)다. 모든 경로는 `/api/v1/admin` 아래이며
[계정·세션](authentication.md)의 현재 신원과 학교 전체 관리 범위로 보호한다.

## 구현 범위

| 컬렉션 | 입력 |
| --- | --- |
| `institutions` | 이름, 선택 국가 코드(대문자 2자), 공식 HTTP(S) URL |
| `departments` | 학교 UUID, 이름, 코드 |
| `curricula` | 학교·학과 UUID, 이름, 적용 연도(1000~9999) |
| `courses` | 학교 UUID, 이름, 코드, 0~100 학점(소수 3자리 이내), 선택 `classification_id`·`track_id`(과목 기본 분류) |
| `curriculum-courses` | 학교·교육과정·과목 UUID, 이름, 이수구분 `major/general/other`, boolean `required`, 선택 `classification_id`·`track_id` |
| `classifications` | 학교 UUID, 이름, `kind`, 세부분류의 상위 `parent_id`, 선택 설명·학교 공식 코드, `status=active/inactive` |
| `rule-sets` | 학교 UUID, 선택 학과·교육과정 UUID, 이름, 선택 시작·종료일 |
| `rules` | 묶음과 같은 범위/기간, 선택 묶음 UUID, 규칙 종류, 조건 설명, 선택 출처 URL |
| `documents` | 범위/기간, 이름, 원문 HTTP(S) URL, 종류, 선택 관련 규칙 UUID |

학교 생성/수정/삭제는 슈퍼관리자만 수행한다. 학교관리자는 활성 학교 전체 범위 안의
학과·교육과정·과목·요건·문서만 관리한다. 학과/교육과정 하위 관리 범위는 아직 지원하지 않는다.
학생 계정에는 관리자 API 접근을 허용하지 않는다. 관리자 권한이 학생 개인 기록 접근을 뜻하지 않는다.

`institutions`를 제외한 위 컬렉션은 다음 동작을 제공한다. 학교에도 기존 목록/생성/상세와
새 수정/삭제/참조 확인을 제공한다.

- `GET /{collection}`: `institution_id`, `query`, `cursor`, `limit`(1~100),
  검토 자료의 `status=draft/applied` 필터. 응답은 `items`, `next_cursor`다.
- `POST /{collection}`: 서버 UUID와 버전을 포함한 생성 결과, 201.
- `GET /{collection}/{id}`: 권한 검증 후 상세, 200.
- `PATCH /{collection}/{id}`: 입력 전체와 `expected_version`을 보내는 교체 수정, 200.
  선택 필드를 생략하면 기본값/비워진 값으로 저장하므로 일반적인 부분 PATCH로 취급하지 않는다.
- `DELETE /{collection}/{id}?expected_version=N`: 버전·권한·참조를 다시 검사한 후 204.
- `GET /{collection}/{id}/references`: 접근 가능한 연결 참조의 `items`, `total`.

읽기/변경은 서버에서 현재 계정 상태와 범위를 확인한다. 변경은 권한 변경과 같은
transaction advisory lock 안에서 세션과 역할을 다시 읽는다. 코드 중복, 같은 교육과정 과목
중복, 다른 학교 연결은 409다. 학교/학과/교육과정 소속은 생성 뒤 이동하지 않으며 새 항목으로
등록한다. 소속은 복합 FK로도 검증한다. 참조 확인 후 연결이 추가돼도 삭제 트랜잭션에서 다시 차단한다.

학교는 참조/활성 관리 범위가 없을 때 삭제 표시(`deleted_at`)하고 일반 목록과 상세에서 숨긴다.
이전 감사와 회수된 관리 범위의 FK를 보존한다. 개인 프로필이 학과/교육과정을 참조하면 학생 식별자·내용·인원 수 없이 보호된 참조 표시만
반환하고 삭제를 차단한다. 다른 항목은 참조 없는 초안만 삭제하며
적용본은 항상 보존한다. 이름/코드는 기존 보관 자료와 충돌할 수 있으며 조용히 재사용하지 않는다.

## 학교별 분류

`classifications`는 학교마다 따로 관리하는 이수구분(`category`), 세부분류(`subcategory`),
이수 경로(`track`)다. 분류의 정체성은 서버가 만든 UUID다. 이름·설명은 자유 입력이며
이름이 같아도 연결하거나 합치지 않는다. 이름을 바꿔도 ID와 기존 연결은 그대로다.
분류 코드는 요구하지 않고, 학교 공식 코드가 따로 있을 때만 `official_code`에 적는다.
필수/선택은 분류가 아니라 기존 `curriculum-courses.required`를 쓴다.

- 세부분류는 같은 학교 이수구분 하나를 `parent_id`로 가져야 한다. 다른 종류는 `parent_id`가 없다.
  `kind`는 생성 뒤 바꿀 수 없다(409). 다른 학교 분류 참조는 409이고 복합 FK로도 막는다.
- 과목과 교육과정 연결은 `classification_id`(이수구분 또는 세부분류)와 `track_id`(이수 경로)를
  가질 수 있다. 종류가 맞지 않으면 409다.
- 실제 적용 값은 **교육과정 연결의 값이 우선**하고, 없으면 과목 기본값이다. 연결 응답의
  `effective_classification_id`·`effective_track_id`가 적용 값이고 `classification_source`·`track_source`가
  출처(`curriculum_course`/`course`/null)다. 과목 기본값을 바꾸면 값이 없는 연결에 바로 반영된다.
- 사용 중지(`status=inactive`)한 분류나 상위가 사용 중지된 세부분류는 새로 연결할 수 없다(409).
  이미 연결된 항목은 값을 유지하고 다른 필드를 수정할 수 있다. 연결된 분류와 하위 세부분류가 있는
  이수구분은 삭제할 수 없고, 참조 확인 API로 연결된 과목·연결을 보여 준다.
- 과목·연결 수정에서 `classification_id`·`track_id`를 **생략하면 기존 값을 유지**하고, `null`을 보내면
  해제한다. 다른 필드는 기존처럼 전체 교체다. 분류를 모르는 이전 화면이 연결을 지우지 않게 하기 위함이다.
- 관리자 목록은 `status=active/inactive`로 거를 수 있다. 감사 기록의 `kind`는 `classification`이다.

학생 프로필의 이수 경로를 분류 ID로 바꾸는 것은 후속 단계다. 현재 프로필 `track`은 문자열이며,
RAG 적용 범위와 공식 규칙도 이 문자열로 맞춘다.

## 과목 학과 소속

과목은 선택 `department_id`(같은 학교 학과)로 소속 학과를 가진다. `null`은 학교 공통 과목이다.
기존 과목은 모두 `null`로 시작한다. 다른 학교 학과는 409이고 복합 FK로도 막는다.

- 수정에서 `department_id`를 **생략하면 기존 값을 유지**하고, `null`이면 공통 과목으로 바꾼다.
  다른 학과로 옮길 수 있다(과목 아래에 학과 범위를 가진 항목이 없기 때문이다).
- 과목이 속한 학과는 삭제할 수 없고, 학과 참조 확인 API에 그 과목이 나온다.
- 학생 카탈로그 `GET /catalog/courses?department_id=`는 **그 학과 소속 과목과 그 학과 교육과정에
  연결된 과목**을 함께 준다. 공통 과목은 연결돼 있을 때만 나온다. `curriculum_id`를 주면 지금처럼
  그 교육과정에 연결된 과목만 준다.

## 과목·연결 통합 저장

`POST /admin/course-placements`는 새 과목과 그 교육과정 연결을 **한 트랜잭션**으로 만든다.
어느 한쪽이라도 실패하면 아무것도 저장하지 않는다.

```json
{
  "client_id": "<제출마다 새로 만든 UUID>",
  "course": {"institution_id": "…", "name": "…", "code": "…", "credits": "3",
             "department_id": null, "classification_id": null, "track_id": null},
  "link": {"curriculum_id": "…", "category": "major", "required": true,
           "classification_id": null, "track_id": null, "name": null}
}
```

- 연결 `name`을 비우면 과목 이름을 쓴다. 검증은 각각 `POST /admin/courses`, `/admin/curriculum-courses`와
  같다(학교 범위, 분류 종류·사용 상태, 코드 중복 409).
- 성공은 201이고 `course`, `curriculum_course`(적용 분류 포함), `replayed=false`를 준다.
- **같은 `client_id`와 같은 본문으로 다시 보내면** 새로 만들지 않고 처음 결과를 200, `replayed=true`로
  준다. 본문이 다르면 409다. `client_id`는 관리자 계정마다 따로 관리한다.
- 응답을 받지 못했으면 `GET /admin/course-placements/{client_id}`로 확인한다. 200이면 저장된 것이고,
  404면 저장되지 않았으니 같은 `client_id`로 다시 보내면 된다.
- 만든 과목이나 연결을 나중에 삭제하면 해당 필드가 `null`로 돌아온다. 같은 `client_id`로 다시 만들지 않는다.
- 감사 기록은 따로 저장할 때와 같이 `academic:course:create`, `academic:curriculumCourse:create` 두 건이다.
- 이미 있는 과목을 다른 교육과정에 연결하거나 수정하는 것은 기존 API를 쓴다.

## 검토·새 버전

`rule-sets`, `rules`, `documents`는 다음 동작을 제공한다.

- `POST /{collection}/{id}/apply`, body `expected_version`: 초안을 검토·고정, 200.
- `POST /{collection}/{id}/drafts`, body `expected_version`: 적용본에서 새 UUID의 초안 생성, 201.

`version`은 수정 충돌 검사용이며 매 변경 증가한다. `revision`은 화면의 문서/기준 판번호다.
동일 `lineage_id` 안의 판번호는 중복되지 않으며 초안도 하나만 허용한다. 적용본은 수정/삭제할 수 없다.
묶음 소속 요건은 개별 적용/버전 생성하지 않는다. 묶음 적용은 하위 요건을 같은 트랜잭션에서
고정하고, 새 묶음 초안은 기존 하위 요건을 새 UUID로 복제한다. 하위 요건 수정은 부모의
충돌 버전도 올린다. 묶음 기간 수정은 초안의 하위 요건 기간과 버전도 함께 갱신한다.

**현재 `rules.definition`은 검토한 사람의 조건 설명이다. 실행 가능한 Rule Engine
조건 JSON으로 해석하지 않는다.** 종류는 `credits/required_course/volunteer/thesis/certificate/custom`다.
실행 조건은 별도 [공식 실행 규칙 API](rule-programs.md)로 등록·검토한다.
공식 기록 매핑과 판정 HTTP API는 후속이다. 기존 메타데이터 편집으로 실행 조건을 덮어쓰지 않는다.

문서 종류는 `academic/graduation/other`다. 원문 URL과 메타데이터를 저장하며 URL을 서버에서
자동 다운로드하지 않는다. 추출 본문·청크·관리자 검토는 별도 [학교 지식 API](school-knowledge.md)에
구현했다. 이 경로 자체는 파일 업로드·임베딩·학교 담당자 외부 신원 확인을 수행하지 않는다.
`applied`가 RAG의 `approved/verified/eligible_for_official_answers`를 부여하지 않는다.

## 계정·감사 연결

- `PATCH /users/{id}/access`: `role`, `account_status`, `expected_version`을 한 번에 변경한다.
  기존 `/role`, `/status`도 유지한다. 자신의 계정 변경은 금지하며 정지는 세션을 폐기한다.
- `POST /scopes/{id}/revoke`: 기존 `expected_version`에 선택 `reason`(최대 500자)을 추가했다.
  회수 사유는 범위의 `revocation_reason`에 저장하며 자유 입력을 감사 로그에 복제하지 않는다.
- `GET /audit-logs`: 학교·UUID cursor·limit 필터와 `items/next_cursor`. 다음 조건을 AND로 더 받는다.
  - `target_id`, `actor_id`: 대상·수행자 UUID 일치.
  - `kind`: 응답의 `kind`와 같은 값(`institution`, `department`, `curriculum`, `course`,
    `curriculumCourse`, `ruleSet`, `rule`, `document`, `classification`, `scope`, `account`). 모르는 값은 422.
  - `action`: 전체 행동 문자열 일치(예: `academic:course:update`, `scope_granted`).
  - `occurred_from`, `occurred_to`: 시간대가 있는 ISO 8601 시각(`Z` 또는 `+09:00`). 시작은 포함하고
    끝은 제외한다. 시간대가 없거나 시작이 끝보다 늦지 않으면 422.
  - 정렬과 cursor는 기존처럼 기록 UUID 순이다. 조건을 바꾸면 cursor를 처음부터 다시 쓴다.
  - 감사 기록은 성공한 변경만 남기므로 결과 필터는 없다. 이름·설명 같은 문자열은 기록하지 않아
    텍스트 검색도 없다. 대상 이름 검색은 목록 API로 ID를 찾은 뒤 `target_id`로 거른다.
  - 학교관리자는 필터와 관계없이 자신의 활성 학교 범위 기록만 받는다.
  슈퍼관리자는 전체, 학교관리자는 현재 활성 범위의 학교 메타데이터만 조회한다.
  성공한 변경을 기록하며 실패 요청의 영구 감사 저장은 구현하지 않았다.

감사에는 수행자·대상·종류·행동·학교·시각·요청 ID를 반환한다. 비밀번호, 토큰, 학생 기록,
조건 설명이나 원문은 포함하지 않는다. 감사 수정/삭제 API는 없다.

## 프론트 연결과 후속

실제 관리자는 `RemoteAdminRepository`로 위 API를 사용한다. 동일 AuthApi의 Web 쿠키와
Windows 메모리 토큰을 공유한다. 전송 DTO는 UUID/숫자/boolean/날짜로 변환하며 화면의
문자열 Map을 그대로 보내지 않는다. 모든 cursor 페이지를 읽은 목록에 학교 선택과 로컬
검색/필터를 적용한다. 서버 검색/필터도 API로 제공하며 대규모 목록의 화면 페이지 처리는 후속이다.

저장 응답을 받으면 결과를 반영하고 목록을 갱신한다. 이후 갱신 실패는 저장 재전송 없이
`저장은 완료했지만 목록을 새로 읽지 못했습니다`와 재조회를 제공한다. 응답을 받지 못한
생성 요청의 idempotency key/중복 재시도 정책은 후속이며 먼저 목록을 확인해야 한다.
일반 오류는 입력을 보존하며 401/403에는 관리자 캐시를 비운다. 세션/권한 버전이 달라지면
편집 화면을 다시 연다. debug 샘플만 FakeAdminRepository를 사용한다.

개인 프로필·수강·봉사·일정·포트폴리오 서버 저장은 [개인 자료 API](personal.md),
학생 조회는 [학생 카탈로그](student-catalog.md), 비밀번호 변경은 [인증 API](authentication.md)로
구현했다. 별도 학교 지식 API에 문서 검토·DB 검색을 연결했다. 기존 개인 화면의 서버 전환,
공식 졸업감사, 실제 RAG 생성기·문서 검토/검색 화면, SSO·이메일 검증·
비밀번호 재설정은 후속이다.
