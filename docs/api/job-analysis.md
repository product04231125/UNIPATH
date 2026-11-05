# 개인화 문맥과 채용 분석 최소 계약

공고 원문 1개와 선택한 개인 기록을 비교하는 계약이다. 실제 AI 분석기는 미연결이며
기본 앱은 `not_configured`를 반환한다. AI/RAG는 `JobAnalyzer.analyze(posting_text, context)`에
요건 추출·비교·설명을 연결한다. LLM 설명만으로 충족을 판정하지 않는다.
학교 공통 문서는 기존 `/me/school-searches`, `/me/school-queries`에서 검색하고
개인 기록은 별도로 조립한다. 개인화 학교 답변 생성과 외부 공급자 연결은 후속이다.

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
`posting_text`를 받는다. URL·임의 프로필·사용자 ID·승인 플래그는 거부한다.
공고·문맥·결과를 저장하지 않으며 UUID `analysis_id`는 요청 식별자다.
사용자별 15분당 30회로 제한한다. `X-Unipath-Owner` 사전조건을 지원한다.

## 응답과 검증

| status | reason | 의미 |
|---|---|---|
| `needs_user_input` | `personal_records_required` | `missing_fields=["records"]` 선택 안내 |
| `not_configured` | `analyzer_not_configured` | 실제 분석기 미연결 |
| `insufficient_evidence` | `no_requirements_found` | 요건 추출 근거 없음 |
| `completed` | `compared_with_personal_evidence` | 인용 검증을 통과한 비교 목록 |
| `failed` | `analysis_failed` | 공급자 출력·처리 오류 차단 |

상태 응답은 HTTP 200이며 `official=false`다. `completed`에만 최대 50개 `comparisons`가 있다.

유효한 본인 기록을 선택했지만 실제 분석기가 미연결인 현재 기본 응답은 다음과 같다.

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
일치해야 한다. UTF-8 바이트나 JavaScript UTF-16 오프셋이 아니다.
비교 상태는 `supported`, `partially_supported`, `insufficient_evidence`이며 앞의 두 값은
개인 인용이 필수다. 개인 인용의 `kind`, `record_id`, `version`, `excerpt`가 선택 자료와
일치해야 한다. 없는 인용·다른 버전·중복 요건 ID는 전체 결과를 차단한다.
구조·출처 검증만으로 의미적 정확성을 보장하지 않으며 실제 자격 확인·합격 예측이 아니다.

로그인 누락 401, 타인/삭제 자료 404, 버전 충돌 409, 검증 실패 422, 제한 429는 공통 오류다.
분석 후에도 로그인·기록 버전을 다시 확인한다. 보호 응답은 `no-store`이고 개인 입력과
공급자 오류를 로그에 남기지 않는다. 외부 연결 시 개인정보 전달 정책을 확인해야 한다.

프런트는 공고 입력·기록 선택·결과 화면, AI/RAG는 추출·비교·설명을 담당한다.
타입은 `scripts/export_job_analysis_contracts.py`로 재생성한다.
`tests/test_job_analysis.py`의 합성 어댑터는 Python 필수/FastAPI 우대 공고와 Python 경험
1개를 비교해 각각 근거 있음·근거 부족을 반환한다. 미연결, 소유권, 버전, 허위 인용과
분석 중 변경을 함께 검사한다. 실제 공고 분석 품질 평가는 AI/RAG 연결 후 진행한다.
