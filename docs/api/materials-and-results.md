# 내 자료와 저장된 분석 결과 API (2026-11-24)

두 기능 모두 계정 주인만 읽고 쓰며, 여기서는 외부 모델을 부르지 않는다. 계정을 지우면 함께 지워진다(`ON DELETE CASCADE`).

## 내 자료 `/api/v1/me/materials`

학생이 등록한 설명·PDF다(마이그레이션 `0031_materials_results`, 표 `student_materials`). 예전에는 기기(브라우저 저장소)에만 두었다.

| 요청 | 설명 |
| --- | --- |
| `GET /me/materials` | 최근 수정 순 목록과 `total_bytes`·`max_total_bytes`(50MiB)·`max_file_bytes`(8MiB). 파일 내용은 없다. |
| `POST /me/materials` | `id`(클라이언트가 정한 UUID), `title`(1~120자), `material_type`(`portfolio`·`resume`·`cover_letter`·`other`), `description`(최대 4,000자), 선택 `file {filename, content_base64}`. 같은 `id`를 다시 보내면 바꾸지 않고 200으로 그대로 돌려준다(기기 자료 옮기기 재시도). 다른 계정의 `id`면 409. |
| `PUT /me/materials/{id}` | 위 필드와 `expected_version`. `file`을 빼면 저장된 PDF를 유지하고, `null`이면 지우고, 값이 있으면 바꾼다. |
| `DELETE /me/materials/{id}?expected_version=N` | 삭제 |
| `GET /me/materials/{id}/file` | 저장된 PDF(`application/pdf`, `Cache-Control: no-store`) |
| `GET /me/materials/{id}/pages` | 앱 안 PDF 보기용. `{page_count, pages: [{width, height}]}`(쪽 크기는 pt, 쪽 회전 반영, 앞 300쪽). 암호가 걸렸거나 손상된 PDF는 422, PDF가 없으면 404. |
| `GET /me/materials/{id}/pages/{n}` | `n`쪽(1부터)의 이미지(`image/webp`, 폭 1,400px, 한 장 600만 화소·한 변 8,000px 이하, `no-store`). 없는 쪽은 404. |

- 설명이나 PDF 중 하나는 있어야 한다. PDF는 `.pdf` 이름과 `%PDF-` 시작을 확인한다.
- 쪽 이미지(2026-11-25)는 서버가 PDFium(`pypdfium2`, pdfplumber와 함께 설치됨)으로 그린다. 글자를 뽑거나 저장하지 않는다.
  - 같은 파일(SHA-256)의 쪽 크기와 최근 이미지 48장은 프로세스 메모리에 잠시 둔다.
  - PDFium은 스레드에 안전하지 않아 OCR과 같은 잠금(`app/rag/pdf_pages.py`의 `PDFIUM_LOCK`)을 쓴다.
  - 두 경로는 학생마다 15분에 600회까지다(`material-pages:` 버킷).
- 한도는 PDF 1개 8MiB(분석 요청 하나로 보낼 수 있는 양), 계정 전체 50MiB, 100개다. 넘으면 422 또는 409.
- 게이트웨이·웹 nginx는 이 경로에 12MB 요청 본문을 허용한다.
- 분석에 쓸 때는 앱이 고른 자료의 설명·PDF를 읽어 기존처럼 요청의 `documents`로 보낸다. 서버가 자료를 분석 요청에 몰래 붙이지 않는다.
- 앱은 로그인한 계정의 기기 자료를 처음 목록을 읽을 때 같은 `id`로 계정에 옮기고, 옮긴 것은 기기에서 지운다. 옮기지 못한 자료(8MB 초과, 한도 초과)는 기기에 남기고 자료 화면에 개수를 알린다.

## 저장된 분석 결과 `/api/v1/me/analysis-results`

공고 1개 비교(`posting`), 목표 직무 분석(`gap`), 내 자료로 공고 찾기(`search`), 활동 추천(`activity`), 자격증 추천(`certificate`)의 끝난 결과다(표 `analysis_results`). 앱이 분석·추천을 마치면 자동으로 저장한다. 활동·자격증 추천은 2026-11-27(마이그레이션 0034)에 더했다.

| 요청 | 설명 |
| --- | --- |
| `GET /me/analysis-results?kind=posting` | 즐겨찾기 먼저, 그다음 최신 순. 제목·요약(`summary`)·즐겨찾기·시각만 있다. |
| `POST /me/analysis-results` | `kind`, `title`(1~160자), `summary`(작은 값 최대 12개, 예: `{"ready": 6, "total": 7}`), `input`(공고 본문·검색 조건·근거 기록 이름, 최대 30,000자), `result`(분석 응답 JSON, 최대 200,000자) |
| `GET /me/analysis-results/{id}` | 위 내용 전체 |
| `PATCH /me/analysis-results/{id}` | `{"favorite": true}` 즐겨찾기(최대 50개) 또는 해제 |
| `DELETE /me/analysis-results/{id}` | 삭제 |

- 종류마다 즐겨찾기하지 않은 결과는 최근 30개만 남기고, 새로 저장할 때 오래된 것부터 지운다. 즐겨찾기한 결과는 지우지 않는다.
- 저장된 결과는 학생이 다시 읽기 위한 기록이다. 동의 여부와 첨부 파일 내용은 저장하지 않는다. 결과는 공식 판정이 아니다(`official=false`).
