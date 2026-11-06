# 학과안내: 컴퓨터공학과 우선 제공 (2026-11-05)

기존 학부·학과 준비 중 메뉴를 캠퍼스별 선택 메뉴로 확장했다.
AI/RAG 모듈만 변경했으며 실제 프론트 화면과 API는 수정하지 않았다.

- 메트로폴캠퍼스: 사용자가 제공한 20개 학과.
- 메디컬캠퍼스: 사용자가 제공한 8개 학과.
- 글로벌캠퍼스: 사용자가 제공한 국제학부 1개.
- 컴퓨터공학과 1개만 공식 소개 페이지를 수집하고 본문 제공.
- 나머지 28개는 `content_pending`, 선택 시 `department_content_pending`/`unavailable`.
  이름에 '추후 추가 예정'을 표시한다. 해당 학과 소개나 연락처를 추측하지 않는다.

## 선택 흐름

`departments → departments:metropol → 첫 학과 묶음 → departments:DE0013`

컴퓨터공학과는 첫 묶음의 첫 버튼으로 표시한다. 선택하면 소개 본문과 아래 6개 버튼이 나온다.

| ID 접미사 | 안내 |
| --- | --- |
| intro | 학과 소개 |
| contact | 사무실·위치·홈페이지 주소 |
| features | 학과 특성 |
| goals | 교육목표 |
| careers | 졸업 후 진로 |
| certificates | 취득자격증 |

예: `respond('departments:DE0013:contact')`.
기존 `reference_text` 카드의 body로 내용을 바로 읽는다. 홈페이지 URL은 본문 안에 안내하되
이동하지 않아도 소개·연락처를 확인할 수 있다. UI는 텍스트를 HTML로 실행하지 않는다.
학교 페이지가 나열한 기업·자격증을 현재 취업 보장이나 현행 자격 운영으로 단정하지 않는다.
`fetched_at`, sources와 warnings 표시 규칙은 기존 콘텐츠 안내와 동일하다.

## 자료와 범위

- `data/departments.json`: 사용자 제공 캠퍼스 목록과 컴퓨터공학과 실제 수집 데이터.
- `examples/department-responses.json`: 캠퍼스·컴퓨터공학과·연락처·준비 중 응답 예시.
- `examples/catalog.json`: 기존 메뉴에 학과안내를 추가한 전체 목록.

수집한 URL: https://www.kduniv.ac.kr/kor/CMS/DeptIntro/view.do?mCode=MN299&code=DE0013

다른 학과의 개별 페이지는 요청하지 않는다. 사용자 제공 링크는 `reference_url`로만 보관한다.
컴퓨터공학과 별도 홈페이지 전체, 갤러리·홍보 게시물·사진, 입학처 바로가기는 이번 수집 범위가 아니다.
공식 소개 페이지의 학과 본문·연락처·교육목표·진로·자격증·특성을 제공한다.
학과명 확인이나 필수 본문 추출에 실패하면 기존 데이터는 덮어쓰지 않는다.

`backend/`에서 갱신:

```bash
app/rag/.venv/bin/python -m app.rag.guidance.departments
app/rag/.venv/bin/python -m app.rag.guidance departments:DE0013:contact
```

수집에 필요한 패키지는 `requirements-collection.txt`를 따른다. 메뉴 조회에는 네트워크·LLM이 필요 없다.
현재는 `academic-click-v3`의 추가 메뉴이며 응답 필드 변경은 없다.
추후 다른 학과를 활성화할 때는 해당 학과 전용 파서·출처 검증을 추가한 뒤 availability를 바꾼다.
