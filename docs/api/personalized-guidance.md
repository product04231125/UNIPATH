# 학교 근거와 개인 기록을 분리한 맞춤 안내

`POST /api/v1/me/personalized-guidance`는 학교 공통 자료와 학생이 고른 개인 기록을 함께 쓰되
섞지 않는다. 학교 기준은 승인된 학교 문서에서만 가져온다. 개인 기록은 학교 근거, 공식 판정,
공용 검색 대상이 되지 않는다. 이 응답은 졸업 판정이 아니며 항상 `official=false`다.

## 요청

```json
{
  "question": "사회봉사 승인 조건은?",
  "context": {
    "institution_id": "UUID",
    "department_id": "UUID",
    "curriculum_id": null,
    "admission_year": 2026,
    "track": "single_major"
  },
  "records": [
    {"kind": "activity", "record_id": "UUID", "expected_version": 1}
  ],
  "external_processing_consent": true
}
```

`context`는 `/me/school-searches`와 같다. 기록은 최대 20개이며 본인 자료만 선택할 수 있다.
타인·삭제 자료는 404, 버전 충돌은 409다. 사용자별 15분당 30회로 제한한다.

## 응답

학교 자료와 개인 기록은 항상 별도 필드다.

- `school`: `/me/school-searches`와 같은 결과. 개인 기록을 포함하지 않는다.
- `personal`: 식별 정보를 제거한 개인 문맥. 외부로 나갈 수 있는 내용 그대로다.
- `answer`, `school_chunk_ids`, `personal_citations`: `grounded`일 때만 값이 있다.

| status | reason | 의미 |
|---|---|---|
| `grounded` | `generated_from_separated_evidence` | 인용 검증을 통과한 답변 |
| `evidence_only` | `generator_not_configured` | 모델 미설정. 두 자료를 나눠 표시 |
| `needs_user_input` | `personal_records_required` | 기록 선택 필요 |
| `needs_user_input` | `external_processing_consent_required` | 외부 전송 동의 필요 |
| `needs_user_input` | `school_evidence_unavailable` | `school.reason`의 입력이 필요. 졸업 판정 질문 포함 |
| `insufficient_evidence` | `school_evidence_unavailable` | 승인 근거 없음 또는 생성 중 회수 |
| `insufficient_evidence` | `generator_reported_insufficient_evidence` | 모델이 근거 부족으로 응답 |
| `failed` | `school_evidence_unavailable` | 학교 검색 실패 |
| `failed` | `generation_failed` | 공급자 오류 또는 인용 검증 실패 |

모델은 학교 chunk ID와 개인 인용을 함께 반환한다. 검색하지 않은 chunk, 선택하지 않은 기록,
기록에 없는 문구, 예상하지 못한 필드가 있으면 전체 답변을 버린다. 생성 후에는 로그인, 기록
버전, 학교 문서 상태를 다시 확인한다. 도중에 근거가 회수되면 답변을 돌려주지 않는다.
구조 검증은 의미의 정확성을 보장하지 않으므로 실제 모델 응답은 사람이 평가해야 한다.

타입은 `scripts/export_academic_guidance_contracts.py`로 재생성한다.

## 명시적으로 선택한 등록 자료 (PR #70)

요청의 선택 필드 `documents`에 `{filename, content_base64}`를 보낼 수 있다. 최대 5개·원본 합계 8MiB이며 기록과 문서 조각은 합계 20개 이하다. 등록 자료의 설명은 UTF-8 TXT로, 첨부 PDF는 원본 바이트로 전달한다. 한 자료의 설명과 PDF는 각각 한 파일로 센다. #69의 추출기를 재사용해 텍스트 PDF·TXT 및 사진·스캔 PDF OCR을 처리한다. OCR은 한국어·영어 엔진, 최대 20장, PDF 100쪽 제한을 따른다.

문서는 저장 기록 없이 단독 선택할 수 있다. `external_processing_consent=true`가 없으면 OCR/문서 추출과 외부 모델 호출을 하지 않는다. 프런트는 문서가 있는 요청마다 동의를 다시 받으며, 동의 화면은 설명·PDF 추출 텍스트의 Google 전송을 명시한다. 원본을 보관하거나 학교 공용 검색에 등록하지 않는다.

응답의 `personal.records`에 요청 내에서만 유효한 문서 조각 ID와 파일명·쪽수/본문·OCR 원본 대조 안내를 title로 제공한다. 개인정보 가림 후 텍스트만 모델에 전달하고 기존 인용 검증을 적용한다. `personal_citations`의 ID를 해당 title과 연결해 출처를 표시한다. 학교 근거 `school`은 승인된 학교 자료에서만 가져오며 개인 문서는 학교 규정이나 공식 판정이 되지 않는다. OCR 미설치는 503, 읽기 불가/용량 초과는 422이며 원문을 오류 로그에 기록하지 않는다. API 런타임 Docker 이미지에 OCR 엔진과 ingestion 의존성을 포함했다.
