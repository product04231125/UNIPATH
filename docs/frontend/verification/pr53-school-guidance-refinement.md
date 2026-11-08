# PR #53 학교 질문 안내 정리

## 졸업 트리·기준 조회 재검증

- 기준: 로컬 HEAD와 최신 `origin/develop`의 `backend/app/rag/guidance/service.py`, `backend/app/api/rule_programs.py` 대조. 해당 두 API의 원격 변경 없음.
- 실제 `respond()` 실행 결과: `summary`, `credits`, `courses`, `volunteer`, `certificate`, `thesis`, `review` 모두 audit 없이 `needs_input/verified_audit_required`, 카드 0개. 현재 정형 트리의 일반 졸업 항목도 개인 감사용이라는 이전 설명은 현 코드에서 확인됐다. 자동 개인 연결이 아니라 검증된 audit ID가 있어야 개인 결과를 보여 준다.
- 별도 `GET /api/v1/catalog/rule-programs`는 개인 audit 없이 승인된 조건·근거를 제공한다. 실제 로컬 OpenAPI에서 필수 입력 `institution_id`, `department_id`, `curriculum_id`, `admission_year`, `track`, 선택 입력 `on`을 확인했다. 일반 기준 조회로 사용할 수 있으나 기준 등록·검토가 필요하며, 전체 졸업요건 완전성을 증명하거나 개인 충족을 판단하지 않는다.
- 프런트는 일반 항목에 기존 기준 조회를 연결하고 `summary`만 개인 결과 선택을 제공한다. 트리 서버 응답의 이동 버튼은 유지하고, 일반 항목의 audit 선택 메시지/과거 개인 결과는 표시하지 않는다. 서버에 새 endpoint/필드를 추가하지 않았다.
- `guidance_criteria_test.dart` 4건 통과: 필요 학점130 표시/audit 미전송과 summary 분리, 기준 미등록, 불완전·변경 문맥, 분리 창 스냅샷 및 타 학교 응답 차단.

## 후속 정리 범위

- 동일 출처 공통 표시, 수집 시각·중복 문구 정리, 학교 질문 디자인과 렌더 검증을 이어서 수행한다.
- 정제 원인은 PDF/OCR로 단정하지 않고 실제 수집 데이터 사례와 백엔드·AI 요청을 별도 명세로 정리한다.
