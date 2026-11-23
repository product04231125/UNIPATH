# 자기소개서·포트폴리오 작성 API

학생의 저장 기록과 고른 내 자료로 편집 가능한 자기소개서·포트폴리오 초안을 만든다. 학생이 고친 초안은
Word 파일로 받는다. 서버는 초안도 파일도 저장하지 않는다. 앱은 마지막 초안과 편집 내용만 기기에 보관한다.
생성 모듈은 팀원 PR #98(`backend/app/rag/writing`)을 바탕으로 앱에 연결했다.

## 초안 만들기: `POST /api/v1/me/writing-drafts`

```json
{
  "document_type": "cover_letter",
  "mode": "create",
  "target_role": "프론트엔드 개발",
  "target_company": "합성 회사",
  "posting_text": "담당업무: React 화면 개발 …",
  "questions": ["지원 직무와 관련된 경험을 적어 주세요."],
  "char_limit": 1000,
  "original_text": "",
  "records": [{"kind": "experience", "record_id": "UUID", "expected_version": 1}],
  "documents": [{"filename": "portfolio.pdf", "content_base64": "…"}],
  "external_processing_consent": true
}
```

- `document_type`: `cover_letter` 또는 `portfolio`.
- `mode`: 새로 쓰려면 `create`, 붙여 넣은 원문(`original_text`, 최대 20,000자)을 다듬으려면 `improve`.
- `posting_text`(선택, 최대 20,000자): 공고의 업무·자격에 맞는 경험을 골라 쓴다. 회사에 대해서는 공고에 적힌
  사실만 쓴다. 공고는 학생 경험의 근거로 인용하지 않는다.
- `questions`(자기소개서, 최대 6개·각 300자): 문항이 그대로 섹션 제목이 된다. `char_limit`(200~5,000)은
  문항별 글자 수(공백 포함)다.
- `records`: 저장 기록 전체(최대 200개, D6). `documents`: 내 자료에서 고른 파일(최대 5개, 합계 8MiB).
  추출·OCR 방식은 채용공고 분석과 같다.
- 동의 없음 → `needs_user_input`(`external_processing_consent`). 기록·자료·원문이 모두 없음 → `records`.
  모델이 설정되지 않으면 `not_configured`.
- 사용자당 15분 20회, 모델 호출은 전체 호출 상한(`llm:global`)을 함께 쓴다.

### 처리

1. 기록은 이름·연락처를 가린 뒤 보낸다. 기록 합계가 40,000자를 넘으면 목표 직무·지원처·공고·문항과 겹치는
   단어가 많은 기록부터 담고, 몇 개를 썼는지 `warnings`에 알린다. 다듬을 원문은 항상 전부 보낸다.
2. 모델 호출 1회(제한 90초, 출력 16,384토큰). 문단과 표 항목(포트폴리오의 기간·역할·기술)마다 근거 기록의
   문장을 그대로 인용하게 한다. 기록에 없는 효과·성과(안정성, 성능, 효율 등)를 덧붙이지 않게 한다.
   빠진 사실은 지어내지 않고 `questions_for_user`로 묻는다.
3. 서버 검증:
   - 인용이 기록에서 확인되지 않으면 그 인용만 뺀다(띄어쓰기 차이 허용). 확인된 인용이 없는 문단·항목은 초안에서
     빼고, 몇 개를 뺐는지 `warnings`에 알린다. 남는 문단이 없으면 `failed`(`personal_citation`).
   - `improve`의 수정 이유는 원문에서 찾은 인용만 남긴다. 남은 섹션 번호에 맞춰 다시 매긴다.
4. 생성 후 계정과 기록 버전이 바뀌었으면 409.

### 응답 (`status=draft_ready`)

```json
{
  "status": "draft_ready",
  "official": false,
  "review_required": true,
  "document_type": "cover_letter",
  "mode": "create",
  "draft": {
    "sections": [{
      "heading": "지원 직무와 관련된 경험을 적어 주세요.",
      "paragraphs": [{"text": "…", "citations": [{"kind": "experience", "record_id": "UUID",
                                                  "version": 1, "excerpt": "기록 원문 일부"}]}],
      "facts": []
    }],
    "questions_for_user": ["지원 동기를 알려 주세요."],
    "revisions": []
  },
  "original_record_ids": [],
  "document_sources": [],
  "warnings": [],
  "notice": "초안입니다. …",
  "model": "gemini-3.5-flash",
  "generated_at": "2026-11-23T03:00:00+00:00"
}
```

- `original_record_ids`: 붙여 넣은 원문을 인용한 근거의 `record_id`.
- `document_sources`: 내 자료에서 나온 근거의 파일·위치(채용공고 분석과 같음).
- 실패하면 `status=failed`와 `failure_reason`(`personal_citation`, `model_timeout`, `output_shape` 등)만 준다.

## Word로 받기: `POST /api/v1/me/writing-exports`

```json
{
  "document_type": "portfolio",
  "draft": {"sections": [{"heading": "…", "paragraphs": [{"text": "…"}],
                          "facts": [{"label": "역할", "text": "…"}]}]},
  "profile": {"name": "이름", "email": "", "phone": "", "link": ""},
  "reviewed": true
}
```

- 학생이 고친 본문만 받는다. `citations`가 함께 와도 무시하고, 학생이 고친 문장은 다시 검증하지 않는다.
- `reviewed=true`가 아니면 422. 섹션은 최대 12개, 본문 합계는 24,000자 이하.
- 이름·연락처는 문서 첫 줄에만 넣고 모델에 보내지 않는다.
- 응답은 `application/vnd.openxmlformats-officedocument.wordprocessingml.document`이다.
  파일명은 `cover-letter.docx` 또는 `portfolio.docx`로 고정하고 `Cache-Control: no-store`를 붙인다.
- A4, 맑은 고딕(Malgun Gothic), 실제 Word 문단과 표로 만든다. 보호·매크로·추적 정보는 없다.
- 사용자당 15분 60회. 모델을 호출하지 않는다.

## 게이트웨이

`writing-drafts`는 채용공고 분석처럼 본문 12MB·180초를 허용한다(`deploy/gateway`, `deploy/preview`,
`deploy/windows-demo`). `writing-exports`는 일반 `/api/v1/me/` 경로(256KB)를 쓴다.
