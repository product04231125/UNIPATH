# 백엔드 담당자에게 전달할 AI/RAG 인터페이스

이 문서는 연결 방법을 제안한다. 공용 FastAPI 라우터·외부 API 스키마를 추가하거나
변경하지 않았다. `app/rag/` 내 데이터 클래스는 내부 모듈용이며, 공개 API 계약은
백엔드 담당자와 합의하여 `app/schemas/`에서 정의해야 한다.

## 실제 호출 예시

`backend/`를 Python 실행 경로로 사용한다. 설치 후 DB·API 키 없이 호출 가능하다.

```python
from pathlib import Path

from app.rag.school.contracts import SchoolContext
from app.rag.school.retriever import SchoolRetriever, load_chunks
from app.rag.school.service import SchoolRagService

retriever = SchoolRetriever(load_chunks(Path("app/rag/output/chunks.jsonl")))
service = SchoolRagService(retriever)
result = service.query(
    "사회봉사 시간 조건은?",
    SchoolContext(institution="경동대학교", department="컴퓨터공학과"),
    preview=True,  # 개발 도구 전용. 사용자 요청으로 공식 모드에서 전환하지 않는다.
)
payload = result.as_dict()
```

새 요청마다 전체 코퍼스를 읽고 인덱싱하지 말고 애플리케이션의 적절한 수명 동안
재사용한다. 현재 함수는 동기 방식이다. 향후 네트워크 공급자를 연결하면 타임아웃,
동시성·비용 제한과 비동기 라우터에서의 실행 방식을 백엔드에서 정해야 한다.
request_id, 인증·권한, HTTP 상태, 요청 제한은 이 모듈에 구현되어 있지 않다.

## 입력과 결과

`SchoolContext`는 학교·학과의 **정규화된 이름**, 입학연도 정수,
`single_major` 같은 이수경로 문자열을 사용한다. 현재 로컬 자료에 학교 UUID가 없어서
이름을 비교하며 별칭 추론은 하지 않는다. 공용 DB의 UUID→이름 또는 ID 기반 필터로
전환하는 계약은 통합 시 합의해야 한다. 백엔드가 검증한 문맥만 전달해야 한다.

`QueryResult` 필드:

| 필드 | 의미 |
| --- | --- |
| `status` | grounded / insufficient_evidence / needs_user_input / failed |
| `answer` | 생성된 답변 또는 null |
| `reason` | 모듈 내부 원인 코드 |
| `citations` | 생성기가 실제 사용한 승인 근거의 식별자·출처·페이지·발췌 |
| `candidates` | preview 전용 미승인 검색 후보. 공식 답변 근거와 구분 |
| `missing_fields` | 추가로 필요한 문맥 필드 |
| `warnings` | 개발용 검토 안내 |

대표 원인: `school_context_required`, `academic_scope_required`,
`conflicting_admission_year`, `rule_engine_required`, `no_approved_matching_evidence`,
`preview_only`, `document_context_not_approved_or_incomplete`,
`answer_generator_not_configured`, `invalid_generator_citations`, `rag_processing_failed`.

졸업 가능 여부를 묻는 대표 표현은 Rule Engine 경로로 넘기도록 처리한다. 정규식은
모든 의역을 알아내는 의도 분류기가 아니다. 개인 졸업 판정의 최종 경로는 백엔드에서
명시적으로 분리해야 하며 이 모듈에 판정을 위임하면 안 된다.

## 공식 근거 조건

`eligible_for_official_answers=true`, `review_status=approved`,
`applicability_status=verified`, 출처 URL 존재, 추출 검토 경고 해결이 모두 필요하다.
연도·이수경로 필터가 주어졌는데 근거의 적용 범위가 null이면 공식 검색에서 제외한다.
조건·예외를 놓치지 않도록 같은 문서의 승인된 적용 범위 페이지를 생성기에 함께
전달한다. 일부 페이지가 빠지거나 문서의 다른 페이지가 미승인이면 생성하지 않는다.

현재 PDF는 모든 조건을 충족하지 않는다. 테스트의 `approved` 데이터는 합성 자료이며
실제 PDF를 승인한 것이 아니다. 파일의 플래그 자체는 접근 제어나 승인 시스템이
아니다. 실제 승인은 관리 권한, 검토자, 적용 교육과정·시행 기간·문서 버전과 함께
DB에서 보장해야 한다. 현재 모듈은 신뢰할 수 있는 로컬 입력을 가정한다.

페이지 청크 하나에 여러 연도와 이수경로가 포함되어 있다. 명시적인 표별 적용 범위
검토와 학교 공식 출처 확인 후 통합해야 한다. 날짜 유효성·학교 공통 규정 상속·교육과정
ID 선택은 아직 구현되지 않았으므로 해당 계약이 확정되기 전 운영 답변에 사용하지 않는다.

## 임베딩 공급자 연결

`EmbeddingProvider`는 `model_id`, `embed_documents(texts)`, `embed_query(text)`를 제공한다.
같은 모델·차원의 벡터만 사용하며 빈 벡터, NaN, 0벡터, 차원·모델 변경을 거부한다.

```python
from app.rag.school.embeddings import EmbeddingRanker

# provider는 팀이 선택한 모델의 실제 구현체
ranker = EmbeddingRanker(chunks, provider)
retriever = SchoolRetriever(chunks, ranker=ranker)
```

현재 메모리 코사인 검색이며 pgvector 테이블 저장·색인·마이그레이션은 구현하지 않았다.
실제 임베딩 모델의 검색 성능도 아직 측정하지 않았다. BM25와 같은 평가 문제로 비교한
뒤 모델·차원·비용을 합의할 수 있다.

## LLM 공급자 연결

`AnswerGenerator.generate(GroundingRequest)`가 `GeneratedAnswer`를 반환하도록 구현한다.
요청에는 고정 시스템 지침, 질문, 최소한의 학교 문맥, 근거별 chunk_id·본문이 들어간다.
반환값은 `answer`, `citation_ids`, boolean `insufficient_evidence`다.
URL·페이지·제목은 생성기에게 맡기지 않고 검색 원본에서만 구성한다.

현재 실제 LLM 공급자·키·모델은 선택하지 않았다. 네트워크 호출 전에 질문의 개인정보
최소화/비식별화 계층과 요청 제한·타임아웃을 연결해야 한다. 이 모듈은 개인정보
탐지기나 PII 제거기를 구현했다고 주장하지 않는다. 비밀값은 공급자 구현에서 관리하고
API 오류의 원문이나 키를 사용자 결과에 노출하지 않는다.

인용 ID 검증은 허구의 출처를 막지만 **인용한 문서가 답변의 모든 주장을 뒷받침한다는
의미 검증은 아니다**. 실제 생성기를 연결한 뒤 사실성·조건 보존·프롬프트 주입·불충분
근거 응답 평가를 추가해야 한다. 공식 문서 검토와 모델 선택 전에는 검색 preview로만 사용한다.
