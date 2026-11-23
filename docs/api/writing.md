# 자기소개서·포트폴리오 작성 API

학생의 저장 기록과 고른 내 자료로 편집 가능한 자기소개서·포트폴리오 초안을 만든다. 학생이 고친 초안은
계정에 저장해 다시 열 수 있고, Word·PDF 파일로 받는다. 생성과 내보내기는 아무것도 저장하지 않는다. 학생이
`저장`을 눌렀을 때만 문서가 저장된다(`/me/writing-documents`). 앱은 편집 중인 초안을 기기에도 따로 보관한다.
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

## Word·PDF로 받기: `POST /api/v1/me/writing-exports`

```json
{
  "document_type": "portfolio",
  "format": "docx",
  "draft": {"sections": [{"heading": "…", "paragraphs": [{"text": "…"}],
                          "facts": [{"label": "역할", "text": "…"}]}]},
  "profile": {"name": "이름", "email": "", "phone": "", "link": ""},
  "reviewed": true
}
```

- 학생이 고친 본문만 받는다. `citations`가 함께 와도 무시하고, 학생이 고친 문장은 다시 검증하지 않는다.
- `reviewed=true`가 아니면 422. 섹션은 최대 12개, 본문 합계는 24,000자 이하.
- 이름·연락처는 문서 첫 줄에만 넣고 모델에 보내지 않는다.
- `format`이 `docx`(기본)면 Word, `pdf`면 PDF를 돌려준다.
  - 파일명은 `cover-letter.<형식>` 또는 `portfolio.<형식>`으로 고정한다.
  - 모든 응답에 `Cache-Control: no-store`를 붙인다.
- Word: A4, 맑은 고딕(Malgun Gothic), 실제 Word 문단과 표로 만든다. 보호·매크로·추적 정보는 없다.
- PDF: A4, 나눔고딕을 문서에 넣어 만든다(ReportLab).
  - 백엔드 이미지에 `fonts-nanum`(SIL OFL)을 설치한다. Pretendard는 CFF 형식이라 ReportLab에 넣을 수 없다.
  - 글꼴이 없는 서버에서는 503을 돌려준다.
  - 표 항목은 Word와 같은 2열 표로 만든다. 학생이 쓴 글은 그대로 옮기고 마크업으로 해석하지 않는다.
- 사용자당 15분 60회. 모델을 호출하지 않는다.

## 저장한 문서: `/api/v1/me/writing-documents`

| 요청 | 동작 |
| --- | --- |
| `GET /me/writing-documents` | 목록(최근 저장 순). `id`, `title`, `document_type`, `version`, `updated_at`만 준다. |
| `POST /me/writing-documents` | 새로 저장(201). 계정당 50개까지, 넘으면 409. |
| `GET /me/writing-documents/{id}` | 문서 전체. |
| `PUT /me/writing-documents/{id}` | 덮어쓰기. `expected_version`이 다르면 409(다른 곳에서 바뀜). |
| `DELETE /me/writing-documents/{id}?expected_version=N` | 삭제(204). 버전이 다르면 409. |

저장·수정 본문은 다음과 같다.

```json
{
  "title": "합성 회사 자기소개서",
  "input": {"document_type": "cover_letter", "mode": "create", "target_role": "…",
            "target_company": "…", "posting_text": "…", "questions": ["…"],
            "char_limit": 800, "original_text": ""},
  "draft": {"sections": [{"heading": "…", "paragraphs": [{"text": "…", "citations": [ … ]}],
                          "facts": []}],
            "questions_for_user": ["…"], "revisions": []},
  "labels": {"record_id": "경험 · 합성 웹 프로젝트"},
  "expected_version": 1
}
```

- `expected_version`은 수정할 때만 보낸다.
- `input`은 생성할 때 쓴 입력이고, 다시 열 때 입력란을 채운다. 전송 동의 여부는 저장하지 않는다.
- `draft`: 학생이 고친 섹션과 생성 때 확인된 인용을 저장한다.
  - 학생이 고친 문장의 인용은 다시 검증하지 않는다.
  - 학생이 새로 쓴 문단은 인용 없이 저장할 수 있다.
  - 빈 섹션은 받지 않는다.
- `labels`는 인용 출처의 표시 이름이다(최대 300개). 기록 본문은 저장하지 않는다.
- 다른 학생의 문서는 목록에 보이지 않고, 조회·수정·삭제하면 404를 돌려준다.
- 계정을 지우면 함께 지워진다(`ON DELETE CASCADE`).
- 테이블은 `writing_documents`이고 마이그레이션은 0030이다. 본문 JSON은 20만 자 이하만 받는다.
- 모델을 호출하지 않으며, 저장된 문서는 외부로 보내지 않는다.

## 게이트웨이

`writing-drafts`는 채용공고 분석처럼 본문 12MB·180초를 허용한다(`deploy/gateway`, `deploy/preview`,
`deploy/windows-demo`). `writing-exports`와 `writing-documents`는 일반 `/api/v1/me/` 경로(256KB)를 쓴다.
