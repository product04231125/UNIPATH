# 목표 직무 분석(직무 갭 분석) API

`POST /api/v1/me/career-gap-analyses`는 학생의 목표 직무 공고 여러 건이 공통으로 요구하는 조건을 모은다.
그 조건을 저장된 기록 전체(수강·활동·경험·자격·성과)와 비교하고, 부족한 조건마다 준비 행동을 제안한다.
이 API는 결과를 저장하지 않는다. 앱이 끝난 결과를 [저장된 분석 결과](materials-and-results.md)로 계정에 남기고, 최근 결과는 기기에도 두어 홈 요약에 쓴다. 합격 가능성이나 지원 자격
판정이 아니며 항상 `official=false`다.

## 요청

```json
{
  "records": [{"kind": "course", "record_id": "UUID", "expected_version": 1}],
  "category_codes": [],
  "keyword": "",
  "external_processing_consent": true
}
```

- `category_codes`·`keyword`: 둘 다 비면 저장된 목표 직무(`GET /me/career-goal`)를 쓴다. 직종 전체 분석은
  목표 직무의 코드만 보내고 `keyword`를 비운다.
- `records`: 저장 기록 전체(최대 200개). 문서 파일은 받지 않는다.
- 동의 없음 → `needs_user_input`(`external_processing_consent`), 목표 직무 없음 → `career_goal`,
  기록 없음 → `records`. 모델이 설정되지 않으면 `not_configured`.
- 사용자당 15분 10회, 모델 호출은 전체 호출 상한(`llm:global`)을 함께 쓴다.

## 처리

1. 고용24에서 목표 직무 공고를 최대 10건 모은다(직종 코드 필터, 수집 상한 40초). 공고 본문이 있는 것만 최대 8건
   비교한다. 학생 기록과 가까운 공고를 고르지 않도록 기록 기반 정렬은 끈다.
2. 모델 호출 1회로 요건을 최대 10개로 묶는다. 요건마다 언급한 공고 번호와 그 공고의 문장을 인용한다.
   제한 시간은 110초이고 출력 한도는 24,576토큰이다.
3. 서버 검증:
   - 공고 인용은 그 공고 본문에서 찾은 것만 남긴다(띄어쓰기 차이는 허용).
   - `frequency`는 인용이 확인된 공고 수다. 확인된 공고가 없는 요건은 뺀다.
   - 기록 인용이 확인되지 않은 `supported`·`partially_supported`는 `insufficient_evidence`로 바꾼다. 이때
     설명은 기록 작성 안내로 대체한다.
   - 준비 행동은 종류(`certificate|activity|project|course|study`)·길이·기간(1~26주)을 검사한다.
4. 공고가 0건이면 `no_postings`를 돌려준다. 세부 검색어 때문에 0건이면 `category_browse_available=true`와
   `search_notice`를 함께 준다. 다른 공고로 채우지 않는다(2026-11-22 결정).

## 응답 (`status=completed`)

```json
{
  "status": "completed",
  "official": false,
  "goal": {"category_codes": ["024"], "keyword": "", "label": "소프트웨어"},
  "postings": [{"posting": 1, "source": "work24", "source_id": "…", "title": "…", "company": "…",
                "location": "…", "url": "https://www.work24.go.kr/…", "closing_label": "…",
                "expires_at": null}],
  "requirements": [{
    "requirement_id": "UUID",
    "requirement": "정보처리기사",
    "category": "certificate",
    "frequency": 2,
    "postings": [{"posting": 1, "excerpt": "우대: 정보처리기사"}],
    "status": "insufficient_evidence",
    "personal_evidence": [],
    "explanation": "…",
    "actions": [{"type": "certificate", "title": "정보처리기사 필기", "detail": "…", "weeks": 6}]
  }],
  "summary": "…",
  "warnings": ["목표 직무 공고가 2건만 수집되어 공통 요건이 적게 나올 수 있습니다."],
  "sources": [],
  "search_notice": null,
  "category_browse_available": false,
  "model": "gemini-3.5-flash",
  "generated_at": "2026-11-23T03:00:00+00:00"
}
```

- 요건은 `frequency`가 큰 순서, 같으면 준비가 필요한 것부터 정렬한다. 앱은 상태를 `준비됨`·`일부 준비됨`·
  `준비 필요`로 보여 준다(증거 판정 표현을 쓰지 않는다).
- 실패 시 `status=failed`와 고정 코드 `failure_reason`만 준다. 공고·기록·모델 출력은 로그에 남기지 않는다.

## 앱

- `채용공고 분석` → `목표 직무 분석`. 홈의 `목표 직무 분석` 카드에서도 연다.
- 준비 행동의 `일정에 추가`는 학생이 목표일을 고른 뒤 개인 일정(분류: 자격증은 마감, 그 밖은 활동)으로 저장한다.
- 자격증 행동에는 Q-Net 확인 링크를 붙인다. 시험 일정·응시 자격은 공식 사이트에서 확인하게 한다.
- 앱·게이트웨이 프록시는 이 경로의 응답을 180초까지 기다린다.

## 실측 (2026-11-23, 고용24 소프트웨어 024, 합성 기록 3개)

공고 8건 수집 4초, 모델 35초(합계 39초). 요건 7개(실무 경력 5건, 오피스 4건, SQL·정보처리기사 2건 등).
React·API·Git은 기록 근거와 함께 `준비됨`, 부족 조건마다 자격증·프로젝트 제안이 나왔다.
