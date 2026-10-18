# RAG 개발용 평가

`questions.jsonl`은 보관 PDF 2개를 바탕으로 만든 36개 평가 사례다.
학교가 승인한 정답집이나 독립적인 최종 성능 시험이 아니다. 문서 내용의 최신성·
공식 적용 범위 검토와 모델 선정 후에는 팀원이 작성한 별도의 미공개 질문으로 평가한다.

## 구성

- 검색 26개: 입학연도 2018~2026, 단일전공·복수전공·부전공·직장인, 창의·전공
  인증, 봉사 시간 구분, 자격증·실습·취업 조건. 여러 페이지가 필요한 질문도 포함.
- 동작 10개: 학교 문맥 누락, 연도·이수경로 누락, 개인 졸업 판정 요청, 미승인 자료,
  검토 모드, 지원하지 않는 학교·학과, 연도 충돌, 빈 질문, 문서 밖 주제.
- 검색 정답은 문장 생성 결과가 아니라 `document_id + page + quote`다.
  청크 ID는 추출 방식이 달라지면 변경되므로 정답 키로 사용하지 않는다.
- `source_versions.json`은 평가 근거의 원문 SHA-256이다. 원문 버전이 달라지거나
  기대 발췌를 페이지에서 찾지 못하면 평가를 중단하고 정답 검토를 요구한다.
- 원문 검토 기반의 개발 초안이다. 평가에 있는 인용 문구는 적용 요건 전체를
  대체하지 않는다. 특히 학점 조건과 졸업인증 조건을 합쳐 졸업 여부를 판정하지 않는다.

## 실행

```bash
# backend/에서 실행
app/rag/.venv/bin/python -m app.rag.ingestion
app/rag/.venv/bin/python -m app.rag.evals
# 더 엄격하게 첫 번째 검색 결과만 확인
app/rag/.venv/bin/python -m app.rag.evals --top-k 1 --output app/rag/output/evaluation-top1.json
```

기본 보고서는 `app/rag/output/evaluation.json`이며 Git에서 제외된다.
종료 코드는 전체 사례 통과 0, 기대 근거/동작 불일치 1, 입력 오류 2다.

## 수치 해석

| 지표 | 의미 |
| --- | --- |
| Hit@k | 기대 페이지 중 하나 이상이 상위 k개에 포함된 질문 비율 |
| Mean Recall@k | 질문마다 필요한 페이지가 얼마나 검색됐는지의 평균 |
| MRR@k | 최초로 맞는 페이지가 등장한 순위의 역수 평균 |
| Behavior pass rate | 기대 상태·원인·누락 필드·후보 유무가 일치한 비율 |

검색 사례 통과는 **필요한 페이지 모두가 상위 k개에 포함됨**을 요구한다.
현재 6개 페이지 코퍼스의 개발용 상위 3개 검색을 확인하는 작은 시험이므로,
26개 검색 사례가 모두 통과해도 실제 사용자 질문에 대한 정확도 100%를 뜻하지 않는다.
LLM 답변 정확성, 운영 필터 권한, 대규모 검색 성능, 응답 비용은 측정하지 않는다.

향후 질문을 추가할 때 정상 질문뿐 아니라 같은 단어지만 무관한 질문, 의역, 문서
충돌, 페이지를 넘는 예외, 개인정보 포함 질문을 추가한다. 모델 개발에 사용한 질문과
최종 평가 질문을 분리하고, 최종 평가 결과에 맞춰 계속 정답이나 검색 규칙을 조정하지 않는다.


## 연도별 청크 평가

`--chunks app/rag/output/sections/chunks.jsonl`로 선택적 v2 산출물도 평가할 수 있다.
같은 페이지의 부분 청크를 순서대로 합쳐 기대 인용문을 확인한다. 검색 순위는 청크 단위,
기대 근거·recall은 페이지 단위다. 같은 페이지의 여러 부분이 상위 k개에 포함될 수 있다.
따라서 v1/v2 점수를 곧바로 실사용 정확도 비교로 해석하지 않는다. 연도 혼합 방지와
공통 조건 보존은 `tests/test_scope_review.py`에서 별도로 검증한다.

## 2026-10-18: 조건 검증 및 저장된 답변 평가

검색 사례 통과에는 이제 페이지 일치뿐 아니라 **검색된 청크 안의 기대 발췌**도 필요하다.
`forbidden_evidence`에 지정한 발췌가 검색 결과에 포함되면 실패한다. 기존 page 기반
Hit/Recall/MRR 수치는 유지하며 세부 결과의 `evidence_check`를 함께 확인한다.

`scope_questions.jsonl`의 12문항은 다른 입학연도 혼합을 검사한다. 기본 페이지 청킹은
여러 연도 표를 보존하므로 이 엄격한 평가에서 실패하는 것이 예상된다. 연도별 옵션과
비교하는 회귀 검사이며 이를 이유로 기존 기본 파이프라인을 변경하지 않았다.

```bash
# backend/ 기준, 모델·네트워크 불필요
app/rag/.venv/bin/python -m app.rag.ingestion \
  --chunking year-sections --output-dir app/rag/output/sections
app/rag/.venv/bin/python -m app.rag.evals \
  --chunks app/rag/output/sections/chunks.jsonl \
  --cases app/rag/evals/scope_questions.jsonl \
  --output app/rag/output/sections/scope-evaluation.json
app/rag/.venv/bin/python -m app.rag.ingestion.readiness \
  --chunks app/rag/output/sections/chunks.jsonl \
  --output app/rag/output/sections/readiness.json
```

점검 종료 코드: 0은 로컬 범위 지정 시험용 메타데이터 조건 충족, 1은 미검토/누락,
2는 잘못된 입력이다. 현재 학교 자료는 **1이 정상**이다. ready 표시도 관리자 권한·
공식성·운영 승인·유효기간·답변 정확성을 보증하지 않는다. 점검은 파일을 승인/수정하지 않는다.

### 저장된 답변의 오프라인 검사

```bash
app/rag/.venv/bin/python -m app.rag.evals.answers \
  --chunks app/rag/evals/examples/synthetic-chunks.jsonl \
  --cases app/rag/evals/examples/synthetic-cases.jsonl \
  --predictions app/rag/evals/examples/synthetic-predictions.jsonl \
  --output app/rag/output/answer-evaluation.json
```

`examples/`는 도구 실행을 보여주는 **합성 자료**다. 학교 사실이나 실제 모델 성능의
정답집이 아니며 학교 코퍼스에 섞지 않는다. 향후 모델을 선택하면 같은 형식으로
저장한 결과를 평가할 수 있다. 이 명령 자체는 API를 호출하지 않는다.

- cases: `id`, `expected_status`, `expected_reason`, 선택적 `context`, `missing_fields`.
- grounded cases: `source_versions`(문서 ID→원문 SHA-256), `evidence`(문서 ID/페이지/발췌).
- `required_patterns`, `forbidden_patterns`: 사람이 작성한 Python 정규식 목록. 숫자 경계,
  단위, 조건·예외 표현을 구체적으로 지정한다. 동일 ID의 prediction이 정확히 하나 필요하다.
- predictions: `{"id": "사례 ID", "result": 기존 QueryResult.as_dict() 또는 API 응답}`.
- 보고서: 사례 ID·실패 코드만 기록한다. 질문·답변·발췌 원문은 복사하지 않는다.
- 종료 코드: 전체 통과 0, 결과 불일치 1, 누락/중복 ID·원문 변경 등 입력 오류 2.

인용은 실제 코퍼스의 ID·제목·URL·페이지·본문과 비교하고 승인/문맥을 검사한다.
공개 API와 내부 QueryResult의 추가 필드 차이는 허용한다. 이 도구는 전체 OpenAPI
검증기나 의미적 사실성 판정기가 아니다. '36시간이 아니다'도 느슨한 패턴에는 맞을 수
있다. 패턴 통과만으로 정확하다고 결론 내리지 말고 독립 검토자가 주장·부정·예외·
이수경로와 표의 숫자 관계를 확인해야 한다. 정규식은 신뢰 가능한 팀 작성 파일만 사용한다.

합의할 항목과 담당자별 질문은 [TEAM_DECISIONS.md](../TEAM_DECISIONS.md)에 정리했다.
