# 학교 질의 API

`POST /api/v1/assistant/queries`는 RAG 팀의 학교 질의 서비스를 호출하는 백엔드 어댑터다.
이 기존 경로는 로컬 이름 기반 계약이며 인증·운영 승인 DB와 직접 연결하지 않았다.
별도 [학교 지식 검토·DB 검색](school-knowledge.md)은 관리자 승인·회수와 인증된 UUID 문맥을
사용한다. 실제 LLM·임베딩 공급자는 미설정이다. 프론트엔드 목업 대화·로컬 기록을 저장하거나
졸업 판정을 실행하는 API가 아니다.

Pydantic 원본은 `backend/app/schemas/assistant.py`, OpenAPI는
`/api/v1/openapi.json`과 [저장소 사본](openapi.json)에서 확인한다.
학교 컨텍스트는 RAG 팀의 이름 비교 계약을 사용한다. 별칭이나 UUID를 자동 추론하지
않으며 향후 학교·교육과정 UUID 계약은 별도 합의한다.

## 요청

```json
{
  "question": "사회봉사 시간 조건은?",
  "context": {
    "institution": "경동대학교",
    "department": "컴퓨터공학과",
    "admission_year": 2026,
    "track": "single_major"
  }
}
```

- `question`: 앞뒤 공백 제거 후 1~4000자.
- `context`: 생략 시 빈 문맥. 학교·학과는 각각 1~128자, `track`은 1~64자 문자열.
  앞뒤 공백은 제거하지만 별칭 정규화나 DB 소속 확인은 하지 않는다.
- `admission_year`: 네 자리 JSON 정수(1000~9999). 문자열·소수·boolean은 거부한다.
- 문맥 필드는 null/생략 가능하다. 부족하면 상태와 `missing_fields`로 안내한다.
- 알 수 없는 필드, `preview`, 승인 플래그, 사용자 식별자는 HTTP 422로 거부한다.
- 요청마다 새 UUID `query_id`를 반환한다. 저장·재조회 ID가 아니며 대화 이력도 없다.
- 선택적 `X-Request-ID` UUID는 응답 헤더에서 유지한다. 잘못된 값은 새 UUID로 바뀐다.

## 응답과 화면 연결

```json
{
  "query_id": "280b7c97-4827-4b7b-baf8-11359d316b99",
  "status": "insufficient_evidence",
  "reason": "no_approved_matching_evidence",
  "answer": null,
  "citations": [],
  "missing_fields": []
}
```

현재 저장된 PDF가 미승인인 상태에서 학교 문맥이 충분하면 위 결과를 반환한다.
코퍼스 설정이 없어도 빈 검색으로 동일 상태를 반환한다. preview 검색 후보, 경고,
내부 파일 경로는 HTTP 응답에 노출하지 않는다.

| status | UI 처리 |
|---|---|
| `grounded` | 답변과 인용을 함께 표시. 현재 실제 생성기가 없어 런타임에서 생성하지 않음 |
| `insufficient_evidence` | 공식 근거 부족 안내. 목업 답변이나 임의 졸업 기준으로 대체하지 않음 |
| `needs_user_input` | `missing_fields` 입력 안내. 현재 작성 내용 유지 |
| `failed` | 질의 실패 안내와 재시도. 원본 예외·질문을 로그에 남기지 않음 |

위 질의 결과는 모두 HTTP 200이다. 구조 검증 실패는 HTTP 422, 처리되지 않은
서버 오류는 HTTP 500 공통 오류이며 `error.code`, `message`, `field_errors`,
`request_id`를 제공한다.

`reason`과 `missing_fields`는 OpenAPI enum이다.

| 주요 reason | 의미 |
|---|---|
| `school_context_required` | 학교 또는 학과 필요 |
| `academic_scope_required` | 학점 질문에 입학연도·이수경로 필요 |
| `conflicting_admission_year` | 질문 속 입학연도와 컨텍스트 충돌 |
| `rule_engine_required` | 졸업 가능 여부는 별도 Rule Engine 감사 필요 |
| `no_approved_matching_evidence` | 승인된 적용 근거 없음 |
| `document_context_not_approved_or_incomplete` | 같은 문서의 조건 페이지 미승인/불완전 |
| `answer_generator_not_configured` | 승인 근거가 있어도 실제 생성기가 연결되지 않음 |
| `rag_processing_failed` | 모듈 실패/유효하지 않은 결과 차단 |

그 밖의 생성기 출력·인용 검증 코드는 OpenAPI enum을 따른다. `missing_fields`는
`question`, `institution`, `department`, `admission_year`, `track`, `graduation_audit` 중
하나다. `graduation_audit`는 요청에 넣는 필드가 아니라 향후 별도 졸업감사 흐름을
안내할 문맥이다. 현재 졸업감사 API는 구현되지 않았다.

## 인용 계약

`grounded`는 공백이 아닌 답변과 최소 한 개의 인용을 함께 반환해야 한다.
다른 상태는 `answer=null`, `citations=[]`이다. 인용은 승인 근거 원본에서
`chunk_id`·`document_id` UUID, `title`, HTTP(S) `source_url`, 1 이상 `page`, `excerpt`를
구성한다. 생성기가 제목·URL·페이지를 만들거나 내부 `source_file`을 노출하지 않는다.

합성 승인 문서와 가짜 생성기로 테스트한 계약이며 실제 PDF 승인을 뜻하지 않는다.
LLM 사실성 검증은 후속이다. 문서 버전·기간·교육과정과 관리자 승인 DB는 별도
[학교 지식 경로](school-knowledge.md)에 연결했으며 이 로컬 API의 파일 플래그를 승격하지 않는다.

## 실행과 확인

저장소 루트에서 실행한다. PowerShell에서는 `curl.exe`나 Swagger UI를 사용할 수 있다.

```bash
docker compose -f compose.yaml -f compose.rag.yaml up --build -d
curl --fail http://localhost:8010/api/v1/assistant/queries \
  -H 'Content-Type: application/json' \
  -d '{"question":"사회봉사 시간 조건은?","context":{"institution":"경동대학교","department":"컴퓨터공학과"}}'
```

기본 Compose는 빈 인덱스, RAG Compose는 PDF 추출 후 읽기 전용 JSONL을 사용한다.
파일 코퍼스는 `APP_ENV=local`에서만 허용하며 파일 승인·업로드 HTTP API는 없다.
인증·관리자 승인·PII·공급자 정책을 구현하기 전에는 운영용으로 배포하지 않는다.

프론트엔드의 `features/assistant/assistant_api.dart`와 공통 채팅 패널이 이 계약으로
상태·인용·입력 부족·공통 오류를 표시한다. 연결 실패와 추가 입력 요구 시 질문을 보존한다.
인증·관리자 학사·학업 프로필·일정 화면은 실제 서버와 연결했다. 다른 개인 화면은 로컬 저장이고 공식 졸업감사는
미연결이다. 대화는 클라이언트 메모리·IPC로 공유하며 서버에 저장하지 않는다.

OpenAPI 사본 갱신은 환경 설정 후 다음 명령으로 실행한다.

```bash
cd backend
uv run --frozen python -c 'import json; from app.main import app; print(json.dumps(app.openapi(), ensure_ascii=False, indent=2))' > ../docs/api/openapi.json
```
