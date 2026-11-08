# 관리자 학사 기준 재설계 — 현재 구현

이번 구현은 관리자 학교·학과 / 교육과정·과목 / 졸업요건 세 메뉴에 한정한다.
학생 화면·catalog·/me 계약·기록·기존 공식 감사는 변경하지 않는다.

## 학교 분류 기반

`0015_admin_academic_foundation`은 기존 public 테이블을 유지하면서
academic_classification_revisions, academic_classification_nodes,
academic_study_tracks, academic_mutation_receipts 네 테이블을 추가한다.
초안 분류와 과목의 고정 category가 별개였던 문제를 해결하기 위한 서버 기준이다.
관리자 학교 메뉴와 교육과정·졸업요건 편집기가 이 기준을 공유한다.

구체 설계안의 별도 `academic_v2` PostgreSQL schema와 `/api/v2`는 제안이었다.
실제 구현은 기존 권한·세션·DB 격리 방식을 유지하도록 기존 schema에
academic_ 접두사의 새 테이블과 `/api/v1/admin/academic` 경로를 추가했다.
다음은 구현과 OpenAPI에서 생성된 계약이며, 설계안의 미구현 경로와 구분한다.

| 메서드·경로 | 실제 동작 |
| --- | --- |
| GET/POST `/api/v1/admin/academic/classification-revisions` | 학교별 버전 목록 / 서버 초안 생성·기존 버전 복사 |
| GET/PUT `/api/v1/admin/academic/classification-revisions/{id}` | 전체 트리 조회 / 초안 전체 교체 |
| POST `.../{id}/preview-publication` | 초안 version·본문 지문·미완성 항목 확인 |
| POST `.../{id}/publish` | 확인한 지문과 version에 대한 불변 게시본 생성 |
| GET/POST `/api/v1/admin/academic/study-tracks` | 학교별 이수 경로 목록·생성 |
| PATCH `/api/v1/admin/academic/study-tracks/{id}` | 이름 변경·사용 중지/복원, 기존 ID 보존 |

생성·변경에는 재시도 client_id가 필수다. 동일 수행자+키+본문은 같은 결과를 반환하고
다른 본문/operation에 키를 재사용하면 409다. 저장·감사·영수증을 한 트랜잭션에서 확정한다.
변경은 기존 신원 잠금 아래 현재 세션·학교 권한을 재검사하므로 권한 회수 후 재시도도 거부한다.

분류 노드는 서버 ID와 개정 간 유지하는 logical_id를 가진다. 기존 노드는 id로,
신규 노드는 client_ref로 보낸다. parent_ref는 같은 요청의 기존 id 문자열 또는
신규 client_ref이며 id_map으로 서버 ID를 돌려준다. 순환·다른 revision ID·중복 위치·
깊이 8 초과·항목 1000개 초과를 거부한다. 표시 이름을 연결 키로 사용하지 않는다.

학교별 초안은 하나다. 게시 후 수정은 금지하며 새 버전으로 복사할 때 물리 ID는 바꾸고
logical_id·부모 관계·표시 이름을 보존한다. 기존 게시본은 바뀌지 않는다.
경로의 사용 중지는 과거 ID를 삭제하지 않는다. 학생 프로필의 track을 자동 변경하지 않는다.

학교 생성·학과·교육과정·과목·기존 규칙의 v1 API와 기존 데이터는 유지한다.
이번 migration은 기존 분류 초안을 임의로 공식 게시하거나 legacy category를 이름으로 매핑하지 않는다.
기존 자료는 관리자가 명시적으로 가져와 분류를 지정한다. 이름으로 자동 매핑하지 않는다.

## 교육과정·과목

`0016_admin_academic_curricula`은 academic_curriculum_revisions / courses /
department_refs / track_refs 네 테이블을 추가한다. 기존 courses를 과목 원본으로
재사용하며 새 연결에 원본 ID·버전·이름·코드 스냅샷과 학교 분류·필수/선택·인정학점을 둔다.
동일 과목을 여러 교육과정에서 다르게 연결할 수 있다.

| 메서드·경로 (`/api/v1/admin/academic` 기준) | 동작 |
| --- | --- |
| GET/POST `/curriculum-revisions` | 학교별 목록 / 새 기준·기존 교육과정 가져오기 |
| GET/PUT `/curriculum-revisions/{id}` | 대상·과목 조회 / 초안 전체 교체 |
| POST `/curriculum-revisions/{id}/course-entries` | 과목 재사용 또는 원본 생성+연결을 원자 저장 |
| POST `/curriculum-revisions/{id}/preview-publication`, `/publish` | 게시 검사 / 검토 지문·버전 확인 후 게시 |
| POST `/curriculum-revisions/{id}/drafts` | 다음 개정 초안 복사 |

가져온 원래 교육과정·과목 연결은 유지한다. 최초 게시에는 원본 과목의 분류 연결을
모두 확인하며, 이후 개정은 이전 게시본을 보존하면서 과목을 추가·제외할 수 있다.
원본 수정은 기존 과목 API로 처리한다. 게시 스냅샷은 바뀌지 않으며 초안의 최신
과목 이름·코드 확인은 관리자가 명시적으로 실행한다.

## 한 줄 요건·학점표·인증 요건

`0017_admin_academic_requirements`는 academic_requirement_revisions와
academic_requirement_department_refs / track_refs / node_refs를 추가한다.
본문은 종류별 엄격한 DTO로 검증하는 JSONB이며 외부 참조는 FK 행으로도 저장한다.
별도 규칙 묶음 등록을 요구하지 않는다.

| 메서드·경로 (`/api/v1/admin/academic` 기준) | 동작 |
| --- | --- |
| GET/POST `/requirement-revisions` | 종류별 목록 / 빈 초안·기존 요건 설명 가져오기 |
| GET/PUT `/requirement-revisions/{id}` | 범위·본문 조회 / 초안 전체 교체 |
| POST `/requirement-revisions/{id}/preview-publication`, `/publish` | 완성도·범위·지문 검사 / 게시 |
| POST `/requirement-revisions/{id}/drafts` | 문장·기준·행/열 ID를 보존하는 새 개정 |
| POST `/requirement-revisions/{id}/withdraw` | 사유와 함께 게시 철회, 본문 보존 |

- 한 줄 요건: 문장별 안정 ID·순서·선택 범위. 새 입력에 출처 URL이 없다.
- 학점표: 최대 8단 열 계층·행·비고·소수 학점·숫자/빈칸/해당 없음,
  학교 분류·필수 여부·소계/총계 참조. 순환 참조와 묶음 열 셀은 거부한다.
- 인증 요건: 영역·기준·하위 영역·모두/택1/택N·면제 설명·보충 설명 표.
  택N은 기준과 하위 영역의 합계 안에서 정한다. 설명 표의 점수를 자동 평가하지 않는다.

범위는 같은 절 안에서 학과·입학연도·경로를 AND로, 여러 절을 OR로 결합한다.
빈 초안은 저장 가능하지만 게시에는 대상과 본문이 필요하다. 하위 범위는 상위 범위와
교집합이며 교육과정을 고정했으면 그 범위와도 교집합을 확인한다.
학생 O/X·개인 기록·자동 판정은 현재 계약에 포함하지 않는다.

분류·교육과정은 게시본을 직접 수정하지 않고 새 개정으로 이어간다. 이전 게시본을
자동 폐기하지 않는다. 분류·교육과정 철회, 초안 삭제, 학교별 특수 정책 자동 판정은
현재 계약에 포함하지 않는다.

검증: 별도 PostgreSQL17/pgvector 합성 컨테이너에서 migration과 실제 저장·재조회·
게시·복사·버전 충돌·멱등성·타 학교 FK·학생 권한 거부를 검사한다.
운영 DB 적용·배포·제품 원격 푸시는 수행하지 않았다.
