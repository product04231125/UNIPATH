# 정형 학사 안내 API

버튼을 눌러 학사일정, 규정, 장학금, 학과 안내를 읽는 API다. LLM을 쓰지 않고 수집한 스냅샷의
본문을 그대로 돌려준다. 안내 자료는 참고 자료이며 졸업 판정을 계산하지 않는다.
로그인이 필요하고 응답은 `no-store`다. 원본은 `backend/app/rag/guidance/`다.

## 노드 조회

`GET /api/v1/me/academic-guidance/nodes/{node_id}?audit_id={uuid}`

첫 화면은 `home`이다. 응답의 `buttons[].node_id`로 다음 노드를 호출한다. ID를 만들어 내거나
label로 분기하지 않는다. `availability=content_pending`은 준비 중 배지로 표시한다.
`node_id`는 영문·숫자·`:`·`_`·`-` 200자 이내이며 형식이 다르면 422다.
형식은 맞지만 없는 노드는 200과 `reason=unknown_node`, 처음으로 가는 버튼을 준다.
사용자별 15분당 600회로 제한한다.

| state | 의미 |
|---|---|
| `ready` | 표시 가능. 충족이나 승인을 뜻하지 않는다 |
| `needs_selection` | 없는 노드 |
| `needs_input` | 감사 또는 입력 필요 (`verified_audit_required`, `career_inputs_required`) |
| `unavailable` | 준비 중 (`approved_content_not_configured`, `department_content_pending`) |

공통 필드는 `schema_version`, `node_id`, `title`, `state`, `reason`, `message`, `cards`, `warnings`,
`buttons`다. `warnings`는 본문보다 먼저 표시한다. `snapshot_stale=true`는 수집 후 7일이 지났다는
뜻이다. `fetched_at`은 수집 시각이며 규정 시행일이 아니다.

## 카드

`cards[].type`으로 분기한다.

| type | 표시할 내용 |
|---|---|
| `calendar_event` | `title`, `date_text`, `start_date`, `end_date` |
| `regulation_excerpt` | `title`, `body`(줄바꿈 보존), `sources` |
| `regulation_page` | `body`, `tables`, `sources`, OCR이면 `image_asset_id` |
| `regulation_metadata` | 규정명, 분류 경로, 게시 개정일 |
| `reference_text` | 장학금·학과 본문 |
| `reference_table` | `table.rows`(병합 구조), `table.grid`(펼친 배열) |
| `audit_requirement` | Rule Engine 결과. `status`, `quantities`, `missing_courses`, 근거 |

- `extraction_status=ocr_unreviewed`이면 `preferred_view=image`다. 이미지와 OCR 경고를 먼저
  보여 주고 텍스트는 보조로 쓴다. OCR 문구로 금액이나 자격을 단정하지 않는다.
- `tables`와 `table.grid`의 `null`은 병합·공란이다. 0이나 면제로 바꾸지 않는다.
- `quantities`의 `null`도 0이 아니다. 프론트에서 부족 수치를 다시 계산하지 않는다.
- 텍스트는 HTML로 실행하지 않는다.

## 졸업 항목

`summary`, `credits`, `courses`, `volunteer`, `certificate`, `thesis`, `review`는 감사가 있어야
결과를 보여 준다. 프론트는 `audit_id`만 보내고 서버가 소유권을 확인해 다시 읽는다. 다른 사용자의
감사는 404다. 감사가 없으면 `needs_input`이며 충족이나 미충족으로 표시하지 않는다.
`audit.current_usable=false`이면 과거 기준일 결과로 묶어서 표시한다.

## 원문 파일

`GET /api/v1/me/academic-guidance/assets/{asset_id}`

`sources[].asset_id`(PDF)와 `image_asset_id`(페이지 JPEG)로 내려받는다. ID는 SHA-256이고 수집
목록에 있는 파일만 해시를 다시 확인해 제공한다. 파일 경로나 URL은 입력받지 않는다.
없는 ID는 404, 형식 오류는 422다. 사용자별 15분당 120회로 제한한다.

## 취업 메뉴

`career:posting`의 `integration_state`는 분석기가 설정되면 `connected`, 아니면
`adapter_not_connected`다. `career:recommend`, `career:profile`은 공개 API가 없어 항상
`adapter_not_connected`다. 메뉴를 누르는 것만으로 자료를 보내거나 모델을 호출하지 않는다.

타입은 `scripts/export_academic_guidance_contracts.py`로 재생성한다.
