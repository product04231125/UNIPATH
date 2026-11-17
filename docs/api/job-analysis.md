# 개인화 문맥과 채용 분석 최소 계약

공고 원문 1개와 선택한 개인 기록을 비교하는 계약이다. 분석기는 Vertex AI의 Gemini로 연결했고
`VERTEX_PROJECT`, `VERTEX_LOCATION`, `VERTEX_MODEL`을 모두 설정해야 동작한다. 설정 전에는
`not_configured`를 반환한다. LLM 설명만으로 충족을 판정하지 않는다.
학교 공통 문서는 기존 `/me/school-searches`, `/me/school-queries`에서 검색하고 개인 기록은
별도로 조립한다. 둘을 함께 쓰는 흐름은 [맞춤 안내](personalized-guidance.md)를 따른다.

## 요청

`POST /api/v1/me/personalization-contexts`는 기존 로그인·세션으로 본인 자료만 조회한다.

```json
{
  "records": [
    {
      "kind": "experience",
      "record_id": "59579706-6788-48c2-82ad-6af17570a394",
      "expected_version": 1
    }
  ]
}
```

UUID는 합성 예시다. 실행에는 기존 개인 자료 API에 저장한 본인 UUID·버전을 사용한다.
종류는 `course`, `activity`, `experience`, `credential`, `achievement`이며 최대 20개다.
중복은 거부하고 빈 선택은 빈 문맥을 반환한다. 응답 `records`에는 종류·UUID·버전과
`origin=personal`, `official=false`, `title`, `text`, `truncated`가 있다.
`text`는 제목·설명과 필요한 필드를 조합하며 8000자 초과 시 자르고 표시한다.
소유자·연락처 필드·링크·학교 승인 관찰 필드는 조립하지 않는다. 자유 텍스트는
신뢰하지 않는 개인 주장이다. 공용 코퍼스나 공식 학교 자료로 승격하지 않는다.

`POST /api/v1/me/job-analyses`는 같은 `records`와 앞뒤 공백 제거 후 1~20000자인
`posting_text`, `external_processing_consent`를 받는다. URL·임의 프로필·사용자 ID·승인 플래그는
거부한다. 공고·문맥·결과를 저장하지 않으며 UUID `analysis_id`는 요청 식별자다.
사용자별 15분당 30회로 제한한다. `X-Unipath-Owner` 사전조건을 지원한다.

## 외부 전송

[D6 결정](../../backend/app/rag/TEAM_DECISIONS.md)에 따라 다음 조건을 지킨다.

- `external_processing_consent`는 요청마다 `true`여야 한다. 기본값은 `false`이며 저장하지 않는다.
  화면에서 선택한 기록이 Google로 전송된다는 점을 알린 뒤 받는다.
- 학생이 고른 기록만 보낸다. 소유자·연락처 필드·링크·학교 승인 필드는 조립 단계에서 뺀다.
- 자유 입력의 이메일, 전화번호, 주민등록번호, 학번, 링크, 본인 이름은 전송 전에 표식으로 바꾼다.
  다른 사람의 이름이나 서술로 드러나는 정보까지 지우지는 못한다.
- 인용은 전송된 내용 기준이므로 응답의 `excerpt`에도 표식이 보일 수 있다.
- 프롬프트와 응답 본문은 로그에 남기지 않는다. 실패 시 예외 종류만 기록한다.
- 전체 호출은 `LLM_REQUESTS_PER_15_MINUTES`(기본 60)로 제한하고, 초과하면 공통 429다.
  월 비용 한도는 클라우드 계정에서 설정한다.

## 응답과 검증

| status | reason | 의미 |
|---|---|---|
| `needs_user_input` | `personal_records_required` | `missing_fields=["records"]` 선택 안내 |
| `needs_user_input` | `external_processing_consent_required` | `missing_fields=["external_processing_consent"]` 동의 필요 |
| `not_configured` | `analyzer_not_configured` | Gemini 미설정 |
| `insufficient_evidence` | `no_requirements_found` | 요건 추출 근거 없음 |
| `completed` | `compared_with_personal_evidence` | 인용 검증을 통과한 비교 목록 |
| `failed` | `analysis_failed` | 공급자 출력·처리 오류 차단 |

상태 응답은 HTTP 200이며 `official=false`다. `completed`에만 최대 50개 `comparisons`가 있다.

유효한 본인 기록을 선택했지만 Gemini가 설정되지 않은 응답은 다음과 같다.

```json
{
  "analysis_id": "cbd758f4-62fb-4d60-a343-71197cd97311",
  "status": "not_configured",
  "reason": "analyzer_not_configured",
  "official": false,
  "comparisons": [],
  "missing_fields": []
}
```

각 항목은 UUID `requirement_id`, `priority=required|preferred`, `requirement`,
`posting_evidence`, `status`, `personal_evidence`, `explanation`이다.
공고 근거의 `start`, `end`, `excerpt`는 공백 제거한 입력의 Python 문자열 `[start:end]`와
일치해야 한다. UTF-8 바이트나 JavaScript UTF-16 오프셋이 아니다. 같은 문구가 공고에 반복되면
아직 인용하지 않은 위치에 연결하고, 공고에 없는 문구는 전체 결과를 차단한다.
비교 상태는 `supported`, `partially_supported`, `insufficient_evidence`이며 앞의 두 값은
개인 인용이 필수다. 개인 인용의 `kind`, `record_id`, `version`, `excerpt`가 선택 자료와
일치해야 한다. 없는 인용·다른 버전·중복 요건 ID는 전체 결과를 차단한다.
구조·출처 검증만으로 의미적 정확성을 보장하지 않으며 실제 자격 확인·합격 예측이 아니다.

로그인 누락 401, 타인/삭제 자료 404, 버전 충돌 409, 검증 실패 422, 제한 429는 공통 오류다.
분석 후에도 로그인·기록 버전을 다시 확인한다. 보호 응답은 `no-store`이고 개인 입력과
공급자 오류를 로그에 남기지 않는다.

프런트는 공고 입력·기록 선택·결과 화면, AI/RAG는 추출·비교·설명을 담당한다.
타입은 `scripts/export_job_analysis_contracts.py`로 재생성한다.
`tests/test_job_analysis.py`의 합성 어댑터는 Python 필수/FastAPI 우대 공고와 Python 경험
1개를 비교해 각각 근거 있음·근거 부족을 반환한다. 미연결, 소유권, 버전, 허위 인용과
분석 중 변경을 함께 검사한다.

## 공고 추천

`POST /api/v1/me/job-recommendations`는 학생이 고른 파일(사진·PDF·DOCX·TXT, 최대 5개·8MiB)과 기록으로
최대 3건의 공고를 비교한다. 기본 API가 함께 제공하며 채용 분석과 같은 Gemini 설정·호출 상한을 쓴다.
파일은 동의가 있을 때만 서버에서 추출·OCR하고 원본을 보관하지 않는다. 계약·응답 예시는
[`backend/app/rag/career/DOCUMENT_RECOMMENDATIONS.md`](../../backend/app/rag/career/DOCUMENT_RECOMMENDATIONS.md),
서버 설정은 [`SERVER_HANDOFF.md`](../../backend/app/rag/career/SERVER_HANDOFF.md)를 따른다. 이 경로와
`/me/personalized-guidance`만 프록시 본문 12m, 응답 대기 180초다.

## 품질 평가

`backend/tests/fixtures/job_analysis_scenarios.json`은 대표 공고와 합성 기록 5건이다. 정상 비교,
필수 자격 미보유, 요구사항 없는 소개문, 지시문 삽입, 반복 문구를 다룬다.
Gemini 설정 후 `backend/`에서 다음을 실행한다. 합성 자료만 전송한다.

```bash
uv run --frozen python -m scripts.evaluate_job_analysis --live
```

`job_analysis_representative.json`은 대표 공고 12건이다. 백엔드·프론트·데이터·클라우드·보안·
임베디드·QA·공공기관(NCS)·모바일 직무와 상투 문구, 관련 기록 없음, 기록 속 지시문을 다룬다.
각 시나리오는 추출해야 할 요구사항(`requirement_keywords`), 근거 있음으로 판단하면 안 되는
요구사항(`not_supported_keywords`), 요구사항으로 뽑으면 안 되는 문구(`not_requirement_keywords`)를
가진다. 모든 결과는 합격·채용 가능성 단정 문구가 없어야 한다.

```bash
uv run --frozen python -m scripts.evaluate_job_analysis --live --representative --repeat 3 \
  --output /tmp/job-analysis-eval.json
```

요약에는 통과 수, 거절 수와 원인(`posting_quote`, `personal_citation`, `classification`,
`output_shape`), 요구사항 재현율, 반복 실행 간 상태가 같은 시나리오 수, 응답 시간 p50/p95/max가
나온다. `--output`에는 시나리오별 비교와 설명문이 저장되므로 합성 자료로만 실행한다.

### 2026-11-15 측정

스테이징 설정(`asia-northeast1`, `gemini-3.5-flash`)과 같은 API 이미지로 측정했다. 공고와 기록은
모두 합성이다. 개발자가 만든 기대값 기준이며 독립 평가가 아니다.

| 세트 | 호출 | 통과 | 검증 거절 | 요구사항 재현율 | 상태 안정 | p50 | p95 | 최대 |
|---|---|---|---|---|---|---|---|---|
| 대표 12건 × 3회 | 36 | 36 | 0 | 100% | 11/12 | 5.5초 | 8.4초 | 9.9초 |
| 기존 5건 × 3회 | 15 | 15 | 0 | 해당 없음 | 5/5 | 5.3초 | 10.6초 | 11.3초 |
| 대표 12건 × 1회(설명문 검토) | 12 | 12 | 0 | 100% | - | 4.7초 | 6.4초 | - |

- 흔들린 1건은 `mobile_kotlin_mixed`다. "Kotlin 안드로이드 개발" 요건을 Java 안드로이드 기록에 대해
  2회는 일부 근거, 1회는 근거 부족으로 판단했다. 두 판단 모두 근거 있음은 아니다.
- 설명문은 기록에 있는 사실만 들었고 없는 경험은 "확인할 수 없다"고 썼다. 필기만 합격한
  자격은 일부 근거로 구분했다. 기록 속 지시문은 따르지 않았다.
- "필수 지원 자격을 충족합니다"처럼 지원 자격 충족을 단정하는 문장이 1건 있었다. 금지 문구는
  아니지만 화면에서는 "기록상 확인됨"으로 읽히도록 안내 문구를 함께 보여 주는 것이 안전하다.
- 실패 경로는 격리 API에서 확인했다. 모델 오류는 1.8초 안에 `failed`/`analysis_failed`,
  미설정은 `not_configured`, 호출 상한 초과는 429 `RATE_LIMITED`다. 로그에는 예외 종류만 남았다.
