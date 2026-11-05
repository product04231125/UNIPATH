# RAG 후속 개발 및 사용법

이 문서는 `backend/app/rag/`의 독립 실행 기능을 설명한다. 별도 백엔드 통합은
[학교 지식 API](../../../docs/api/school-knowledge.md)와 [INTEGRATION.md](INTEGRATION.md)를 따른다.
기존 이름 기반 API의 요청·상태·reason·인용 형식을 유지한다.
모델·제공 업체는 미정이며, 기본 실행은 기존 오프라인 BM25다.

## 1. 입학연도별 문서 처리

`backend/`에서 실행한다. 기존 명령은 6개 페이지 청크를 그대로 생성한다.
새 옵션은 별도 출력 경로를 사용한다.

```bash
app/rag/.venv/bin/python -m app.rag.ingestion \
  --chunking year-sections --output-dir app/rag/output/sections
app/rag/.venv/bin/python -m app.rag.school search \
  '2026학번 단일전공 졸업학점은?' \
  --chunks app/rag/output/sections/chunks.jsonl \
  --institution 경동대학교 --department 컴퓨터공학과 \
  --admission-year 2026 --track single_major --preview
```

독립된 `YYYY학년도 입학자` 제목 줄을 경계로 분리한다. 현재 PDF 2개·6쪽에서는
13개 청크다. 표 머리글·행·빈 셀은 추론해 고치지 않으며 모든 텍스트를 보존한다.
공통 머리말은 별도 청크로 남긴다. 여러 이수경로 행은 같은 연도 청크에 함께 남으므로
**행 단위 숫자 구조화나 졸업 규칙 추출을 완성한 것은 아니다.**

v2의 `page_part_index/count`, 문자 구간, `page_content_hash`로 누락·중복·변조를
검증한다. 부분 청크를 순서대로 연결한 해시가 원래 페이지와 같아야 한다.
표 좌표·원시 셀은 페이지 전체 메타데이터이며 `table_metadata_scope=original_page`다.
`observed_admission_years`는 관찰값일 뿐 승인된 적용 범위가 아니다. 자동 분리는
범용 표 분석기가 아니므로 새로운 PDF는 반드시 원문과 비교한다.

## 2. 사람이 검토할 자료 준비

```bash
app/rag/.venv/bin/python -m app.rag.ingestion.review template \
  --chunks app/rag/output/sections/chunks.jsonl \
  --output app/rag/output/sections/review-template.json
```

템플릿은 `pending` 상태다. 학교 공식 URL, 적용 입학연도·이수경로, 조건·예외,
표 추출 결과를 원문과 대조한 후 검토자가 다음을 기록한다.

- `reviewer`, 시간대가 있는 `reviewed_at`.
- 청크별 `decision`: `pending`, `rejected`, `approved`.
- 승인 시 `source_url`, 명시적 `admission_years`, `tracks`, `review_note`.
- 실제로 해결한 추출 경고만 `resolved_warnings`에 기록한다.

`tracks`는 `single_major`, `double_major` 등 현재 프론트에서 전달하는 값과
일치시킨다. `null`을 전체 적용으로 취급하지 않는다. 공통 조건 청크에도 적용 범위를
명시한다. 검토 메모는 적용 범위와 예외를 확인한 근거를 남기는 용도다.

작성한 검토 파일은 원본을 덮어쓰지 않고 새 코퍼스에 적용한다.

```bash
app/rag/.venv/bin/python -m app.rag.ingestion.review apply \
  --chunks app/rag/output/sections/chunks.jsonl \
  --review app/rag/output/sections/review-completed.json \
  --output app/rag/output/sections/reviewed-chunks.jsonl
```

코퍼스 전체와 개별 원문 해시가 일치해야 한다. 검토 후 청크 ID가 새로 생성되고
원래 ID·검토 파일 해시·검토자가 기록된다. 미승인 페이지나 적용 범위가 불명확한
공통 조건이 있으면 생성하지 않는다. 완성된 템플릿 예시는 테스트의 합성 자료에만 있다.
실제 학교 PDF는 승인하지 않았다.

이 도구는 **로컬 검토 기록 도구**다. 검토자의 권한이나 학교 공식성을 인증하지 않으며
관리자 승인 DB·서명·접근 통제를 대체하지 않는다. 기존 백엔드의 로컬 코퍼스 제한을
우회하지 않는다.

## 3. 모델 공급자는 나중에 선택

`AnswerGenerator`와 `EmbeddingProvider`가 공통 경계다. 선택 가능한 HTTP 어댑터:

| 설정 | 지원 요청 형식 | 용도 |
| --- | --- | --- |
| `openai-compatible` | `/chat/completions`, `/embeddings` | 해당 형식을 지원하는 상용 API |
| `ollama` | `/api/chat`, `/api/embed` | 선택적 로컬 실험 |

OpenAI 호환은 모든 상용 API 지원을 뜻하지 않는다. JSON Schema 구조화 출력,
`max_completion_tokens`, `store=false` 등을 지원해야 한다. Claude/Gemini 등 고유 API는
팀이 선택한 뒤 별도 어댑터를 추가한다. 다른 공급자는 공통 인터페이스를 구현하면 된다.
채팅과 임베딩은 Python에서 서로 다른 공급자를 주입할 수 있다. CLI는 간단한 실험을
위해 하나의 공급자/서버 설정을 공유한다.

아래는 모델 선택과 문서 검토가 끝난 뒤 사용하는 명령 형식이다. 대문자 값은 실제
선택한 값으로 바꾼다. 키는 `RAG_API_KEY` 환경변수에 로컬로 설정하며 소스나 명령행
인자에 넣지 않는다. 공급자를 지정해도 `--allow-network` 없이는 통신하지 않는다.

```bash
app/rag/.venv/bin/python -m app.rag.school ask '사회봉사 인증 조건은?' \
  --chunks app/rag/output/sections/reviewed-chunks.jsonl \
  --institution 경동대학교 --department 컴퓨터공학과 \
  --admission-year 2026 --track single_major \
  --provider openai-compatible --base-url https://API_HOST/v1 \
  --chat-model CHOSEN_CHAT_MODEL --allow-network
```

로컬 서버를 선택하면 `--provider ollama --base-url http://127.0.0.1:11434`로 바꾼다.
자동 모델 설치·다운로드는 하지 않는다. 모델명 기본값도 없다.
`--embedding-model CHOSEN_EMBEDDING_MODEL`을 추가하면 BM25와 코사인 검색을 RRF로
합친다. `--embedding-cache app/rag/output/vectors.json`은 문서 임베딩을 재사용한다.
서버·모델 ID·본문·제목·청크 ID가 바뀌면 캐시를 다시 만든다. 모델 태그가 같은 채로
서버의 실제 모델이 바뀌면 자동 감지할 수 없으므로 고정 모델 버전을 사용하거나 캐시를
삭제해야 한다. 질문 벡터는 캐시하지 않는다. 캐시는 신뢰 가능한 로컬 파일로 취급한다.

문서 임베딩은 인덱스 초기화 시 호출되므로 상용 API 비용이 들 수 있다. 미승인 자료도
명시적으로 임베딩을 설정하면 서버에 전송된다. preview는 채팅 생성을 막지만 임베딩
검색까지 네트워크 금지로 만드는 옵션은 아니다.

구현 기준: [Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create),
[Embeddings](https://developers.openai.com/api/reference/resources/embeddings/methods/create),
[Ollama Chat](https://docs.ollama.com/api/chat), [Ollama Embed](https://docs.ollama.com/api/embed).
공급자의 실제 모델별 호환성·품질은 아직 검증하지 않았다.

## 4. 백엔드에 전달할 연결 예시

다음은 백엔드 담당자가 추후 생성기 주입 위치에서 사용할 수 있는 예시이며,
이번 작업에서 `app/services/assistant.py`를 변경하지 않았다.

```python
import os
from pathlib import Path

from app.rag.school.providers import HttpAnswerGenerator, HttpJsonTransport
from app.rag.school.retriever import SchoolRetriever, load_chunks
from app.rag.school.service import SchoolRagService

# 값들은 서버의 신뢰 가능한 설정에서 가져온다. 사용자 요청에서 받지 않는다.
transport = HttpJsonTransport(
    os.environ["RAG_BASE_URL"],
    api_key=os.environ.get("RAG_API_KEY"),
    allow_network=True,
)
generator = HttpAnswerGenerator(
    transport, dialect="openai-compatible", model=os.environ["RAG_CHAT_MODEL"]
)
service = SchoolRagService(
    SchoolRetriever(load_chunks(Path("app/rag/output/sections/reviewed-chunks.jsonl"))),
    generator=generator,
)
```

프론트 입력과 공개 응답에는 새로운 필드를 요구하지 않는다. 현재 백엔드의 기본
생성기 미연결 상태도 유지된다. 모델이 반환한 URL·페이지를 사용하지 않고 검증된
청크에서 기존 인용 필드를 구성한다. 출력 형식 오류는 기존
`invalid_generator_output`, 통신 실패는 `rag_processing_failed`로 반환한다.

HTTP 요청은 재시도·리다이렉트 없이 수행한다. 호출별 기본 12초, 서비스 질의 안에서
검색+생성이 공유하는 예산은 15초다. 본문·응답 크기와 출력 길이를 제한하고 임베딩은
16개씩 전송한다. 서비스 근거는 최대 40,000자이며 넘으면 예외를 잘라내지 않고 중단한다.
토큰 수 기반 모델별 컨텍스트 적합성은 아직 계산하지 않는다. DNS/OS 지연이나 임의로
주입한 다른 생성기를 강제 취소하는 기능은 없으므로 20초 앱 응답을 보장하지 않는다.
실제 서버 환경에서 지연·동시성·요청 제한을 검증해야 한다.

질문·근거·학교 문맥이 선택한 공급자에게 전송된다. 비식별화, 공급자 보관 정책,
사용자 동의, 운영 비용·권한 정책은 팀 통합 시 확정해야 한다. 구현에 PII 탐지기나
답변의 모든 주장에 대한 의미적 사실성 검증은 포함되지 않는다.

## 5. 검증과 남은 작업

```bash
app/rag/.venv/bin/python -m unittest discover -s app/rag/tests -v
app/rag/.venv/bin/ruff check app/rag
app/rag/.venv/bin/python -m app.rag.evals \
  --chunks app/rag/output/sections/chunks.jsonl \
  --output app/rag/output/sections/evaluation.json
```

기존 36문항 평가는 출처 페이지와 무응답 정책을 확인하는 개발용 자료다. 연도별
분리의 회귀 검증에는 유용하지만 실사용 답변 정확도나 혼합 검색 성능을 뜻하지 않는다.
추가 테스트는 원문 재구성·청크 누락·검토 해시 불일치·조건 누락 차단·API 요청 형식·
응답 파싱·가짜 인용·네트워크 비활성화·오류 정보 비노출·캐시 무효화·공유 시간 예산을
검증한다. 공급자는 합성 응답으로만 테스트하며 유료 호출을 하지 않는다.

남은 통합 조건은 공식 출처/적용 범위 검토, 모델 선정과 독립 평가, 백엔드 생성기 주입,
실제 문서 검토 후 Staging 검색/생성 통합 테스트다. 관리자 승인 저장소는 별도 백엔드 학교
지식 API에 구현했다. 개인 졸업 판정은 기존 팀 분담대로 Rule Engine
영역이며 이 모듈이 대신 계산하지 않는다.
