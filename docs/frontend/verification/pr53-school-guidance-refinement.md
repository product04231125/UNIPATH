# PR #53 학교 질문 안내 정리

## 졸업 트리·기준 조회 재검증

- 기준: 로컬 HEAD와 최신 `origin/develop`의 `backend/app/rag/guidance/service.py`, `backend/app/api/rule_programs.py` 대조. 해당 두 API의 원격 변경 없음.
- 실제 `respond()` 실행 결과: `summary`, `credits`, `courses`, `volunteer`, `certificate`, `thesis`, `review` 모두 audit 없이 `needs_input/verified_audit_required`, 카드 0개. 현재 정형 트리의 일반 졸업 항목도 개인 감사용이라는 이전 설명은 현 코드에서 확인됐다. 자동 개인 연결이 아니라 검증된 audit ID가 있어야 개인 결과를 보여 준다.
- 별도 `GET /api/v1/catalog/rule-programs`는 개인 audit 없이 승인된 조건·근거를 제공한다. 실제 로컬 OpenAPI에서 필수 입력 `institution_id`, `department_id`, `curriculum_id`, `admission_year`, `track`, 선택 입력 `on`을 확인했다. 일반 기준 조회로 사용할 수 있으나 기준 등록·검토가 필요하며, 전체 졸업요건 완전성을 증명하거나 개인 충족을 판단하지 않는다.
- 프런트는 일반 항목에 기존 기준 조회를 연결하고 `summary`만 개인 결과 선택을 제공한다. 트리 서버 응답의 이동 버튼은 유지하고, 일반 항목의 audit 선택 메시지/과거 개인 결과는 표시하지 않는다. 서버에 새 endpoint/필드를 추가하지 않았다.
- `guidance_criteria_test.dart` 4건 통과: 필요 학점130 표시/audit 미전송과 summary 분리, 기준 미등록, 불완전·변경 문맥, 분리 창 스냅샷 및 타 학교 응답 차단.

## 출처·문구·학교 질문 디자인

- 서버 버튼의 ID·이동 의미를 유지하며 제목/내용/선택 목록/이전·처음을 한 안내 카드 안에서 구분했다. 일반 기준과 summary의 개인 결과 UI는 분리했다.
- 동일 URL/asset/document/page만 공통 출처로 묶고 다른 문서/페이지는 유지한다. 달력의 body가 제목·날짜의 정확한 결합인 경우만 생략하며 추가 설명은 보존한다. 긴 수집 타임스탬프는 제거하고 자료 확인 설명은 접힌 상세로 옮겼다. OCR·표 null·원문 인증과 오류는 유지한다.
- `guidance_presentation_test.dart`의 출처 관계 보존·공통 링크1개·제목/날짜/시각 중복 제거 2건 통과. Material/잉크 배경 경고가 난 관련 UI4건은 Material 외곽으로 수정 후 해당4건 재실행 통과했다.
- 렌더: 1440×1000, DPR1, Pretendard/MaterialIcons, 합성 한국어 메뉴·일정·학점 기준. 3테마의 기본 크기와 크림 테마의 글자2배, 총4렌더를 확인했다. 불필요한 적용연도 반복과 fixture의 실제 이동 메뉴 구성을 보완 후 재캡처했다. 경계 겹침/잘림 없음. `output/pr53-school-guidance-refinement/visuals/`에 보관한다.
- 캡처 테스트 최초 실행은 디렉터리 생성 IO가 위젯 테스트 비동기 영역에서 대기해 종료했다. 실제 비동기 영역으로 이동한 뒤 캡처 사례만 재실행 통과했다. 기능 회귀 실패와 구분한다.

## 자료 정제 요청 근거

- 실제 `respond(calendar:2026:01)` 7건/11월5건은 각기 하나의 원문 URL을 반복한다. 첫 카드의 title/date_text/body 중복을 확인했다. 이는 `content.py`의 결합 문자열이며 PDF 추출 문제로 단정할 수 없다.
- [수집 자료 정제·응답 역할 정리 요청](../specs/school-guidance-content-cleanup.md)에 사례·담당 범위·원문 보존·오류/불확실 상태·수용 조건을 정리했다. 서버 코드는 변경하지 않았다.

## 사용자 템플릿 상세화·최종 확인 (2026-11-08)

- 첫 메뉴를 분야 → 받은 세부 항목으로, 졸업을 일반 기준/개인 요약 선택으로 세분화했다. 새 노드·서버 계약은 추가하지 않았다. 학사일정의 기존 연도 → 월 → 일정 경로를 유지한다. 일정·문서는 추가 내용만 선택해 펼치며 제목/날짜뿐인 행은 빈 펼침이 없다.
- 프로필 저장 후 안내가 비던 문제를 실제 로컬 화면에서 발견했다. 노드 ID를 보존하고 문맥 갱신 뒤 재조회하도록 수정했다. 합성 위젯 테스트와 실제 로컬의 서버 자료 재조회 뒤 이수학점 화면 유지를 확인했다. 현재 로컬 학업 문맥에는 승인 기준이 없어 관리자 등록·검토 필요 상태를 표시하며 값을 만들어 넣지 않는다.
- 관련 학사 안내/기준/IPC 테스트 18건 통과(기존 IPC3건 + 수정 후 학사/기준15건), 표현·캡처4건 통과. 이전 선정 데스크톱 회귀274통과/12생략은 프로필 갱신 수정 전 근거이며, 이후 관련 회귀로 보완했다. 좁은 화면·배포 서버·외부 AI 호출은 검증 대상에서 제외했다.
- 반복 실행 사유: 새 메뉴 단계와 본문 접힘에 맞춰 기존 기대를 갱신했고, 프로필 재조회 테스트의 비동기 callback 내부 expect가 Flutter guarded API와 충돌해 expectSync로 수정했다. 실패한 두 테스트 파일만 재실행해15건 통과했다. 렌더 중 빈 펼침을 발견해 추가 내용 없는 일정은 펼침을 제거한 후 표현 테스트와 영향 검증을 반복했다.
- 로컬 1280×720에서 첫 분야 → 수업·학사 → 졸업 → 일반 기준 → 이수학점과 학사일정 → 2026 → 1월을 확인했다. 캡처는 output/pr53-school-guidance-refinement/visuals/local-tree-template.png, local-tree-criteria.png, local-profile-refresh-after-fix.png 참조. 테마3종/글자2배의 합성 렌더4장도 보관한다. Windows는 빌드 근거이며 OS 분리 창 실기는 이번 완료 범위에 포함하지 않는다.

- 최종 명령: `flutter test --no-pub test/guidance_criteria_test.dart test/academic_guidance_test.dart` 15통과, 기존 IPC3통과 재사용; `flutter test --no-pub test/guidance_presentation_test.dart --dart-define=GUIDANCE_CAPTURE=true` 4통과(3기능+1렌더). `flutter analyze --no-pub` 문제 없음. Web·Windows Release 빌드 통과. 로컬 실기에서 빈 펼침/본문 대비를 보완했기 때문에 표현·분석·빌드를 추가 실행했으며 최종 소스를 검증했다.
