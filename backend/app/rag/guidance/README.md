# 클릭형 학사 안내 — 프론트·백엔드 전달 문서

작성일: 2026-11-02. 내부 자료 형식 버전: `academic-click-v2`.
사용자가 제공한 대학 챗봇 스크린샷의 **큰 메뉴 → 세부 버튼 → 안내·근거** 흐름을 따른다.
학교 로고·캐릭터·실제 규정이나 연락처를 복제하지 않는다.

## 이번 구현 범위

AI/RAG 폴더만 추가했다. 기존 프론트, API, 서비스, 스키마, 규칙엔진, DB는 변경하지 않았다.
이 패키지는 표준 라이브러리만 사용하는 독립 모듈이다. 앱에 자동 연결되지 않는다.
아래 JSON은 **프론트 구현을 위한 내부 전달 규격**이며 합의·배포된 HTTP 계약이 아니다.
`examples/responses.json`의 감사 결과는 합성 시연 자료다. 실제 수집 안내 예시는
`examples/content-responses.json`으로 분리했다. 실제 학생·학교 판정이나 운영 승인 자료가 아니다. `synthetic-audit.json`은 렌더러가
읽는 필드만 담은 축약 픽스처이며 전체 공개 감사 API 응답 예시는 아니다.

- 기본 메뉴 9개와 학사관련규정 메뉴: 졸업, 학사일정, 공지사항, 수강신청, 전공, 장학금, 등록금, 기숙사, 학부·학과.
- 졸업 세부 메뉴: 요약, 이수학점, 필수과목, 봉사, 자격, 논문, 추가 확인 항목.
- 이전 메뉴·처음으로 이동. 자유 입력 의도 분류·서버 대화 저장은 이번 범위가 아니다.
- 학사일정과 학사관련규정은 실제 수집 본문을 안내한다. 그 외 미연결 항목은
  `content_pending`으로 표시하고 클릭하면 준비 중이라는 안내만 반환한다. 스크린샷의 학과명·전화번호를 실제 데이터로 넣지 않았다.
- 졸업 항목은 검증된 기존 감사 결과를 표현한다. 이 모듈은 판정을 계산하지 않는다.
- 추가 확인 항목 메뉴는 `manual_review` 종류다. 다른 종류의 `needs_review`도 각 카드에 표시된다.

## 실행

프로젝트의 `backend/` 디렉터리에서 실행한다.

```bash
app/rag/.venv/bin/python -m app.rag.guidance --catalog
app/rag/.venv/bin/python -m app.rag.guidance home
app/rag/.venv/bin/python -m app.rag.guidance graduation
app/rag/.venv/bin/python -m app.rag.guidance credits \
  --audit app/rag/guidance/examples/synthetic-audit.json
app/rag/.venv/bin/python -m unittest discover -s app/rag/tests -p test_guidance.py -v
```

Python 호출:

```python
from app.rag.guidance import catalog, respond

menu = catalog()
first_message = respond("home")
sub_menu = respond("graduation")
# verified_view는 백엔드가 소유권·무결성·현재 사용 가능 여부를 검증한 GraduationAuditView.
# result = respond('credits', audit=verified_view.model_dump(mode='json'))
```

`audit`는 프론트에서 보낸 판정 JSON을 받는 인자가 아니다. 프론트는 항목 ID와 선택한
감사 ID만 전달하고, 서버가 해당 사용자의 감사를 다시 읽고 검증한 뒤 모듈에 넣어야 한다.
CLI로 로컬 파일을 읽는 행위에는 공식 승인이나 사용자 인증 효과가 없다.

## 프론트 구현 규칙

`examples/catalog.json`에 전체 메뉴 트리, `examples/responses.json`에 실제 모듈 출력이 있다.

| 필드 | 의미·처리 |
| --- | --- |
| `schema_version` | 내부 규격 버전. 모르는 버전은 안내 연결 오류로 처리 |
| `node_id`, `title` | 선택 항목 ID와 화면 제목 |
| `state` | `ready`, `needs_selection`, `needs_input`, `unavailable` |
| `reason` | 아래 원인 코드. Rule Engine의 판정 사유와 별개 |
| `message` | 안내 본문. summary 메시지는 전체 감사 상태이며 개별 항목 상태는 cards에 있음 |
| `buttons[]` | label, action=`select_node`, node_id, availability |
| `cards[]` | 항목별 상태·설명·근거. 빈 목록을 충족으로 해석하지 않음 |
| `warnings[]` | 본문·카드보다 먼저 표시하는 주의 안내 |
| `audit` | 결과가 있을 때만 제공. 기준일·문맥·전체 상태·현재 사용 가능 여부 |
| `issues[]` | 기존 감사 및 현재 검증 이슈. 이유 코드는 개발 상세에 사용 |
| `notice` | 결과가 있을 때 표시하는 최종 승인 관련 설명 |

`reason`: `menu`, `unknown_node`, `approved_content_not_configured`,
`verified_audit_required`, `audit_rendered`, `invalid_audit_projection`.
`ready`는 화면 표시 준비 상태다. 학사 요건을 충족했다는 뜻이 아니다.

버튼은 label로 분기하지 않고 `action`과 `node_id`로 처리한다. `availability=content_pending`은
'준비 중' 배지를 붙이고 클릭 시 준비 중 메시지를 보여준다. ID를 URL이나 함수명으로 실행하지 않는다.
메뉴 이동은 자료 수정이나 감사 생성을 수행하지 않는다. 결과를 보고 싶을 때 감사가 없으면
기존 공식 감사 선택·생성 화면으로 연결할 UX는 프론트 담당자가 정한다.

권장 레이아웃은 넓은 화면에서 3열, 좁은 화면에서 1~2열 카드다. 이미지 대신 텍스트만으로도
선택 가능해야 한다. 탭/엔터 선택, 명확한 포커스, 선택 상태, 스크린리더 라벨을 제공한다.
클릭하면 사용자의 선택 문구와 응답을 대화에 추가하고 이전 메뉴로 돌아갈 수 있게 한다.
빠른 연속 선택에서 오래된 응답이 마지막 선택을 덮어쓰지 않도록 요청 순서를 관리한다.
요청 실패·시간 초과에는 선택/입력을 보존하고 재시도를 제공한다. 전송 오류는 이 순수 모듈의
응답 상태가 아니라 프론트/API 전송 계층에서 처리한다.

텍스트는 HTML로 실행하지 않는다. 근거는 카드 안에 제목·페이지·문서 버전을 표시한다.
`source_url`은 http/https만 렌더러가 허용하지만 공식 도메인 승인 여부는 서버의 책임이다.
`source_state=unavailable`이면 '연결된 근거 없음'으로 표시한다. 원문 발췌는 현재 입력 계약에
없으며 생성하지 않는다. 동일 버전의 원문 열기는 후속 서버 연결이 필요하다.

`audit.current_usable=false`이면 warnings를 최상단에 표시하고, 카드의 충족 상태도
'과거 기준일 결과'로 묶어서 보여준다. `evaluated_on`을 항상 표시한다.
`catalog_complete=false`이면 전체 졸업 가능 안내를 하지 않는다.
`quantities`의 수치는 정확한 십진 문자열 또는 null이다. null을 0으로 바꾸거나 프론트에서
부족 수치를 다시 계산하지 않는다. 자격/논문 내부 0·1은 표시 수치로 제공하지 않는다.

## 백엔드 연결 지점 — 이번에는 변경하지 않음

기존 `GET /api/v1/me/graduation-audits/{audit_id}/guidance`와
`app/services/graduation_guidance.py`를 재사용한다. 별도의 졸업 판정기를 만들지 않는다.
기존 guidance 응답에는 조건 종류와 참조명 전체가 없으므로, 이 모듈에는 서비스 내부의
**GraduationAuditView 전체를 JSON 모드로 투영**해 전달한다. guidance 응답을 다시 입력하지 않는다.

규칙 조인은 `(program.id, program.version, rule.rule_id)`와 결과의
`(rule_set_id, rule_set_version, rule_id)`로 한다. 당시 참조 스냅샷에서 과목명을 얻고,
당시 문서 버전·페이지·해시를 유지한다. 판정 상태와 수치는 수정하지 않는다.
중복 결과, 누락된 규칙, 버전 불일치, 지원하지 않는 종류, 잘못된 수치/출처는 안내 불가로 처리한다.
미래에 추가될 사유 코드는 알려진 상태의 일반 문구로 대체하며 구체적인 부족 문장을 추측하지 않는다.

통합 전 합의할 일:

1. 기존 guidance 응답에 이 표현 자료를 추가할지, 별도 표현용 API를 둘지 정한다.
   기존 응답을 바로 교체하지 않는다. Pydantic/OpenAPI와 Dart 생성은 각 담당자의 작업이다.
2. 서버에서 인증 사용자 소유 감사 조회·무결성·근거 변경/회수·범위 검증 후 렌더러를 호출한다.
   이 모듈의 구조 검사는 권한·승인 검사를 대신하지 않는다. 사용자·감사 간 전역 응답 캐시를 공유하지 않는다.
3. 개인 기준 평가는 별도 라벨/계약으로 확장한다. 현재 모듈은 official=true 입력만 지원한다.
4. 일반 학사 안내에는 학교/학과/입학연도/시행 기간, 검토된 문구와 출처를 연결할 계약이 필요하다.
   검색된 문서나 클라이언트의 approved 플래그만으로 승인 안내를 만들지 않는다.
5. 기존 이름 기반 `/assistant/queries`를 이 메뉴 계약으로 바꾸지 않는다.
   학생이 선택하는 학교·학과 목록은 기존 등록 데이터에서 가져오며 이름으로 ID를 추론하지 않는다.

## QA 전달

홍요아 담당자는 개발 테스트와 별도로 다음 시나리오를 선택해 예상 화면을 검토할 수 있다.

- 첫 메뉴 → 졸업 → 학점 → 이전 메뉴 → 처음으로.
- 준비 중인 학과/장학금 메뉴에 실제 연락처나 규정이 만들어져 나오지 않는지.
- 감사 없음 → 감사 선택 필요. 원래 선택이 유지되는지.
- 미충족/충족/자료 부족/적용 기준 없음이 서로 다른 의미로 표시되는지.
- 0과 자료 없음, 소수 학점, 봉사 시간, 자격·논문을 구분하는지.
- 누락 과목과 확인 필요 과목을 함께 보여주는지.
- 회수된 근거의 과거 결과를 현재 충족 결과처럼 강조하지 않는지.
- 전체 기준이 미완성인데 졸업 가능이라고 안내하지 않는지.
- 근거 페이지·문서 버전, 시간 초과·재시도·빠른 연속 클릭 동작.

## 2차 취업 LLM 방향

사용자 후보: Vertex 기반 'Gemini 3.8 Flash' 또는 'Argon'. 사용자 제안 명칭으로 기록하며,
공식 모델 ID·제품명·Vertex 제공 여부·리전·접근 권한은 아직 확인/확정하지 않았다.
가상의 모델 ID를 설정하거나 실제 API를 호출하지 않았다. 모델 연결 시 공식 문서와
프로젝트의 사용 가능 모델 목록을 확인해 확정한다.

학사 메뉴/템플릿은 모델과 독립적이다. 취업에는 기존 `JobAnalyzer` 경계를 사용해
공고와 사용자가 선택한 경험을 비교·설명하는 구현을 후속 연결한다. 기존 학사
`AnswerGenerator`를 그대로 취업 분석기로 간주하지 않는다. 선택 자료의 식별자·버전,
공고 인용 위치 검증을 유지하고 모델의 의미적 정확성은 별도로 평가한다.
공급자 인증·리전·비용·시간 제한·개인정보 전송 범위를 확정한 뒤 전용 어댑터를 만든다.
기존 학사 LLM 실험 코드는 삭제하지 않았고 앱의 현재 생성 설정도 변경하지 않았다.


## v2: 실제 학사일정·규정 안내 (2026-11-02)

프론트 전달용 상세 내용은 [CONTENT_HANDOFF.md](CONTENT_HANDOFF.md)를 따른다.
기존 `calendar`는 준비 중에서 선택 가능한 연도/월 메뉴로 바뀌었고,
`regulations` 및 장/조항/페이지 선택 노드가 추가됐다. `cards[].type`으로
`calendar_event`, `regulation_excerpt`, `regulation_page`를 구분한다.
졸업 감사 카드의 기존 필드는 유지했다. 일반 참고 자료는 공식 개인 판정과 분리된다.
