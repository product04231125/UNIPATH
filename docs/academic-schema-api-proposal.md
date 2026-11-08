# 학사 기준·졸업요건 DB 및 API 변경 명세 초안

- 작성: 2026-11-08 KST. 구현 전 검토 명세다. 아래 테이블·경로·DTO는 **제안 계약**이며 현재 동작하는 API가 아니다.
- 사용자 승인 범위: 학교·학과·교육과정·과목·학교 분류·졸업요건의 DB 및 OpenAPI 변경까지 포함한다. 기존 프런트 전용 범위를 이번 작업에서는 확장한다.
- 현재 구현 대상은 관리자 **학교·학과 / 교육과정·과목 / 졸업요건** 세 메뉴와 이를 위한 DB·백엔드·관리자 OpenAPI뿐이다. 학생용 테이블·catalog 조회·/me API·화면·개인 데이터 이전은 이번 범위에서 제외한다. 아래 후속 참고 항목은 구현 목록이 아니다.
- 이번 산출물: 컬럼·키·제약, API 요청/응답·오류, 호환·마이그레이션·검증 명세. 실행 코드·Alembic·현재 OpenAPI JSON을 변경하거나 DB에 적용하지 않는다.
- 상위 맥락: [학사 기준](academic-catalog-data-design.md), [졸업 본문](graduation-requirements-data-design.md). 물리 구조·제안 API 세부사항은 이 문서를 기준으로 한다.
- 기준: develop 288af01의 모델·schema·API·0014까지의 migration 및 b765272의 학교 분류 후속 코드. 운영 DB 배포 상태는 확인하지 않았다.

## 1. 이번에 선택한 설계 방향

1. 학교·학과의 기존 UUID를 재사용한다. 과목·교육과정도 기존 자료와 대응되는 경우 같은 UUID로 새 학사 구조에 옮기고 legacy 대응 관계를 보존한다.
2. 새 학사 본문은 PostgreSQL의 `academic_v2` schema에 추가한다. 기존 public 테이블과 공식 감사 이력을 파괴하거나 덮어쓰지 않는다. 아래 이름은 이 schema 안의 테이블명이다.
3. 분류는 학교별 한 계층 구조다. `major/general/other`는 신규 입력값에서 제외하고 호환 매핑에만 남긴다. 필수·선택은 분류 마스터 항목으로 등록하지 않는다.
4. 과목의 학점·이름과 교육과정에서의 분류·필수 여부·인정학점은 분리한다. 학과마다 같은 과목을 복제하지 않는다.
5. 각 편집 단위는 초안 수정 번호와 게시 revision을 분리한다. 과목·분류·교육과정·졸업요건의 게시본은 불변이다.
6. 적용 범위는 공통 모델을 사용한다. 학교 공통, 학과·교육과정, 입학연도, 학교별 경로를 AND/OR로 표현한다. 학교가 다른 분류는 참조하지 못한다.
7. 관리자 기준에 적용 범위·안정 ID·버전을 저장해 후속 학생 연결이 가능하게 한다. 학생 O/X·개인 기록 연결·판정·수신 조회는 이번에 구현하지 않고 기존 학생 기능을 유지한다.

`academic_v2`는 물리 namespace, `/api/v2`는 제안 전송 경로다. 어느 것도 현재 생성되거나 등록된 상태가 아니다.

## 2. 타입·공통 컬럼 규약

- `uuid`는 UUID, `text`는 UTF-8 문자열, `ts`는 timestamptz, `date`는 날짜, `int`는 정수, `decimal`은 numeric(12,3), `json`은 JSONB다. 금액/학점/점수는 부동소수로 저장하지 않는다.
- `?` 표기만 NULL을 허용한다. 별도 언급 없으면 모든 컬럼은 NOT NULL이다. 아래 `PK`, `UQ`, `FK`는 물리 제약이다.
- `audit` 약어는 `created_by uuid FK public.users, updated_by uuid FK public.users, created_at ts, updated_at ts` 네 컬럼이다. 행위자는 서버 세션에서 결정한다.
- `version`은 수정 충돌용 양의 정수, `revision_no`는 같은 원본의 게시 개정 번호다. 새 draft를 만들 때 번호를 예약하며 취소해도 번호를 재사용하지 않는다.
- `revision_meta`는 `revision_no int, version int, status text, effective_from date?, effective_to date?, digest text?, published_by uuid?, published_at ts?, withdrawn_at ts?, withdrawal_reason text?, replaced_by_id uuid?, audit`다. replaced_by_id는 각 revision 테이블의 같은 원본·학교에 속한 revision을 참조하는 self FK다.
- status는 draft/published/withdrawn. draft의 digest·published_by/at는 NULL, published와 withdrawn에는 지문과 게시 정보가 필수다. withdrawn에는 철회일·사유가 필수다. 종료일은 시작일 이상이다.
- 모든 학교 소속 테이블은 `institution_id uuid`를 가진다. id PK가 있는 테이블에는 `UQ(id,institution_id)`, 연결 테이블에는 학교를 포함한 부모 복합 FK를 사용해 부모·자식·참조가 같은 학교인지 보장한다. scope_set과 revision도 같은 학교여야 한다.
- 게시 본문의 불변과 lifecycle 메타데이터는 구별한다. 게시/철회/교체 때 version·상태·replaced_by_id만 정해진 트랜잭션으로 바뀔 수 있고, 본문·당시 digest는 바뀌지 않는다.
- 기본 현재 후보는 published이면서 replaced_by_id가 없고 적용 기간/범위가 맞는 revision이다. 교체된 본문은 명시 ID로 과거 문맥에서 읽을 수 있으나 현재 기준이라고 표시하지 않는다. 후속본 철회 시 이전 본문으로 자동 fallback하지 않는다.
- 한 게시본의 일부 대상만 바꾸는 부분 교체는 1차 자동 지원하지 않는다. 교체는 이전 적용 범위를 모두 포함하는 후속본을 명시하고, 대상 분할이 필요하면 기존 종료·후속 범위를 검토한 새 문서로 구성한다. 다른 원본 사이의 공통/학과 규정 누적과 구분한다.
- 과거 표시를 보존해야 하는 이름·내용은 revision 또는 당시 snapshot에 저장한다. 현재 이름으로 이력을 재작성하지 않는다.

## 3. 학교·학과·분류·경로

| 테이블/기존 변경 | 실제 컬럼 제안 | 키·제약 |
| --- | --- | --- |
| `public.institutions` | 기존 컬럼 유지 | 신규 학교도 기존 슈퍼관리자 권한 사용. 별도 학교 마스터 중복 생성 없음 |
| `public.departments` | 기존 컬럼 유지, 추가 `inactive_at ts?` | 기존 학교+code UQ·학교 FK 유지. 새 학생 선택만 사용 중지, 기존 FK 유지 |
| `classification_revisions` | id uuid PK, institution_id, revision_meta | UQ(institution_id,revision_no), 학교당 draft 1개 부분 UQ. 게시본은 여러 버전 보관 |
| `classification_nodes` | id uuid PK, institution_id, revision_id uuid FK classification_revisions, logical_id uuid, parent_id uuid?, label text, position int, selectable bool | UQ(revision_id,logical_id), UQ(id,revision_id,institution_id). parent는 같은 revision의 node 복합 FK. 루트/자식 순서 각각 부분 UQ |
| `study_tracks` | id uuid PK, institution_id, name text, version int, inactive_at ts?, audit | 이름은 표시값, 참조는 ID. 사용 중인 경로 삭제 금지. 개명 전 이름은 게시 snapshot에 보존 |

분류 노드는 깊이를 고정하지 않는다. 부모만 분류하는 학교는 부모도 selectable=true, 세부분류까지 선택하는 학교는 부모 selectable=false로 설정할 수 있다. selectable=false인 노드는 과목의 직접 분류로 선택하지 못하지만 학점표 subtree 조건에는 사용할 수 있다.
노드 label은 1~128자, position은 0 이상이다. 깊이 8, 노드 1000개/학교 revision을 1차 상한 제안으로 두고 실제 학교 자료로 조정한다. 순환·자기 부모·삭제 후 고아 노드는 거부한다.
학교 분류의 별도 관리 코드 입력은 없다. 외부 공식 코드가 필요하면 선택 메타데이터를 후속 추가한다.

## 4. 공통 적용 범위

| 테이블 | 실제 컬럼 제안 | 키·제약 |
| --- | --- | --- |
| `scope_sets` | id uuid PK, institution_id | 부모 편집 aggregate의 수명에 속하는 불변 범위 집합. draft 전체 교체 때만 변경 |
| `scope_clauses` | id uuid PK, institution_id, set_id uuid FK scope_sets, department_id uuid? FK public.departments, curriculum_revision_id uuid? FK curriculum_revisions, admission_from int?, admission_to int?, track_mode text, position int | track_mode=all/selected. 연도는 두 값 모두 NULL 또는 둘 다 1000~9999 및 from<=to. UQ(set_id,position) |
| `scope_tracks` | clause_id uuid, institution_id, track_id uuid FK study_tracks | PK(clause_id,track_id), clause/track와 같은 학교 복합 FK |

- clause 안의 필드는 AND, clause끼리는 OR. 학교 전체는 제한이 없는 clause 하나로 표현한다. root scope_set의 빈 목록은 저장 중 미완성 상태일 수 있으나 게시를 막는다.
- track_mode=all이면 scope_tracks 0개, selected이면 1~32개다. 자식 개수는 서버 게시 검증/DB deferred trigger 중 구현 시 하나를 선택해 검증한다.
- 교육과정 범위를 지정한 clause는 해당 revision의 audience에 포함되는 학과만 허용한다. 학교 공통 교육과정은 특정 학과 ID를 강제하지 않는다.
- 자식 scope_set_id=NULL은 부모 상속이다. 별도 scope_set이 있으면 부모와 교집합을 사용한다. 범위를 넓히는 override는 없다.
- scope_set은 하나의 편집 aggregate가 소유한다. 다른 게시 aggregate와 mutable scope를 공유하지 않는다. 새 revision 복사 시 범위·노드·행의 물리 ID는 새로 만들고 논리 ID만 보존하며, 의미가 같은 학교 분류/경로 참조는 유지한다.
- 제한한 문맥 값이 없으면 `needs_context`이며 해당 없음을 뜻하지 않는다. 적용 기간과 입학연도는 서로 다른 축이다.
- scope는 curriculum revision과 서로 참조할 수 있다. DDL 생성 순서는 scope_clauses의 curriculum FK를 뒤에 추가하는 방식으로 해결한다. scope 데이터가 자신의 curriculum audience에서 자신을 다시 참조하는 것은 거부한다.
- 국적·재직·편입 등 추가 대상 속성은 학교별 경로와 섞지 않는다. 1차 자동 적용 schema에는 없으며 예외 설명과 수동 확인을 보존한다. 추가 속성의 자료 출처·확인 정책을 정한 후 확장한다.

## 5. 관리자 과목·교육과정

| 테이블 | 실제 컬럼 제안 | 키·제약 |
| --- | --- | --- |
| `courses` | id uuid PK, institution_id, code text, version int, inactive_at ts?, audit | UQ(institution_id,code). 기존 과목은 기존 UUID/공식 code 유지. 코드 없는 과목 허용은 1차에서 제외 |
| `course_revisions` | id uuid PK, institution_id, course_id uuid FK courses, name text, credits decimal, description text, revision_meta | UQ(course_id,revision_no), course별 draft 1개. credits 0~100, 소수 3자리 |
| `curricula` | id uuid PK, institution_id, version int, inactive_at ts?, audit | 학과를 이 행의 필수 FK로 고정하지 않음. 안정 ID의 원본 |
| `curriculum_revisions` | id uuid PK, institution_id, curriculum_id uuid FK curricula, name text, curriculum_year int?, classification_revision_id uuid FK classification_revisions, audience_set_id uuid FK scope_sets, revision_meta | UQ(curriculum_id,revision_no), 원본별 draft 1개. curriculum_year는 기준 연도, audience 입학연도와 별개 |
| `curriculum_courses` | id uuid PK, institution_id, revision_id uuid FK curriculum_revisions, logical_id uuid, course_id uuid FK courses, course_revision_id uuid FK course_revisions, classification_node_id uuid FK classification_nodes, requirement text, recognized_credits decimal, position int | UQ(revision_id,course_id), UQ(revision_id,logical_id). requirement=required/elective/not_specified. 인정학점 0~100 |
| `course_allocation_overrides` | id uuid PK, institution_id, curriculum_course_id uuid FK curriculum_courses, scope_set_id uuid FK scope_sets, classification_node_id uuid?, requirement text?, recognized_credits decimal? | 3개 변경값 중 하나 이상 필수. 모두 NULL인 예외 금지. 대상은 기본 교육과정 audience 이내 |

- 같은 과목의 과목명·기본학점은 course_revision, 교육과정별 인정은 curriculum_course가 소유한다. 기본 인정학점은 선택한 과목 버전 값으로 UI가 채울 수 있으나 저장값은 명시한다.
- course_revision은 course_id와 같은 원본이어야 하고, classification_node는 curriculum의 고정 classification_revision 소속이어야 한다. 이를 복합 FK 또는 게시 검증으로 확인한다.
- 경로별 override가 두 개 이상 일치하면 게시 오류다. 마지막 저장값 우선 정책을 사용하지 않는다. match가 없으면 기본값, 하나면 해당 값과 기본 상속을 합성한다.
- 학생 문맥·원본 수강 연결 테이블은 후속 단계에서 재설계한다. 현재 planning_profile·personal_course_records 및 해당 API를 수정하거나 이전하지 않는다. 관리자 course/revision/classification의 안정 참조만 준비한다.

## 6. 졸업 본문·인증 조건

| 테이블 | 실제 컬럼 제안 | 키·제약 |
| --- | --- | --- |
| `requirement_documents` | id uuid PK, institution_id, kind text, version int, inactive_at ts?, audit | kind=checklist/certification/credit_table, 생성 후 종류 변경 금지 |
| `requirement_revisions` | id uuid PK, institution_id, document_id uuid FK requirement_documents, title text, scope_set_id uuid FK scope_sets, curriculum_revision_id uuid?, classification_revision_id uuid?, revision_meta | UQ(document_id,revision_no), 원본별 draft 1개. 참조 revision은 같은 학교 |
| `requirement_nodes` | id uuid PK, institution_id, revision_id uuid FK requirement_revisions, logical_id uuid, parent_id uuid?, position int, node_kind text, text text, choice_kind text?, choice_count int?, scope_set_id uuid? | node_kind=line/group/item. choice_kind=all/at_least는 group만. UQ(revision_id,logical_id), 같은 revision 부모 FK |
| `conditions` | id uuid PK, institution_id, node_id uuid UNIQUE FK requirement_nodes, kind text, schema_version int, payload json | 직접 확인 또는 닫힌 조건 schema. node의 문서 kind와 맞지 않는 조건 거부 |
| `condition_course_refs` | condition_id uuid, institution_id, course_revision_id uuid FK course_revisions | PK(condition_id,course_revision_id) |
| `condition_certificate_refs` | condition_id uuid, institution_id, certificate_id uuid FK public.certificates, catalog_version int, snapshot json | PK(condition_id,certificate_id), catalog_version>=1 |
| `condition_classification_refs` | condition_id uuid, institution_id, classification_node_id uuid FK classification_nodes, match_mode text | PK(condition_id,classification_node_id), match_mode=exact/subtree |
| `requirement_exceptions` | id uuid PK, institution_id, revision_id uuid, target_node_id uuid, kind text, scope_set_id uuid, condition_id uuid?, replacement_node_id uuid?, explanation text, position int | kind=exemption/replacement, 대상/대체/조건은 같은 revision. exemption은 대체 NULL, replacement는 대체 필수 |
| `display_tables` | id uuid PK, institution_id, node_id uuid FK requirement_nodes, title text, position int, rows json, columns json, cells json | 설명용 표만. row/column 안정 ID·순서·cell 참조를 닫힌 schema로 검증. 실행값으로 해석하지 않음 |

- line은 checklist의 root 항목만, group/item은 certification만 허용한다. credit_table 본문은 다음 절의 표 테이블을 사용한다. 노드 text는 1~4000자, 문서당 노드 1000개·깊이 8을 초기 한도로 제안한다.
- 선택 조건은 직계 item/group을 모두 센다. all은 choice_count=NULL, at_least는 1<=count<=직계 자식 수다. 비어 있는 그룹은 초안에 보존하고 게시 거부한다.
- 설명 표는 relational 집계 대상이 아니므로 JSONB로 보관한다. 앞선 논리 문서의 별도 row/column/cell 엔터티를 1차 물리화하지 않는 선택이다. 값 편집·순서·소형 병합만 표시용으로 다루며 semantic 조건은 conditions가 소유한다.
- 조건 kind 1차 후보: manual, minimum_credits, required_courses, minimum_volunteer_hours, any_certificate. 기존 실행기가 다루지 못하는 어학 점수/활동 완료/서류·학교별 집계 정책은 설명+manual로 보존한다. typed schema와 자료 출처를 정의하기 전 자동 지원을 표시하지 않는다.
- 기존 kind 이름을 재사용해도 현재 실행기가 새 분류 ID나 개인 기록 연결을 그대로 지원한다는 뜻은 아니다. node 기반 집계 adapter와 입력 출처 정책을 검증한 조건만 자동 실행하고 나머지는 needs_review로 반환한다.
- 조건 payload의 UUID만으로 관계를 저장하지 않는다. 위 참조 테이블을 통해 현재 master 존재·학교·검토 버전을 검증한다. payload.kind와 행 kind는 일치해야 한다.
- 한 줄 문장에는 source_url 컬럼이나 필수 조건을 새로 두지 않는다. 구 URL과 공식 근거는 legacy 및 기존 증거 모델에 남는다.
- exception의 대체/조건 그래프는 순환 금지, 무조건 면제는 명시 검토가 필요하다. 그룹 상태는 satisfied/not_satisfied/needs_review/not_applicable/exempt이며 학생 직접 체크값과 구별한다.

## 7. 학점표

| 테이블 | 실제 컬럼 제안 | 키·제약 |
| --- | --- | --- |
| `credit_tables` | id uuid PK, institution_id, revision_id uuid FK requirement_revisions, title text, position int | 문서 kind=credit_table, 한 revision 여러 표 가능 |
| `credit_headers` | id uuid PK, institution_id, table_id uuid FK credit_tables, logical_id uuid, parent_id uuid?, position int, label text, role text | role=group/value/subtotal/total. 같은 표 부모 FK, UQ(table_id,logical_id) |
| `credit_rows` | id uuid PK, institution_id, table_id uuid FK credit_tables, logical_id uuid, position int, label text, note text, scope_set_id uuid? | UQ(table_id,logical_id), UQ(table_id,position) |
| `credit_cells` | table_id uuid, institution_id, row_id uuid, header_id uuid, state text, value decimal? | PK(row_id,header_id), row/header 같은 표 복합 FK. state=empty/number/not_applicable |
| `credit_column_filters` | id uuid PK, institution_id, header_id uuid FK credit_headers, classification_node_id uuid FK classification_nodes, match_mode text, requirement text? | match_mode=exact/subtree. 한 header 여러 filter는 OR, filter 안 분류·필수 여부는 AND |
| `credit_aggregate_members` | institution_id, table_id uuid, aggregate_header_id uuid, member_header_id uuid | PK(aggregate_header_id,member_header_id), 같은 표 FK·자기 참조 금지 |

- group은 자식이 있어야 하고 셀은 없다. 나머지 role은 잎이어야 한다. 소계/총계의 원문 숫자와 explicit 집계 참조를 별도로 보존한다.
- 숫자 셀은 value>=0, 다른 state는 value=NULL이다. 빈 셀은 명시 empty로 반환하고 0으로 채우지 않는다. 누락 셀도 조회에서는 empty로 정규화한다.
- 표 열의 다단 머리글 병합은 부모/자식 구조에서 계산한다. 전체 자유 셀 병합은 1차 범위가 아니다. 전체 졸업 최소학점을 잎 최소값의 합으로 추정하지 않는다.
- credit_column_filters는 문서가 고정한 classification_revision의 node만 참조한다. 필터 없는 열은 문서 표시 전용이며 자동 집계를 표시하지 않는다.
- row별 이수 경로는 scope_set으로 표현한다. 행 이름으로 학생 경로를 추론하지 않는다. 실제로 국적/재직 같은 미지원 대상 축이 있으면 행을 보존하고 대상 수동 확인 상태를 표시한다.
- 전체 표 300열/300행·3만 셀, Decimal 소수 3자리 등을 초기 상한으로 제안한다. 규정 원문 숫자를 보존하면서 입력·응답 크기 상한을 적용한다.

## 8. 학생 저장 구조 — 이번 범위 제외

앞선 문서의 student_contexts, course_record_origins, self_checks, requirement_record_links, evaluation_snapshots는 후속 설계 참고다. 이번 migration에 생성하거나 개인 기록을 연결하지 않는다. 관리자 세 메뉴가 완료된 뒤 실제 수신 흐름에 맞춰 다시 설계한다.
한 줄 문장의 안정 logical_id, 게시 revision, 분류 참조, 적용 범위는 관리자 데이터이므로 현재 범위에 포함한다. 이것만으로 학생 체크나 판정이 동작한다고 표시하지 않는다.

## 9. 변경 영수증·전환 상태·이전 대응

| 테이블 | 실제 컬럼 제안 | 키·제약 |
| --- | --- | --- |
| `mutation_receipts` | actor_id uuid, client_id uuid, institution_id uuid?, operation text, target_id uuid?, request_digest text, result_resource_id uuid?, response_status int, response_json json, created_at ts | PK(actor_id,client_id). 성공 트랜잭션과 같은 commit에 영수증 기록. 실패는 성공 영수증으로 만들지 않음 |
| `school_rollouts` | institution_id uuid PK FK public.institutions, mode text, version int, batch_id uuid?, switched_at ts?, switched_by uuid?, validation_digest text? | mode=legacy/shadow/v2. 학교 기준 쓰기 경로를 서버가 단일 선택 |
| `migration_batches` | id uuid PK, institution_id, source_digest text, result_digest text?, status text, started_at ts, finished_at ts?, report json | status=prepared/validated/switched/failed. 복구 가능한 실행 결과·건수 보존 |
| `legacy_mappings` | id uuid PK, batch_id uuid FK migration_batches, institution_id, legacy_kind text, legacy_id uuid, legacy_version int, target_kind text, target_id uuid, target_revision_id uuid?, resolution text | UQ(batch_id,legacy_kind,legacy_id,legacy_version). resolution=mapped/needs_review |

legacy_mappings는 이관 영수증으로만 사용한다. 런타임 무결성을 이 polymorphic 대응표에 의존하지 않는다. 각 target 실제 존재·학교·지문은 이관 검증에서 확인하고, 서비스의 실제 데이터는 앞선 명시 FK를 참조한다.
mutation_receipts의 response_json은 관리자 변경 결과만 보관하고 비밀번호·토큰·원본 PDF를 넣지 않는다. 학생 변경 영수증으로 확장하는 작업은 후속 단계다. 보관 기간은 서비스 운영 정책 확정이 필요하다.

## 10. API 공통 계약 제안

- 신규 경로는 `/api/v2` 아래 별도 router로 추가한다. 학교/학과의 기존 v1 CRUD를 재사용하는 동안도 새 조회 payload는 같은 학교/학과 ID를 사용한다. v1 의미를 조용히 바꾸지 않는다.
- 관리자 권한은 기존 활성 학교 범위와 세션 잠금을 재사용한다. 학생·게스트는 새 관리자 API를 사용할 수 없다. 새 학생 쓰기 API는 이번에 추가하지 않는다.
- 생성/상태 변경/복사 요청은 `client_id`가 필수다. 서버 ID 발급 전 UI row 식별은 `client_ref`를 쓰고 결과에 client_ref→id 대응을 반환한다.
- 초안 전체 교체는 PUT, 부분 필드 수정은 PATCH로 구분한다. PUT에는 누락 컬렉션을 허용하지 않고, `expected_version`을 필수로 받는다. published 본문 수정은 409다.
- aggregate의 row/node ID를 유지하면 identity를 보존한다. 다른 revision의 ID를 보내면 422다. 새 row/node는 client_ref만 보내며 서버가 UUID를 발급한다. 다른 연도로 복사는 별도 operation이다.
- 저장·게시·복사는 트랜잭션+멱등성 영수증으로 결과를 재현한다. 성공 응답 유실 후 같은 본문/client_id 재시도는 같은 결과를 반환하고, 다른 본문은 409다. 그 사이 권한 회수 시 재시도도 권한을 재검사한다.
- 최초 생성 201, 재시도 재현은 기존 성공 상태와 결과 ID 반환, 수정/게시 200, 초안 삭제 204. 초안 삭제 재시도도 영수증으로 처리한다.
- 목록은 `items,next_cursor`와 limit(기본50/최대100), 학교·상태·검색 필터를 갖는다. 게시 aggregate 본문은 한 번에 완전 반환하거나 크기 오류를 반환하며 일부를 전체로 표시하지 않는다.
- 오류 envelope는 현재 `backend/app/schemas/common.py`의 `error.code/message/field_errors/request_id` 구조를 그대로 따른다. field_errors는 `{field,reason}` 배열이며 오류 위치는 `nodes[client_ref].text` 같은 안정 입력 식별자를 포함한다.
- 상태별 구분: 401 로그인, 403 역할/학교 권한, 404 접근할 수 없는 본인/리소스, 409 version·게시 상태·중복·범위 충돌, 422 field/schema·관계 오류. 새 세부 reason enum은 기존 ErrorCode를 무시해 임의 추가하지 않고 schema에 함께 정의한다.
- 초기 요청 상한 제안: editor aggregate 2MiB. 문장·인증 노드/표 셀 제한과 독립 검사한다. HTTP JSON의 decimal은 소수 3자리 문자열로 표준화한다.

## 11. 관리자 API 변경 목록

아래 경로는 구현 대상 초안이다. `{id}` 계열은 UUID path parameter다.

| 메서드·제안 경로 | 핵심 요청/응답 | 담당 범위 |
| --- | --- | --- |
| GET/POST `/api/v2/admin/classification-revisions` | 목록: institution_id,status,cursor. 생성: institution_id,client_id, 선택 copy_from_id → revision 헤더 | 학교 분류의 서버 저장 |
| GET/PUT `/api/v2/admin/classification-revisions/{id}` | 완전 트리 / expected_version,client_id,nodes 전체 → stable ID·경로·version | 상위·세부분류를 한 기준으로 관리 |
| POST `/api/v2/admin/classification-revisions/{id}/publish` | PublishInput → 게시본·지문 | 순환·유효 부모·참조 검증 |
| GET/POST `/api/v2/admin/study-tracks` | institution_id 또는 새 name,client_id → 학교별 경로 | 기존 track 문자열 후보 교체 |
| PATCH `/api/v2/admin/study-tracks/{id}` | expected_version,name/inactive,client_id → 최신 경로 | 개명/신규 선택 중지 |
| GET/POST `/api/v2/admin/courses` | 목록 또는 institution_id,code,name,credits,client_id → 원본+초기 draft | 학교의 과목 원본 |
| POST `/api/v2/admin/courses/{id}/revisions` | client_id, 선택 copy_from_id → 새 draft | 과목 개정 |
| GET/PUT `/api/v2/admin/course-revisions/{id}` | expected_version,client_id,name,credits,description → draft | 이름·학점 수정 |
| POST `/api/v2/admin/course-revisions/{id}/publish` | PublishInput → 게시본 | 과목 기준 고정 |
| GET/POST `/api/v2/admin/curricula` | 목록 또는 institution_id,name,client_id → 원본+draft | 공통/학과 교육과정 |
| POST `/api/v2/admin/curricula/{id}/revisions` | client_id,copy_from_id → draft | 교육과정 개정 |
| GET/PUT `/api/v2/admin/curriculum-revisions/{id}` | name,curriculum_year,분류 revision,scope,courses,overrides 전체 + expected_version/client_id → 본문 | 적용 대상과 과목 인정 기준 통합 저장 |
| POST `/api/v2/admin/curriculum-revisions/{id}/course-entries` | client_id,expected_version, 기존 course_revision_id **또는** new_course, 분류·필수 여부·인정학점 → 원본/연결 ID와 최신 교육과정 version | 새 과목+편입을 원자적으로 저장 |
| POST `/api/v2/admin/curriculum-revisions/{id}/publish` | PublishInput → 게시본 | 원본·분류·경로·대상·중복 override 검증 |
| GET/POST `/api/v2/admin/requirement-documents` | institution_id,kind,title,client_id → 원본+draft | 기존 별도 규칙 묶음 대신 편집 단위 |
| POST `/api/v2/admin/requirement-documents/{id}/revisions` | client_id,copy_from_id → 새 draft | 기준 개정/복사 |
| GET/PUT `/api/v2/admin/requirement-revisions/{id}` | expected_version,client_id,scope,타입별 본문 전체 → draft | 문장·인증·표 각각 discriminator |
| POST `/api/v2/admin/requirement-revisions/{id}/publish` | PublishInput → 게시본 | 적용 대상과 내용 검토 |
| GET/PATCH `/api/v2/admin/courses/{id}`, `/api/v2/admin/curricula/{id}`, `/api/v2/admin/requirement-documents/{id}` | 원본·revision 헤더 조회 / expected_version,client_id,inactive → 원본 상태 | 원본 정체성의 읽기·신규 선택 중지. 본문 개정과 분리 |
| POST `/api/v2/admin/{revision-resource}/{id}/preview-publication` | expected_version → digest,issues,영향 범위 요약 | 아래 네 revision 리소스에 각각 명시 router로 등록 |
| POST `/api/v2/admin/{revision-resource}/{id}/withdraw` | expected_version,client_id,reason → 철회 상태 | 과거 본문 보존 |
| DELETE `/api/v2/admin/{revision-resource}/{id}` | expected_version,client_id → 204 | 참조 없는 draft만 삭제 |

`revision-resource`는 classification-revisions/course-revisions/curriculum-revisions/requirement-revisions의 설명용 약어다. OpenAPI에 임의 문자열 route 하나로 구현하지 않고 네 경로를 명시한다. 각 GET/PUT도 서로 다른 DTO로 정의한다.
PublishInput은 `expected_version, client_id, expected_digest, review_note, replaces_revision_id?`다. preview가 반환한 현재 지문을 확인한다. 새 학교 공통/학과 규정은 누적 적용되고 동일 원본의 겹치는 현재 revision 교체만 명시한다.
분류 revision의 기본 현재 기준도 게시 교체 관계로 정하고 MAX(revision_no)만으로 고르지 않는다. 과목·교육과정·문서의 inactive는 신규 선택 중지이며 기존 게시본 철회와 다르다.
course-entries에서 new_course 생성 시 과목 draft와 연결을 함께 만들며 성공했다고 자동 게시하지 않는다. 기존 code 중복은 409 후 기존 과목 선택으로 복구한다.

## 12. 학생 수신 API — 후속 단계

학생용 catalog 조회와 /me 학업 문맥·수강·O/X·기록 연결·평가 API는 이번 OpenAPI 구현 목록에서 제외한다. 기존 학생 API의 요청·응답 의미도 변경하지 않는다.
현재 완료 기준은 관리자 세 메뉴의 작성→요청→DB 저장→새 세션 재조회→수정·게시/철회다. 학생 조회 성공을 이번 작업 완료 조건으로 요구하지 않는다.

## 13. 요청/응답 형태 예시

실제 UUID·학생 데이터가 아닌 설명용 placeholder다. 실제 DTO에서는 `id` 자리에 UUID를 받는다. 현재 서버로 전송할 수 있는 예시는 아니다.

```json
{
  "expected_version": 3,
  "client_id": "<retry-uuid>",
  "classification_revision_id": "<published-classification-revision-uuid>",
  "name": "교육과정 이름",
  "curriculum_year": 2026,
  "scope": {
    "clauses": [{
      "department_id": "<department-uuid>",
      "admission_from": 2026,
      "admission_to": 2028,
      "track_mode": "selected",
      "track_ids": ["<track-uuid>"]
    }]
  },
  "courses": [{
    "client_ref": "entry-1",
    "course_revision_id": "<course-revision-uuid>",
    "classification_node_id": "<classification-node-uuid>",
    "requirement": "required",
    "recognized_credits": "3.000",
    "position": 0,
    "overrides": []
  }]
}
```

응답은 `id,version,status,digest?,scope,courses,resolved_refs,id_map`을 제공한다. `id_map`은 신규 client_ref를 서버 row ID와 연결하고, `resolved_refs`는 실제 표시 이름·분류 경로·참조 revision을 포함한다. 수정 UI가 이를 다시 추론하지 않는다.
문장 본문은 `kind=checklist,nodes=[{client_ref,text,position,scope:null}]`이며 `source_url,rule_type`을 받지 않는다. 인증 본문은 group/item 및 conditions, 학점표는 headers/rows/cells/filters를 받는 별도 schema다.

## 14. 기존 API 호환과 전환 기준

| 기존 v1 | 전환 중 | v2 학교 전환 후 |
| --- | --- | --- |
| 학교·학과 CRUD | 공통 ID/권한 유지 | 같은 마스터 재사용, inactive 확장 |
| 과목/교육과정/분류 | legacy 학교는 기존 쓰기, shadow는 검증 복제만 | v1 학사 수정은 409+전환 안내, v2만 기준 쓰기 |
| 고정 category/required | 명시 legacy mapping으로 dual-read | 신규 작성은 classification node+requirement만. 구 payload는 구 snapshot 표시용 |
| v1 수강·개인 기록 | 기존 읽기/쓰기 유지 | 이번에 origins를 생성하거나 학생 API를 변경하지 않음 |
| v1 planning-profile·학생 조회 | 기존 문맥과 요청/응답 유지 | 새 관리자 기준 수신으로 전환하지 않음. 후속 학생 작업에서 다룸 |
| rule_sets/rules/programs | 기존 공식 흐름 보존 | legacy 이력 읽기 유지. 새 정책을 기존 조건으로 표현 가능한 부분만 adapter 연결 |
| 공식 검토·감사·근거 | 전 단계에서 불변 보존 | 과거 결과 재작성 없음. 새 전체 규정 완전성·공식 입력 검증을 통과하기 전 v2 기준을 공식 감사 입력으로 사용하지 않음 |

학교 전환은 관리자 학사 기준 쓰기만 전환하며 학생 context 선택·일정·활동·기존 개인 기록 기능은 보존한다. 기존 학생 조회는 legacy 기준을 유지한다. 관리자 새 기준이 아직 학생에게 반영되지 않는 단계임을 명시하고, 두 체계 사이에 변경 사항을 자동 동기화하지 않는다.

## 15. 마이그레이션 실행 설계

현재 저장소 head는 `0014_school_admin_signups`다. 다른 채팅에서 migration이 추가될 수 있으므로 아래는 이름 제안이며 실제 번호/부모 head는 구현 직전 다시 확인한다.

1. **expand_catalog**: academic_v2 schema, 분류/경로·범위·과목/교육과정·영수증·전환 테이블을 추가한다. 기존 테이블 변경은 departments.inactive_at 같은 additive만 포함한다.
2. **expand_requirements**: 관리자 졸업 본문·인증 조건·표·분류 연결 테이블과 FK만 추가한다. 학생 체크·개인 기록 연결·평가 테이블은 제외한다. 순환 DDL 의존은 테이블 생성 후 FK 추가로 해소한다.
3. **prepare_backfill**: 학교별 source 지문과 기존 row/버전·참조 건수를 기록하고 classification/track 명시 대응안을 작성한다. 자유 이름 매핑은 하지 않는다.
4. **backfill_shadow**: 학교/학과/과목/교육과정 UUID를 보존해 v2 원본 생성, 기존 기록 snapshot·버전 참조 보존. 아직 게시 또는 사용자 기본 조회를 전환하지 않는다. 재실행은 batch 대응표로 중복 방지한다.
5. **validate_shadow**: 학교별 과목 수/연결 수·학점·범위·누락·외부 참조·지문을 비교한다. 기존 manual_review는 줄별 안정 ID 후보로 옮기되 자동 게시하지 않는다. 메모리 표/인증 초안이 서버에 있다고 가정하지 않는다.
6. **publish_and_switch**: 검토한 분류→과목→교육과정→졸업 본문 순서로 게시하고, 학교 잠금+현재 지문 확인 하에 mode=v2로 원자 전환한다. 전환 중 동시 v1 쓰기는 거부한다.
7. **observe_and_retire**: 관리자 세 메뉴에서 저장→새 세션 재조회→수정→게시/철회와 과목/표/분류 연결을 확인한다. 학생 후보·수강·체크·자기관리 결과 연결은 후속 단계다. 기존 데이터 삭제는 이번 전환에 포함하지 않는다.

rollback은 'DB downgrade로 새 데이터를 삭제'하지 않는다. 전환 전 실패는 legacy mode 유지, shadow 오류는 원본 보존·batch 실패 기록이다. 전환 후 v2 쓰기가 있었다면 legacy로 자동 되돌리면 데이터가 사라져 보이므로 기준 쓰기를 잠그고 batch·신규 변경을 보존한 뒤 forward-fix 또는 명시 역이전 계획을 사용한다. 운영 적용 전 백업·복원 리허설과 학교별 전환 보고서가 필요하다.

## 16. 구현 검증과 완료 기준

- PostgreSQL의 실제 제약으로 타 학교 FK·범위/연도 역전·중복 identity·invalid cell을 거부하는지 검증한다. SQLite만으로 대체하지 않는다.
- Alembic upgrade를 빈 DB와 0014 기반 합성 fixture DB에 실행하고, 기존 공식 감사·입력/결과 지문이 바뀌지 않는지 비교한다. downgrade는 새 데이터 없는 개발 DB에서만 검증한다.
- 동시 요청의 학교 권한 회수·초안 수정 충돌·동일 client_id·연결 부분 실패·게시 겹침을 테스트한다. 성공 응답 유실 재시도에서 과목/연결이 중복 생성되지 않아야 한다.
- A/2026 OR B/2025, 공통+학과 누적, 경로 전체/선택, 문맥 누락, 중첩 택 N·면제·표 빈칸/0/-를 검증한다.
- 동일 과목의 교육과정별 전공 필수/교양 선택, 경로 override가 관리자 저장·재조회에서 일치해야 한다.
- OpenAPI는 Pydantic·FastAPI 구현에서 생성한다. 실제 schema 작성 후 export 스크립트·저장소 docs/api/openapi.json·Dart 생성 타입을 같은 변경에 맞춘다. 현행 JSON만 손으로 바꾸어 구현된 API처럼 표시하지 않는다.
- schema discriminator, additionalProperties 금지, path/query/response schema, error envelope·decimal 문자열·페이지네이션·owner 권한을 계약 테스트한다.
- 관리자 화면은 세 메뉴를 작은 기능 단위로 연결하고 저장·재조회까지 확인한다. 학생 API·화면·데이터 이전은 후속 작업이다. 이번 변경으로 기존 학생 기능이 손상되지 않는 호환 회귀만 검증한다. 실서버/DB 적용·원격 푸시·PR·배포는 현재 수행하지 않았다.

## 17. 이번 명세에서 남기는 판단

- 코드 없는 과목, 국적/재직/편입의 추가 대상 속성, 학교별 어학시험/점수 척도와 자동 비교, 재수강·교류/중복 인정은 별도 typed 정책이 필요하다. 원문 입력은 허용하고 자동 판단은 수동 확인으로 남기는 기본 동작을 제안한다.
- 공개 게시와 기존 공식 실행본 승인을 같은 것으로 합치지 않는다. 새 문서 게시가 공식 졸업 판단에 충분하다고 표시하지 않는다.
- 설계 검증은 저장소 구조·현재 오류/권한/DTO 대조와 문서 자체 확인까지다. DDL 실행·API 계약 생성·운영 데이터 이전은 아직 하지 않았다.
