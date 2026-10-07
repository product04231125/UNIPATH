# AI/RAG 개발 모듈

기존 FastAPI, 프론트엔드, DB 모델, 마이그레이션, 공통 의존성을 변경하지 않고
실행하는 문서 처리·학교 근거 검색·질의 제어·평가 모듈이다. 기본 로컬 실행에는
API 키·DB·네트워크가 필요하지 않다. 공용 API에 아직 연결하지 않았다.

| 기능 | 구현 상태 |
| --- | --- |
| PDF 텍스트·표 추출, 출처·페이지 보존 | 실제 PDF 2개로 검증 |
| 한국어 BM25 검색, 학교·학과·연도·이수경로 필터 | 로컬 실행 가능 |
| 평가 데이터와 평가 명령 | 검색 26개 + 동작 10개, 개발용 |
| 질의 상태·검토 자료 격리·인용 검증 | 로컬 서비스로 구현 |
| 임베딩 | 공급자 인터페이스와 코사인 검색 구현, 실제 모델 미연결 |
| LLM | 공급자 인터페이스·근거 프롬프트·응답 검증 구현, 실제 모델 미연결 |
| DB·HTTP API·인증·프론트 연동 | 다른 담당자와 통합할 영역, 변경하지 않음 |
| OCR·공식 졸업 판정·자격증 전용 검색 | 미구현 |

기본 검색은 **단어·한국어 글자 조합을 이용하는 BM25 기준선**이다. 학습된 임베딩이나
의미 검색을 구현했다고 보아서는 안 된다. `embeddings.py`는 별도 모델을 주입받는
선택적 코사인 검색 경로이며 합성 벡터로만 테스트했다.

## 빠른 사용

아래 명령은 설치가 끝난 뒤 `backend/`에서 실행한다.

```bash
# 1. PDF 2개를 페이지 청크로 변환
app/rag/.venv/bin/python -m app.rag.ingestion

# 2. 검토용 검색: 아직 승인되지 않은 자료임을 명시적으로 허용
app/rag/.venv/bin/python -m app.rag.school search \
  '2026학번 단일전공 졸업학점은?' \
  --institution 경동대학교 --department 컴퓨터공학과 \
  --admission-year 2026 --track single_major --preview

# 3. 상태와 검색 후보를 확인 (미승인 자료에서 생성형 답변은 하지 않음)
app/rag/.venv/bin/python -m app.rag.school ask \
  '사회봉사 시간 조건은?' \
  --institution 경동대학교 --department 컴퓨터공학과 --preview

# 4. 개발용 평가와 RAG 전용 테스트
app/rag/.venv/bin/python -m app.rag.evals
app/rag/.venv/bin/python -m unittest discover -s app/rag/tests -v
```

`--preview` 없이 실행하면 승인된 근거만 사용한다. 현재 입력 문서는 전부 검토 전이므로
기본 검색 결과는 비어 있고 질의는 `insufficient_evidence`를 반환한다. 이는 의도한
동작이다. `--preview`에서도 `grounded`로 표시하거나 LLM을 호출하지 않는다.
실제 검색 후보는 `hits` 또는 `candidates`에 들어가며 공식 답변 `citations`와 구분한다.

검색은 JSONL 산출물을 메모리에 읽어 수행하며 별도 인덱스 서버를 띄우지 않는다.
검색 점수는 순위 비교용이며 답변 확률·근거 충분성 점수가 아니다. 단어가 겹치는
무관한 문서가 검색될 수 있고, 동의어·의역 질문은 놓칠 수 있다.

## 구성과 연동

```text
ingestion/          PDF 추출·페이지 청킹·CLI
school/contracts.py 내부 요청 문맥·검색 결과·질의 결과·공급자 인터페이스
school/retriever.py 코퍼스 검증·적용 범위 필터·BM25
school/embeddings.py 선택적 임베딩 공급자·코사인 검색
school/service.py   질의 상태·근거 승인 검사·문서 문맥·생성 결과 인용 검증
school/__main__.py  search / ask CLI
evals/             질문·기대 근거·동작 기대값·평가 실행기
tests/             네트워크 없는 독립 테스트
```

백엔드 담당자를 위한 호출 예시와 통합 전제는 [INTEGRATION.md](INTEGRATION.md),
평가 해석은 [evals/README.md](evals/README.md)를 참고한다. 루트 README, API·DB 모델,
공통 의존성·CI, 기존 `__init__.py` 파일은 수정하지 않았다.

## 설치와 실행

저장소 루트에서 Python 3.12로 전용 가상환경을 만든다. 아래 `.venv`는 기존
공통 `.gitignore` 규칙으로 제외된다. 기존 백엔드 환경과 분리되어 있다.

```bash
python3.12 -m venv backend/app/rag/.venv
backend/app/rag/.venv/bin/python -m pip install -r backend/app/rag/requirements-ingestion.txt
cd backend
app/rag/.venv/bin/python -m app.rag.ingestion
app/rag/.venv/bin/python -m unittest discover -s app/rag/tests -v
```

Windows에서는 `python3.12` 대신 `py -3.12`, `bin/python` 대신
`Scripts/python.exe`를 사용한다. 의존성은 pdfplumber 0.11.9 한 개를 명시했다.
통합 시 공용 `pyproject.toml`/`uv.lock` 반영은 백엔드 담당자와 조율한다.
현재 공용 Docker 이미지에는 이 선택 의존성이 설치되지 않는다.

기본 입력은 이 폴더의 `sources.json`이며 경로는 저장소 루트를 기준으로 한다.
현재 저장된 학교 PDF 2개의 SHA-256을 검증한 후 처리한다.

```bash
# backend/에서 실행. 다른 출처 목록·출력 위치 지정 가능
app/rag/.venv/bin/python -m app.rag.ingestion \
  --manifest app/rag/sources.json --output-dir app/rag/output
```

## 산출물

- `output/chunks.jsonl`: 한 줄에 한 청크. UTF-8 JSON.
- `output/report.json`: 문서·페이지별 추출 상태, 청크 ID, 표 개수, 경고.
- `output/`는 이 폴더의 `.gitignore`로 제외한다. 재실행은 추가가 아니라 교체한다.
- 동일 입력·메타데이터·추출기 버전에는 같은 청크 UUID와 결과가 생성된다.
- 원문 해시·본문·메타데이터·추출기 버전 변경 시 청크 ID가 달라질 수 있다.
  향후 DB 적재 시 문서별 이전 청크를 교체하는 처리는 별도로 구현해야 한다.
- 추출 도중 입력 오류가 발생하면 기존 산출물은 유지된다. 각 파일은 원자적으로
  교체하지만 두 파일 전체가 하나의 트랜잭션은 아니다. 동시에 실행하지 않는다.

## 청킹과 검토 정책

첫 버전은 **텍스트가 있는 한 페이지당 한 청크**다. 표의 열 간격을 보존한
`content`와 `tables`의 원시 셀·좌표를 함께 저장한다. 표 머리글, 연도 제목,
각주를 글자 수로 잘라 분리하지 않으며 긴 페이지는 자르지 않고 경고한다.
병합 셀의 `null`, 빈 문자열, `-`는 원래 추출 상태 그대로 둔다. 숫자나 조건을
추측해서 채우거나 졸업 규칙으로 변환하지 않는다.

한 페이지에 여러 연도·이수경로가 있으므로 `admission_years`, `curriculum_year`,
`track`은 `null`이다. `null`은 모든 학생에게 적용된다는 뜻이 아니라 미확인이다.
학교·학과는 입력 목록에 기록한 문서의 식별 정보이며 승인된 적용 범위가 아니다.
예를 들어 학점 문서 1쪽에는 2026·2025·2024학년도 표가 함께 존재한다.

졸업인증 문서의 1쪽 전체 조건과 2·3쪽 세부 기준처럼 페이지를 넘는 관계는
이 단계에서 자동 해석하지 않는다. 청크의 `document_id`, `page`,
`document_page_count`를 이용해 원문 전체 조건을 확인해야 한다. 후속 검색 단계에서는
관련 페이지 연결과 표별 적용 범위 검토가 필요하다. 이 단계 결과를 그대로
공식 답변이나 판정에 사용하면 안 된다.

모든 청크는 `review_status=needs_review`, `applicability_status=unverified`,
`eligible_for_official_answers=false`이다. 출처 URL은 확보되지 않아 `null`이며
실제 URL처럼 꾸며 넣지 않는다. 기존 규칙 JSON은 검토 전 초안이므로 읽거나
정답으로 활용하지 않는다. 학점 문서 ID만 기존 문서 식별자와 일치시켰다.

출처 필드: `document_id`, `title`, `source_file`, `source_url`, `page`,
`document_hash`. 재현 필드: `chunk_id`, `content_hash`, `pipeline_version`,
`extractor_version`. 표 셀은 OCR이나 시각 검증을 대체하지 않는다.

## 실패와 경고

- 종료 코드 `0`: 모든 페이지에 텍스트가 있음. 공식 근거 승인을 뜻하지 않는다.
- 종료 코드 `1`: 입력 목록·경로·해시·PDF 파싱·출력 오류.
- 종료 코드 `2`: 텍스트가 없는 페이지가 있음. 해당 페이지는 청크에서 제외하고
  보고서에 기록한다. 스캔 PDF는 별도 OCR/검토가 필요하다.
- 표 추출 실패 시 페이지 텍스트는 남기고 `table_extraction_failed`를 기록한다.
- 표가 있으면 `table_structure_requires_review`, 문자 인코딩 문제가 의심되면
  `possible_text_encoding_error`를 기록한다. 보고서를 함께 확인한다.
- 원문이 바뀌면 해시 검증이 실패한다. 변경 문서 검토 후 입력 목록의 해시를
  갱신해야 한다. 해시가 맞는다는 사실은 문서의 공식성·최신성을 보증하지 않는다.

## 검증 범위

테스트는 합성 PDF의 텍스트·빈 페이지·손상·해시 변경·잘못된 경로·표 추출 실패,
청크의 재현성·출처·배치 보존, 실제 PDF 2개의 6쪽 추출 및 반복 실행을 검증한다.
단위 테스트는 위 명령으로 독립 실행한다. 공용 테스트·CI 파일은 변경하지 않았다.

추가 테스트는 학교·학과·연도·이수경로 분리, 미승인·불완전 문서 차단, 질의 상태,
허구의 인용 ID 거부, 생성기 오류 정보 비노출, 벡터 차원·모델 변경 검증을 포함한다.
현재 RAG 전용 테스트는 총 44개다. 외부 모델·실제 DB·브라우저 통합 검증은 포함하지 않는다.
