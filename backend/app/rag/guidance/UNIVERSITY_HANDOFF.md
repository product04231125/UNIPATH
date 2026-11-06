# 대학규정·장학금 안내 추가 (2026-11-05)

AI/RAG 모듈만 수정했다. 기존 백엔드/API·프론트·DB는 변경하지 않았다.
자료는 외부 페이지 바로가기 대신 선택 결과의 `cards[].body`와 표로 제공한다.
새 API 및 이미지/파일 제공 경로는 배포하지 않았으며 각 담당자의 통합이 필요하다.

## 수집 범위와 확인 결과

- 대학규정: `https://www.kduniv.ac.kr/kor/CMS/RegulationBookMgr/list.do?mCode=MN191`
- 위 페이지가 실제 사용하는 `ajaxRegulationList.do`의 전체 목록도 수집.
- 규정 189개, 연결된 PDF 첨부 171개, 총 1,197쪽.
- 18개는 사이트에 폐지·이동 표시와 함께 첨부가 없다. 항목 자체를 지우지 않았다.
- 분류 트리에는 188개, 전체 목록에는 189개가 있다. 분류에 없는
  '경동대학교 연구실안전관리센터 규정'도 전체 목록에 포함하고 분류 정보 미표시를 안내한다.
- PDF의 텍스트가 없거나 워터마크만 추출되는 등 본문을 읽기 어려운 53쪽은 로컬 macOS Vision OCR 적용.
  OCR은 오탈자가 있으며 검수 완료가 아니다. 이미지 우선 표시와 원본 대조가 필요하다.
- 장학금 안내(MN149), 장학금 종류(MN150), 학자금 융자(MN151)의 본문 전체·섹션·표·관련 링크 포함.
  이 세 본문 영역에는 별도 다운로드 첨부가 없었다. 사이트 공통 하단의 인증서는 본문 첨부가 아니다.
- 장학금 종류의 표 2개는 병합 셀 원본 구조와 펼친 행렬을 모두 보존한다.
- 외부 한국장학재단 사이트 전체나 학교 전체 공지 게시판으로 범위를 확장하지 않았다.

`data/university.json`과 `data/sources/university/`에 본문·표·원본 HTML/PDF·OCR 페이지 이미지가 있다.
[UNIVERSITY_INVENTORY.md](UNIVERSITY_INVENTORY.md)에 189개 항목별 수집 상태를 정리했다.
원본 파일은 SHA256으로 식별하고 파일명이나 URL을 사용자 입력으로 받아 임의 파일을 열지 않는다.
기존 사용자가 첨부한 학사규정 6개 메뉴는 유지한다. 대학규정 메뉴의 온라인 수집본과
파일 해시가 같을 수도, 개정으로 다를 수도 있으므로 출처와 수집 시점을 구분한다.

## 클릭 흐름

- `home → university → 분류 → 규정 → 첨부 → 페이지`
- `home → scholarship → scholarship:MN149` (신청·지급·자격 제한 등의 안내)
- `home → scholarship → scholarship:MN150` (교내·교외 장학금, 표·항목별 안내)
- `home → scholarship → scholarship:MN151` (정부학자금대출·농어촌출신학자금융자)
- `scholarship:MN149`의 장학 규정 버튼 → `university:CDE_000275`

메뉴는 자동 생성된 `catalog.json`을 사용한다. 여러 규정이 있는 분류는 12개씩 묶는다.
규정명으로 인덱스를 추측하지 않고 `node_id`를 전송한다. 규정의 첨부 페이지 ID는
`university:{규정ID}:attachment:1:page:1` 형식이며 규정의 ID는 사이트 분류 코드가 기본이다.
분류가 없는 항목은 제목 해시를 사용한다.

## 프론트 전달 형식 (academic-click-v3)

기존 감사 결과의 필드는 유지한다. 참고 안내 카드에는 다음 type이 추가된다.

| type | 화면에 표시할 내용 |
| --- | --- |
| regulation_metadata | 규정명, 분류 경로, 게시 개정일, 폐지·이동 여부 |
| regulation_page | 해당 페이지의 body, tables, 페이지 출처 |
| reference_text | 장학금·융자 본문 또는 선택한 표 행의 제목/내용 |
| reference_table | 표 전체 body, table.rows 및 table.grid |

`table.rows`는 `{text,rowspan,colspan,header}` 셀 구조이고 `table.grid`는 병합을 펼친 배열이다.
셀을 펼치는 것은 적용 범위를 추론하는 작업이 아니며, 원래 병합 영역에 같은 문구를 반복한다.
빈 칸을 0이나 '조건 없음'으로 바꾸지 않는다. 표 행은 조건·금액·비고를 함께 보여준다.

OCR 페이지는 `extraction_status=ocr_unreviewed`, `preferred_view=image`, `image_asset_id`를 반환한다.
프론트는 이미지와 OCR 경고를 먼저 표시하고 텍스트는 보조로 보여준다. OCR 출력으로
자격 판정·금액 계산·숫자 단정을 하지 않는다. 추출되지 않는 새 문서는 `needs_visual_review`로 남는다.
`assets.resolve_asset(asset_id)`는 수집 목록에 등록된 PDF/이미지만 SHA 검증 후 내부 Path로 돌려준다.
백엔드 담당자가 파일 제공 경로를 연결해야 한다. 반환 Path를 JSON에 노출하지 않는다.
`source.asset_id`는 PDF, `image_asset_id`는 페이지 JPEG이며 외부 URL 열기를 대신한다.

`fetched_at`은 수집 시각이지 규정 시행일이나 페이지 갱신일이 아니다.
일주일 지난 자료에는 `snapshot_stale`/warnings가 표시된다. 수집한 내용이 현재 개인에게
적용되는지는 별도 검토 대상이다. 장학금 수혜나 대출 가능 여부를 자동 판정하지 않는다.
장학금 페이지 본문에 오래된 제도 표현이 있을 수 있어 '학교 게시 자료 기준' 표시를 유지한다.

## 갱신 방법

`backend/`에서:

```bash
app/rag/.venv/bin/python -m pip install -r app/rag/guidance/requirements-collection.txt
app/rag/.venv/bin/python -m app.rag.guidance.university
# 수집이 중단됐을 때 같은 작업의 재시도에만 사용:
app/rag/.venv/bin/python -m app.rag.guidance.university --resume
# macOS Swift/Vision 사용. 모델 API에 자료를 보내지 않는다.
app/rag/.venv/bin/python -m app.rag.guidance.ocr
app/rag/.venv/bin/python -m app.rag.guidance scholarship:MN150
```

`--resume`은 다운로드/추출 임시 캐시를 재사용한다. 최신판 전체 재수집에는 기본 명령을 사용한다.
수집 실패·목록 누락·개수 불일치·새 첨부 형식에는 기존 university.json을 교체하지 않는다.
원본·임시 파일 일부가 남을 수 있지만 게시 JSON은 완성된 수집 결과만 원자적으로 교체한다.
OCR 단계도 성공 후 JSON을 교체한다. 재수집 후 OCR을 다시 실행해야 한다.
임시 캐시는 Git에서 제외한다. 자동 주기 갱신은 아직 설정하지 않았다.

## 검증과 한계

분류/목록/첨부 수 대조, 원본 해시, 모든 페이지의 메뉴 연결, 병합 셀 처리, 폐지 항목 보존,
7일 경과 경고, 장학 규정 연결, 파일 경로 입력 거부를 자동 검증했다.
스캔 문서와 장학 규정 일부 페이지를 시각 확인했으나 1,197쪽 전체를 사람이 교정한 것은 아니다.
원본을 수정하지 않았으며 OCR 문구를 원문과 동일하다고 보증하지 않는다.
자료 읽기는 가능하지만 실제 앱의 이미지 표시·표 레이아웃·서버 파일 경로 연결은 후속이다.
