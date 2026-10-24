# 학교 문서 검토·DB 검색 API

`0006_school_knowledge`는 `school_knowledge_documents`, `school_knowledge_chunks`를 추가한다.
학사 메타데이터의 `applied`와 본문 검색 승인을 분리한다. 승인된 문서 본문은 PostgreSQL에
보관하고 RAG 팀의 한국어 BM25를 재사용한다. 임베딩 모델·차원·실제 LLM은 선택하지 않았다.

## 관리자 등록과 검토

모든 경로는 `/api/v1/admin/knowledge-revisions` 아래다. 슈퍼관리자 또는 해당 학교의
활성 범위를 가진 학교관리자만 읽고 변경한다. 변경은 기존 권한 변경과 같은 transaction
lock에서 세션·역할·범위를 다시 확인한다. 학생은 등록·검토·원문 조회를 할 수 없다.

| 메서드·경로 | 계약 |
|---|---|
| `POST /knowledge-revisions` | 적용된 `source_document_id`, `expected_source_version`, 원본 `document_hash`, `page_count`, `extractor_version`, 실제 `source_checked_on`으로 검토 대기 초안 생성 |
| `GET /knowledge-revisions` | `institution_id`, `source_document_id`, `status=draft/approved/revoked`, UUID `cursor`, `limit=1..100`으로 허용 학교 목록 |
| `GET /knowledge-revisions/{id}` | 원문 메타데이터와 검토 이력. 본문은 페이지 경로에서 별도 조회 |
| `GET /knowledge-revisions/{id}/pages` | 페이지별 hash·글자 수·분할 수·빈 페이지 표시. 숫자 cursor, limit 1..100 |
| `GET /knowledge-revisions/{id}/pages/{page}` | 해당 페이지의 본문·범위·경고·분할/offset/hash와 현재 부모 version |
| `PUT /knowledge-revisions/{id}/pages/{page}` | `expected_version`, `is_blank`, `parts`로 초안의 페이지 전체를 원자 교체 |
| `DELETE /knowledge-revisions/{id}/pages/{page}?expected_version=N` | 초안 페이지 삭제, 부모 version 증가 |
| `POST /knowledge-revisions/{id}/approve` | 출처·적용 범위·추출·전체 원본 검토 후 불변 승인 |
| `POST /knowledge-revisions/{id}/revoke` | expected_version과 reason으로 승인 회수. 본문/이력은 보존 |
| `DELETE /knowledge-revisions/{id}?expected_version=N` | 초안과 하위 청크만 삭제. 승인/회수된 이력은 삭제 불가 |

학교·학과·교육과정·제목은 적용된 문서 메타데이터에서 결정한다. 요청으로 다른 학교나
소유자를 지정하지 못한다. 같은 메타데이터 UUID에 추출본은 하나만 등록한다.
승인본의 내용을 수정하거나 회수본을 재승인하지 않는다. 수정본은 학사 문서에서 새 초안 →
새 적용 버전을 만들고 그 **새 source_document_id**에 등록한다.

### 페이지와 명시적 빈 페이지

```json
{
  "expected_version": 1,
  "is_blank": false,
  "parts": [{
    "content": "검토할 원문 본문",
    "admission_years": [2026],
    "tracks": ["single_major"],
    "warnings": ["table_structure_requires_review"]
  }]
}
```

페이지 순서 안의 parts 순서가 원문 순서다. 서버가 chunk UUID·SHA-256·문자 offset·페이지
재구성 hash를 계산한다. 본문 공백은 임의로 제거하지 않는다. 최대 200페이지, 페이지당
20개 part·총 20,000자이며 범위는 입학연도 최대 200개·이수경로 최대 32개다.
초안에는 범위 미확인(null)과 추출 경고를 남길 수 있지만 그 상태로는 승인할 수 없다.
본문을 수정해 경고를 해소한 뒤 명시적으로 검토한다. 중복 범위/경고, NUL, 빈 part를 거부한다.

원본을 직접 확인한 **빈 페이지**는 `is_blank=true, parts=[]`로 등록한다. parts가 없는
일반 페이지는 거부한다. 빈 페이지는 DB에서 별도 표시하고 원문 페이지 완전성에 포함하지만
검색 본문·생성기 입력·인용으로 만들지 않는다. 누락된 OCR/추출 실패를 자동으로 빈 페이지로
처리하지 않는다. 본문 없는 문서 전체는 승인할 수 없다.

### 승인과 회수

승인 요청에는 `expected_version`, 저장된 hash와 같은 `reviewed_document_hash`,
`source_verified`, `applicability_verified`, `extraction_verified`,
`complete_document_verified` 네 boolean을 모두 true로 보내고 `review_note`(1~500자)를
기록한다. boolean 대신 숫자를 받을 수 없다. 전체 페이지와 분할/offset/hash를 검사하고,
본문 청크의 범위 누락·미해결 경고가 있으면 422다. 버전/hash 충돌은 409다.

이는 현재 관리 권한을 가진 사람의 검토 확인이다. 서버가 학교 담당자의 외부 신원이나
공식 사이트의 현재 PDF를 자동 검증했다는 뜻이 아니다. URL을 서버에서 다운로드하지 않으며
등록된 원본 hash도 검토자가 제공한 값이다. 실제 원본·공식 출처·학교 적용 기준을 확인한
관리자가 승인해야 한다. 기존 PDF나 파일의 승인 플래그를 자동 승격하지 않는다.

등록·페이지 변경·승인·회수·초안 삭제는 수행자/대상/학교/행동/request_id로 감사한다.
본문·검토 메모·회수 사유·질문은 감사 로그에 복사하지 않는다. 검토 메모와 회수 사유는
허용 학교의 관리자 상세에서만 조회한다.

## 학생용 검색과 질의

- `POST /api/v1/me/school-searches`: 승인된 문서의 출처와 최대 800자 발췌를 검색한다.
  답변·졸업 판정을 생성하지 않는다. 요청 `limit`은 1..10, 기본 3이다.
- `POST /api/v1/me/school-queries`: 같은 자료를 기존 RAG 생성 인터페이스로 전달한다.
  현재 실제 생성기가 없어 근거가 있으면 `failed / answer_generator_not_configured`다.
  근거가 없으면 `insufficient_evidence`이며 임의 답변으로 대체하지 않는다.

두 경로 모두 로그인해야 하며 같은 사용자당 15분 60회 제한을 공유한다. 기존 `/assistant/queries`
이름 기반·로컬 JSONL 계약은 그대로 유지한다. 새 요청은 이름을 추정하지 않고 등록된 UUID를 쓴다.

```json
{
  "question": "사회봉사 승인 조건은?",
  "context": {
    "institution_id": "00000000-0000-4000-8000-000000000001",
    "department_id": "00000000-0000-4000-8000-000000000002",
    "curriculum_id": null,
    "admission_year": 2026,
    "track": "single_major"
  }
}
```

UUID는 합성 예시다. 실제 등록된 학교·학과·선택 교육과정의 소속을 검사하며 잘못된 조합이나
삭제 학교는 404다. 이 선택은 학생의 공식 학적 인증이 아니다. 학교 공통 문서와 해당 학과
문서를 함께 검색하고, 교육과정별 자료는 그 교육과정을 명시한 경우에만 포함한다.
새 DB 경로에서는 모든 질의에 입학연도·이수경로를 확인하며 누락 시 needs_user_input으로
요청한다. 다른 연도/경로의 봉사·자격 요건도 섞지 않는다. 검토된 청크 범위와 비교하며
질문의 연도 충돌·정보 부족·졸업 가능 여부는
기존 RAG 입력 요구/Rule Engine 안내를 재사용한다.

검색 결과는 `query_id`, `status`, `reason`, `sources`, `missing_fields`다.
status는 `evidence_found`, `insufficient_evidence`, `needs_user_input`, `failed` 중 하나다.
sources는 기존 인용 DTO(chunk_id, document_id, title, source_url, page, excerpt)이며
`document_id`는 학사 문서 UUID다. `evidence_found`는 검색 성공이며 자연어 답변이나 요건
충족을 뜻하지 않는다. 질의 응답은 [기존 assistant 응답](assistant.md)을 따른다.

### 기간·판본·캐시

- 서버 UTC 오늘의 적용 기간(양끝 포함), 현재 적용된 최신 문서 판본, 관련 규칙/묶음의
  공개 가능 상태를 검사한다. 최신 적용본에 검색 승인이 없으면 이전 판본으로 돌아가지 않는다.
- 승인된 전체 페이지를 함께 인덱싱한다. 본문 없는 검토된 빈 페이지는 범위 예외를 만들지 않는다.
  검색 문서의 다른 조건 페이지가 불완전/미승인이면 근거를 반환하지 않는다.
- 요청마다 메타데이터 ID/버전/기간을 확인하고 본문 인덱스는 학교/학과/과정·이름/버전·날짜·
  승인 문서 버전별로 재사용한다. 질문·사용자별 자료·답변을 캐시하지 않는다.
- 인덱스는 프로세스당 최대 2개, 선택 범위당 최대 32문서·2,000개 저장 part(빈 페이지 포함)·
  본문 1,000,000자다. 한도를 넘으면 failed이며 일부 페이지를 조용히 제외하지 않는다.
- 생성/검색 후 신원과 문서 선택을 다시 확인한다. 도중에 승인 회수·새 적용본·학교 메타데이터 변경이
  생기면 계산한 답변/출처를 버린다. 실제 LLM·임베딩·개인정보 외부 전송은 연결하지 않았다.

요청·응답은 no-store이며 질문·대화·답변을 DB에 저장하지 않는다. 오류는 공통 401/403/404/
409/422/429 계약을 따르고 본문·비밀번호·원본 예외를 반환하지 않는다.

## RAG 팀 JSONL 가져오기

백엔드 담당자가 먼저 학사 문서 메타데이터를 등록·적용한다. 원본 파일과 JSONL의 문서 UUID,
서버의 적용 문서 UUID는 별개이며 임의로 매핑하지 않는다. RAG 담당자는 기존 추출 모듈로
생성한 JSONL과 원본을 제공하고 관리 권한이 있는 담당자가 다음 도구로 초안을 등록할 수 있다.

```bash
# backend/에서 실행. 예시 UUID/경로/버전/확인일을 실제 검토 자료로 바꾼다.
uv run --frozen python -m scripts.import_school_knowledge \
  --corpus /private/extraction/chunks.jsonl \
  --document-id 00000000-0000-4000-8000-000000000010 \
  --source-file /private/extraction/original.pdf \
  --source-document-id 00000000-0000-4000-8000-000000000020 \
  --expected-source-version 2 --source-checked-on 2026-10-19 --dry-run
```

실제 전송에는 `--dry-run`을 빼고 `--base-url https://배포주소`,
`--credentials-file /private/admin.json`을 지정한다. 자격 파일은 email/password JSON이며
Git 밖에 두고 Unix 권한은 0600으로 제한한다. HTTPS 또는 개발용 loopback HTTP만 허용한다.
도구는 임시 bearer 세션으로 호출하고 종료 시 로그아웃한다. 비밀번호·토큰·원문은 출력하지 않는다.
서버 리다이렉트는 따라가지 않아 자격 정보나 토큰을 다른 경로/원점으로 전달하지 않는다.

원본 파일 hash와 청크 hash/전체 페이지/분할을 검증한다. 직접 확인한 빈 페이지는
`--reviewed-blank-page N`으로 별도 지정한다. 출처를 실제로 확인한 날짜를 명시하며
업로드 날짜를 출처 확인일로 추정하지 않는다. 파일의 승인 플래그·URL·학교 이름은 서버 승인이나
메타데이터를 덮어쓰지 않는다. 범위 미확인·경고는 초안으로 보존한다.

중단 후 같은 명령을 실행하면 일치하는 초안에서 같은 페이지는 건너뛰고 누락 페이지를 올린다.
기존 hash/범위/본문이 다르거나 검토자가 수정한 페이지가 있으면 멈춘다. 승인·회수본은 건드리지
않는다. 가져오기는 승인 API를 호출하지 않는다. 관리자의 별도 검토·승인 단계가 필수다.

Flutter에는 Pydantic 생성 `school_knowledge_models.dart`와 공통 AuthApi를 사용하는
`school_knowledge_api.dart`가 있다. 관리자 본문 검토 UI와 학생의 UUID 문맥 선택/검색 화면은
아직 연결하지 않았다. 재생성은 backend에서 `uv run --frozen python ../scripts/export_knowledge_contracts.py`
후 저장소 루트에서 `dart format frontend/lib/features/api/school_knowledge_models.dart`다.
