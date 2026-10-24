# develop 통합 및 구현 범위 확인 (2026-10-24)

## 브랜치와 범위

- 원래 feature/frontend-carryover 81be081(기능 기준 31f131d와 기존 README 서식 커밋)에서 feature/frontend-integration-audit를 만들고, fetch한 origin/develop 535cd69를 병합했다. 원래 브랜치를 보존했다.
- 기존 9커밋은 develop에 이미 반영돼 있다. 새 구현을 추가하는 작업이 아니라 최신 기능 통합·회귀·구현 범위 확인이다. 제품 원격 푸시·PR·배포는 하지 않았다.
- 시작 시 작업 트리는 깨끗했다. 개인 지침·첨부·실제 비밀값은 커밋 대상에 넣지 않았다.

## 충돌 해결

- admin_workspace.dart: 서버 beforeSignedOut를 유지하고 입력 폐기 확인 전후 busy 및 mounted를 검사한다. 비동기 확인 뒤 폐기된 화면을 갱신하지 않는다.
- remote_admin_test.dart: 본문 학교 등록 폼 탐색, 관리자 변경 요청의 X-Unipath-Owner 검사, 미저장 입력에서 로그아웃 취소 시 서버 미호출·입력 보존, 정상 서버 로그아웃을 모두 유지했다.

## 코드에서 확인한 구현 상태

| 영역 | 확인 상태 | 주요 근거 |
| --- | --- | --- |
| 가입·로그인·세션·역할/학교 범위 | 실제 AuthApi·관리자 repository 연결 | app_navigation.dart, auth_api.dart, remote_admin_repository.dart |
| 계정 보안 | 비밀번호 변경·전체 세션 종료 화면 연결 | account_security_dialog.dart, app_navigation.dart |
| 프로필·일정 | 서버 CRUD·명시적 동의 이전 화면 연결 | remote_planning_repository.dart, planning_import_section.dart, workspace.dart |
| 개인 수강·봉사·경험·자격·성과·학업 기준 | 서버 repository 선택·동의 이전 연결 | personal_repository_scope.dart, remote_personal_record_repository.dart, personal_workspace_import_section.dart |
| 구성·지원 문서 | 서버 CRUD·관계/순서·이전 연결 | remote_portfolio_workspace_repository.dart |
| 개인 기준 계산 | 명시 조건·계산·불변 이력 화면 연결 | personal_calculation_page.dart, personal_calculation_controller.dart, personal_graduation_workspace.dart |
| 자료 PDF | IndexedDB/Windows 기기 보관·내보내기 | material_repository.dart, materials_page.dart. 서버 기록 JSON 저장과 별개 |
| 관리자 학교·학과·교육과정·과목·요건·문서 메타데이터 | 서버 CRUD·본문 등록 연결 | admin_workspace.dart, admin_editor.dart |
| 학교관리자 신청·승인 | 백엔드 API와 Dart 타입/전송 adapter, 신청·접수 화면 미연결 | docs/api/school-admin-applications.md, admin_application_api.dart |
| 학교 문서 RAG 승인·검색 | 백엔드 API와 Dart 전송 adapter, 관리자 검토·학생 UUID 검색 화면 미연결 | docs/api/school-knowledge.md, school_knowledge_api.dart |
| 공식 실행 규칙·자격증 마스터 | 서버 계약 준비, 새 관리 화면 후속 | docs/api/rule-programs.md, certificates.md |
| 학교 발급 PDF·학생 기록 검토·공식 졸업감사 | API/생성 DTO/전송 adapter 준비, 제출·검토·감사 화면 미연결 | docs/api/official-record-sources.md, official-student-records.md, graduation-audits.md |
| 채팅 | 기존 assistant/queries의 상태·오류·근거 UI. 승인 DB 기반 새 API 화면과 별개 | assistant_panel.dart, assistant_api.dart |
| LLM·학습된 임베딩 | adapter 존재, 실제 모델 미선정/미연결 | backend/app/rag/README.md. 질문 방식/운영 결정 미확정 |
| 채용 분석·개인화 | 2차 설계, 분석 API/최종 UI 미구현 | backend/app/services/job_analysis/__init__.py, docs/job-matching-decision-layer-proposal.md |
| 수강 연도·활동/경험 명칭·일반 임시저장 | 미완료 요구 유지 | personal_record_fields.dart는 term만 제공, workspace.dart는 활동/경험 이름 유지 |

화면 연결 확인은 코드 참조와 합성 테스트에 근거한다. 실제 서비스 저장·권한·전체 학교 자료 등록·운영 시연 성공을 뜻하지 않는다. 관리자 문서 적용, RAG 승인, 원본 신원 검토, 학생 기록 승인, 전체 규정 검토와 졸업감사는 별개 단계다.

## 검증

- flutter pub get 1회 성공, 충돌 파일 dart format 1회(수정 없음).
- flutter analyze --no-pub 1회: 문제 없음.
- flutter test --no-pub --reporter compact 1회: 434건 통과, 11건 생략, 실패 없음.
- 생략 11건은 별도 환경이 필요한 server_*_http_test.dart의 실제 Flutter HTTP→격리 API/DB 테스트다. API URL/합성 fixture가 미설정인 상태에서 실행하지 않는다. 새로 서버·DB를 생성하거나 실제 계정을 사용하지 않았다.
- flutter build web --no-pub 및 flutter build windows --no-pub 각각 1회 성공.
- git diff --check 및 충돌 마커/미해결 항목 확인.
- 이번에는 백엔드 전체 테스트, 실제 운영 서버 요청, 브라우저/Windows 실기 UI·PDF 대화상자·다중 모니터 검증을 수행하지 않았다. 테스트 통과를 실제 학교 데이터의 정확성이나 LLM 답변 품질로 확대하지 않는다.

## 남은 작업

1. 학교관리자 신청·접수, 학교 문서 검토/검색, 공식 원본/기록 검토·감사 화면 중 우선 흐름을 선택해 기존 OpenAPI와 연결한다.
2. 학사 안내의 템플릿/LLM 선택과 개발용과 분리한 평가·정답·근거 검토를 합의한다. 2차 채용 분석의 모델 선택과 구별한다.
3. 격리 API/DB HTTP 검증과 실제 학교 자료·승인·역할별 시연을 별도로 수행한다.
4. 수강 연도·메뉴 명칭·임시저장 및 기존 가독성/접근성 잔여 요구는 개인 work.md에서 유지한다.
