# 관리자 학사 기준 재설계 — 현재 구현

이번 구현은 관리자 학교·학과 / 교육과정·과목 / 졸업요건 세 메뉴에 한정한다.
학생 화면·catalog·/me 계약·기록·기존 공식 감사는 변경하지 않는다.

## 학교 분류 기반 (1차 구현)

`0015_admin_academic_foundation`은 기존 public 테이블을 유지하면서
academic_classification_revisions, academic_classification_nodes,
academic_study_tracks, academic_mutation_receipts 네 테이블을 추가한다.
초안 분류와 과목의 고정 category가 별개였던 문제를 해결하기 위한 서버 기준이다.
관리자 화면·과목·요건의 새 연결은 이어서 구현한다.

구체 설계안의 별도 `academic_v2` PostgreSQL schema와 `/api/v2`는 제안이었다.
실제 1차 구현은 기존 권한·세션·DB 격리 방식을 유지하도록 기존 schema에
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
화면 연결 및 관리자 자료 이전 흐름이 완성되기 전에는 기존 자료가 새 기준으로 전환됐다고 표시하지 않는다.

검증: 별도 PostgreSQL17/pgvector 합성 컨테이너에서 migration과 실제 저장·재조회·
게시·복사·버전 충돌·멱등성·타 학교 FK·학생 권한 거부를 검사한다.
운영 DB 적용·배포·제품 원격 푸시는 수행하지 않았다.
