# 학생용 학사 조회 API

2026-10-19 구현. prefix는 `/api/v1/catalog`. 로그인한 모든 활성 계정이 읽을 수 있고
관리자 학교 범위 부여는 필요하지 않다. 개인정보/관리자 변경 이력은 반환하지 않는다.

각 컬렉션에 `GET /{collection}`, `GET /{collection}/{id}`를 제공한다.

`institutions`, `departments`, `curricula`, `courses`, `curriculum-courses`,
`rule-sets`, `rules`, `documents`를 조회한다. 쓰기는 관리자 API만 제공한다.
DB/버전/관계의 원본은 [학사 API](academic.md), DTO 원본은 [OpenAPI](openapi.json)다.

- 목록은 `institution_id/department_id/curriculum_id`, 이름 검색 query, UUID cursor,
  limit(1~100), `as_of`(기본 UTC 오늘)를 받는다. 하위 ID의 학교/학과를 추론하고
  요청한 부모와 다르면 404다. 과목의 교육과정/학과 필터는 실제 과목 연결로 제한한다.
- 검토 자료는 **적용본만** 반환한다. 기준일에 유효한 적용본 중 lineage별 가장 높은
  revision을 선택한다. 미래 효력 새 버전이 과거 기준일까지 덮어쓰지 않는다.
- 묶음 소속 규칙은 선택된 유효 적용 묶음의 하위 요건만 노출한다. 문서가 규칙을
  참조하면 그 규칙도 공개 가능한 적용본이어야 한다. rules 목록은 rule_set_id 필터도 받는다.
- 직접 UUID 조회도 같은 가시성 검사를 사용한다. 초안/기간 밖/교체된 판/삭제 학교는
  404다. 관리자 actor UUID·감사·소유자·비밀번호 등을 응답에 포함하지 않는다.
- 응답은 no-store이며 `items/next_cursor`를 제공한다. GET은 학생 소속을 변경하지 않는다.

조건 설명을 조회했다고 Rule Engine 실행식이 되지 않으며, 문서 적용은 RAG 승인 자격이
아니다. 전체 학교 기준을 읽는 것과 특정 학생에게 공식 적용된다고 판정하는 것은 다르다.
입학연도/이수경로별 공식 규칙 선택·공식 기록 매핑·졸업감사 HTTP API는 후속이다.
현재 학생 Flutter 화면은 이 API에 아직 연결하지 않았으며 관리자 화면은 기존 API를 사용한다.
