# 공식 실행 규칙 등록·검토·선택

모든 경로는 `/api/v1` 아래에 있고 로그인한 현재 세션을 사용한다. 메타데이터의 자유 입력
`definition`·개인 자료의 `current_value`를 실행식으로 해석하지 않는다. 기존 학사 편집 API와
분리한 실행본을 적용된 `rule_set_id` 또는 독립 `rule_id` 하나에 연결한다.
이 계약은 **실행 규칙 등록과 선택**이며 공식 졸업 판정 HTTP API가 아니다.
학교 확정 성적·활동 자료의 제공 방식과 전체 규칙 완전성 확인은 아직 미정이다.

## 관리자 경로

슈퍼관리자는 전체 학교, 학교 관리자는 활성 권한을 가진 학교에서만 조작한다.
모든 변경은 현재 세션·역할·범위를 권한 변경과 같은 transaction lock에서 재확인한다.

| 메서드·경로 | 동작 |
| --- | --- |
| `GET /admin/rule-programs` | 학교·원본 규칙·상태·UUID cursor로 목록 조회 |
| `POST /admin/rule-programs` | 적용 메타데이터 버전에 연결한 실행 초안 생성 |
| `GET /admin/rule-programs/{id}` | 조건·근거·참조 snapshot·누락 요건·현재 사용 가능 여부 |
| `PUT /admin/rule-programs/{id}` | 초안 조건과 적용 연도·경로 전체 교체 |
| `POST /admin/rule-programs/{id}/approve` | 명시적 전체 검토 후 불변 승인 |
| `POST /admin/rule-programs/{id}/revoke` | 사유를 남기고 승인 회수 |
| `DELETE /admin/rule-programs/{id}?expected_version=N` | 초안만 삭제 |

생성은 `expected_source_version`, 적용 입학연도 구간, `tracks`, `rules`를 받는다.
원본 규칙 집합과 독립 규칙 중 하나만 지정한다. 집합 하위 요건을 독립 규칙으로 중복 등록하지
않는다. 학교·학과·교육과정·이름은 원본에서 가져온다. 교체·승인·회수·삭제는 실행본의
`expected_version`을 확인하고 불일치는 409다. 승인본은 수정·삭제할 수 없으며 회수는
되돌리지 않는다. 수정은 별도 초안·새 메타데이터 적용본을 사용한다.

입학연도는 1000–9999, 연도 구간은 최대 200년, 이수경로는 중복 없는 1–32개다.
한 집합은 최대 100개 요건, 각 요건은 근거 청크 1–8개, 실행본 전체는 최대 500개 근거와
500개 과목·자격증 참조를 갖는다. 초안은 일부 조건을 생략할 수 있으나 승인 시 원본의
모든 요건을 정확히 포함해야 한다.

## 닫힌 실행 조건

각 항목은 `rule_id`, 원본 요건의 `expected_version`, `condition`, `evidence_chunk_ids`다.

| 메타데이터 종류 | `condition.kind` | 조건 |
| --- | --- | --- |
| `credits` | `minimum_credits` | `minimum`, 선택 `category` |
| `required_course` | `required_courses` | `courses`: 과목 UUID·버전·선택 최소 학점/평점·평점 비교 척도 |
| `volunteer` | `minimum_volunteer_hours` | `minimum` |
| `certificate` | `any_certificate` | `certificates`: 자격증 마스터 UUID·버전의 대안 목록 |
| `thesis` | `thesis` | `thesis_type`, `requires_approval`, `accepted_grades` |
| `custom` | `manual_review` | `instruction`; 자동 충족으로 계산하지 않음 |

과목은 같은 학교여야 하고 평점 임계값에는 비교 척도가 함께 있어야 한다. 자격증은 활성
발급기관의 활성 마스터여야 한다. 과목·자격증은 ID와 검토 당시 버전·코드·이름을 별도 FK
참조에 보존한다. 이후 이름 변경은 승인 당시 표시를 바꾸지 않는다. 학생의 자격증 보유·
활동 승인 여부는 이 마스터 등록으로 만들어지지 않는다.

## 근거와 승인

근거는 [학교 지식 검토](school-knowledge.md)에서 승인된 본문 청크 UUID다.
클라이언트가 보낸 URL·페이지·제목을 근거로 저장하지 않는다. 같은 학교이며 대상보다 넓거나
같은 학과·교육과정 범위여야 한다. 빈 페이지·경고가 있는 청크·다른 연도/경로·회수된 문서는
사용할 수 없다. 각 근거 청크가 실행본의 모든 입학연도와 이수경로를 포함해야 한다.
연도별 조건이 다르면 실행본을 구분한다. 원본 문서와 연결 규칙의 적용 기간 교집합을 사용한다.

승인은 `expected_version`, `review_note`와 다음 네 개의 엄격한 참 값을 요구한다.

- `conditions_verified`: 수치·종류·비교 조건 검토
- `sources_verified`: 출처 검토
- `applicability_verified`: 학교·학과·교육과정·연도·경로 검토
- `complete_source_context_verified`: 예외·부칙을 포함한 전체 원본 문맥 검토

이는 권한 있는 사람의 검토 확인이다. 서버가 PDF 의미를 자동으로 검증했다고 주장하지 않는다.
동일 원본에 대해 연도·이수경로·유효기간이 겹치는 승인 실행본은 409로 거절한다.
출처 회수·새 적용본·유효기간 만료 시 기존 승인은 이력에 남지만 현재 공개 선택에서 제외한다.

## 로그인 사용자 조회

`GET /catalog/rule-programs`는 `institution_id`, `department_id`, `curriculum_id`,
`admission_year`, `track`을 모두 요구한다. `on`은 선택 날짜이며 기본값은 UTC 오늘이다.
선택 문맥의 실제 소속 관계를 검증하고 학교·학과·교육과정의 적용 집합과 독립 요건을 모두
수집한다. 최신 적용 메타데이터에 실행본이 없으면 이전 승인으로 되돌아가지 않는다.

`status`는 `available`, `needs_review`, `not_applicable`이다. 알려진 요건의 실행본 누락,
다중 실행본, 출처 무효, 수동 검토 요건은 `issues`에 보존한다. `not_applicable`은 등록된
메타데이터가 없다는 뜻이며 졸업 가능을 뜻하지 않는다. 범위 내 최대 100개 원본·500개 실행
요건·2000개 근거를 넘으면 부분 결과 대신 `rule_catalog_limit_exceeded`를 반환한다.
**`catalog_complete`는 항상 false**다. 전체 공식 규정이 등록됐다는 확인으로 사용하지 않는다.

`GET /catalog/rule-programs/{id}`는 현재 사용 가능한 승인본만 제공한다. 관리자 검토 메모·
행위자·학생 자료는 공개하지 않는다. 근거에는 공식 문서/검토 문서/청크 UUID, 버전,
원본·본문 hash, 제목·URL·페이지·최대 800자 발췌를 제공한다.

내부 `as_core` 어댑터는 검증된 승인 실행본을 기존 결정론적 Rule Engine 계약으로 바꾼다.
신뢰할 학교 기록 공급자·공식 감사 저장·HTTP 판정은 후속이다. 개인 입력을 학교 확정값으로
승격하지 않는다. OpenAPI와 생성된 Dart 타입·전송 API를 함께 제공하며 화면 연결은 후속이다.
