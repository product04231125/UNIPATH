# ERD·HTML 개인 수동 입력 완료 대조

## 기준과 완료 의미

기준 자료는 [논리 ERD](../database-erd.md), `frontend/mockup/app.js`의 입력 폼·이벤트 처리,
[개인 입력 경계](manual-input-boundaries.md)다. 기능 선언뿐 아니라 저장소·입력 필드·실제
추가/수정/삭제 처리와 해당 테스트 내용을 대조했다.

현재 메뉴에서 사용자 소유 데이터의 로컬 수동 입력과 겹치는 HTML 개인 입력 흐름을 구현했다.
학교 공식 데이터, 서버 판정, RAG·AI·파일 저장·권한 연동은 구현 완료에 포함하지 않는다.
이 범위는 별도 계약 작업이며 개인 후속 메모에 유지한다. 봉사 증빙 출처 입력은 사용자 결정으로 제외한다.

## 메뉴별 입력·관계·검증 근거

공통 스키마는 `frontend/lib/features/records/personal_record_fields.dart`, 개인 UUID 저장소는
`personal_record_repository.dart`, 입력·수정·삭제 확인 UI는 `record_menu_page.dart`에 있다.
검증 파일 경로는 모두 `frontend/test/` 기준이다.

| 메뉴·ERD | 구현된 개인 입력·동작 | 확인한 코드·검증 근거 |
| --- | --- | --- |
| 수강 · Course/AcademicRecord | 이름·과목 코드·학기·이수구분·학점·분반·원 성적·개인 상태 CRUD, 학기 필터·개인 학점 합계 | 공통 스키마의 course, `course_page.dart`; `personal_records_test.dart`의 입력 실패 보존·학기 합계 및 수강 CRUD·재진입·삭제 |
| 활동 · VolunteerRecord/Experience.details | 기관·기간·역할·직접 입력 시간·확인한 승인 시간/상태/확인일 CRUD, 개인 승인 시간 집계 | 공통 스키마의 activity, `activity_page.dart`, RecordMenuPage의 approved 합산; `personal_records_test.dart`의 승인 시간 조건·활동 CRUD·확대 입력 |
| 경험 · Experience | 종류·제목·기관·기간·상태·역할·결과/기여 CRUD | 공통 스키마의 experience, `experience_page.dart`; `personal_records_test.dart`의 경험 입력·재진입·수정·삭제 |
| 자격 · UserCertificate/Certificate | 이름·기관·점수/등급·취득/만료일·보유 상태·증빙 URL CRUD, 증빙 링크 확인/외부 열기 | 공통 스키마의 credential, `credential_page.dart`; `personal_records_test.dart`의 자격 CRUD, `external_links_test.dart`의 URL·확인·취소·실패·플랫폼 요청 |
| 성과 · Experience.details/HTML work | 종류·기간·역할·결과·공개 가능한 URL CRUD | 공통 스키마의 portfolio, `portfolio_page.dart`; `personal_records_test.dart`의 성과 CRUD, `external_links_test.dart`의 성과 링크 |
| 논문·캡스톤 · ThesisRecord | 성과 원본 안에 제목·유형·개인 상태·원 성적·직접 확인한 승인일 보관 | 공통 스키마의 thesis 선택 필드, PortfolioSource.text; `thesis_record_test.dart`의 선택 필드 호환·실제 날짜·원 성적·재마운트·수정·삭제·확대 |
| 개인 교육과정 · Curriculum | 이름·학교·학과·입학연도·교육과정 연도·메모·출처 URL CRUD | `personal_graduation_workspace.dart`·공통 스키마; `personal_graduation_test.dart`의 세 목록 CRUD 및 프로필 수정 뒤 다른 목록 보존 |
| 교육과정 과목 · CurriculumCourse | 이름·코드·학점·이수구분·필수 여부, 개인 교육과정 필수 연결·수강 기록 선택 연결 | `personal_graduation_fields.dart`의 실제 개인 UUID 선택; `personal_graduation_test.dart`의 관계 검증·삭제 후 원본 보존 |
| 개인 규칙 · GraduationRuleSet/Rule 및 관련 요건 | 이름·코드·종류·학교/학과/교육과정 범위·필요/현재 값·단위·조건/대체 요건/성적 기준·기간·출처 CRUD, 교육과정·과목·개인 기록 연결 | `personal_graduation_fields.dart`의 연결 대상 재검사·교육과정 불일치 거부; `personal_graduation_test.dart`의 값/기간 검증·규칙 CRUD·끊어진 참조·판정 미표시 |
| 일정 · ERD 독립 엔터티 없음 | 제목·시작/종료 일시·분류·메모 CRUD, 달력·선택 날짜·주간 표시 | `planning_repository.dart`·`schedule_page.dart`; `widget_test.dart`의 저장·복원, `planning_storage_test.dart`의 실패 보존·삭제 확인/취소/재시도, `workspace_ux_test.dart`의 날짜 경계 |
| 설정 · User의 개인 소속 정보 | 학교·학과·입학연도·개인 계획 학년·주 시작 요일 저장 | `settings_page.dart`·PlanningProfile; `widget_test.dart`의 로컬 복원, `planning_storage_test.dart`의 프로필 저장 실패 보존·성공 표시·읽기 재시도 |
| 포트폴리오 구성·지원 문서 · HTML 확장 | 성과 선택·순서·소개·로컬 사용 의도, 지원처/직무/문서 종류/본문 CRUD·경험/성과 선택·확인 후 본문 추가·미리보기/복사 | `portfolio_workspace_repository.dart`·`portfolio_editor_dialog.dart`·`portfolio_drafts_page.dart`; `portfolio_workspace_test.dart`의 독립 저장·정렬·공개 검토·원본 삭제/실패·사용자 본문 보존·복사·좁은 창 |

공통 검증: 필수값, 양의 학점, 비음수·유한 숫자, 실제 날짜·기간 역전, 안전한 URL을 검사한다.
저장 성공 뒤 상태 확정, 읽기 실패 시 덮어쓰기 차단, 저장 실패 입력 유지, 삭제 확인을 구현했다.
fixture는 개인 수정/삭제·집계·구성 후보에 들어가지 않는다. 개인 기록·규칙·구성 삭제는 참조
원본을 연쇄 삭제하지 않으며 끊어진 참조를 명시한다.

## HTML 입력·사용 동작 대조

| HTML의 실제 흐름 | Flutter 대응과 차이 |
| --- | --- |
| recordsScreen / add-registration / remove-reg / reg-filter | 수강 CRUD·분반·학기 필터·합계. 이번 학기를 고정한 목업 대신 실제 개인 입력 학기를 선택한다. |
| activitiesScreen / add-volunteer / remove-volunteer / 1365 링크 | 봉사 CRUD·1365 확인 후 외부 열기. HTML의 단일 hours를 직접 입력/확인한 승인 시간으로 구분한다. |
| add-experience / remove-experience | 경험 종류·제목·기관·시작/종료 입력과 삭제. Flutter는 수정·재시작 보존·기간 검증도 제공한다. |
| add-certificate / remove-certificate | 자격 이름·점수/등급·취득일 입력과 삭제. 기관·만료일·증빙도 로컬로 관리한다. |
| portfolioScreen / add-work / remove-work / portfolio-pane | 세 단계 유지. 문자열 기간은 시작/종료일로 구조화하며, 역할·결과·공개 링크를 기록한다. 구성의 선택/순서와 지원 문서의 실제 로컬 편집도 구현했다. |
| affiliationCard / save-year / save-note | 개인 소속·입학연도는 설정과 개인 교육과정에서 입력한다. 공식 institution/department 선택·인증은 구현하지 않는다. |
| unifiedChatDock / workspaceLayer의 Q-Net 링크 | 자격 안내의 Q-Net 확인 링크를 AI 답변 없이 사용한다. 가짜 시험 일정·응시자격 답변을 옮기지 않는다. |
| clearPersonal / restoreSampleStudent / enter-sample | 합성 세션 시작용 목업 초기화다. 개인 저장 자료를 로그인/학교 변경 시 지우거나 fixture로 덮어쓰는 동작은 옮기지 않는다. 개발용 프로필/초기화 도구는 후속 메모에 둔다. |
| ask / apply-workspace-draft / analyze | 하드코딩 AI 답변·고정 제목 채우기·가짜 채용 분석은 실제 기능으로 옮기지 않는다. AI/RAG 계약 뒤 사용자 확인을 거친 초안 반영으로 연결한다. |
| 역할/학교 검색·공식 규칙·문서 뷰어 | 개인 입력과 다른 공식 데이터·권한·근거 문서 영역이다. 후속 계약 항목으로 남긴다. |

## ERD의 직접 입력하지 않는 부분

- 공식 Institution/Department/Course/Certificate/Provider 마스터의 식별자·국가 코드·활성 여부,
  User의 역할·학교 FK·서버 생성/수정 시각, SchoolAdminScope는 클라이언트에서 만들지 않는다.
- AcademicRecord의 계산용 점수·성적 체계별 환산·확정 이수학점은 서버 계약과 Rule Engine 책임이다.
  현재 credits는 개인 입력 과목 학점이며 earned_credits로 확정하지 않는다.
- VolunteerRecord의 파일 참조·등록 시각은 저장 어댑터/서버 계약 영역이다. 학교 승인 처리가 아니며
  증빙 원문·OCR·외부 LLM 전송은 구현하지 않는다. 출처 입력은 사용자 결정으로 제외했다.
- 공식 GraduationRuleSet의 버전·활성화·관계 테이블 및 rule_definition 실행,
  GraduationRuleCourse/Volunteer/Thesis/Certificate/Skill의 공식 비교·대체 그룹,
  GraduationAudit/Result와 감사 스냅샷은 개인 조건 메모와 구분한다. 계산 결과를 생성하지 않는다.
- UserCertificate의 마스터 FK·자격증 번호·유효성 정책·공식 인증은 추정하거나 수집하지 않는다.
- Skill/UserSkill/ExperienceSkill/CertificateSkill/CareerPath 및 관련 관계는 역량 판정·추천 계약 영역이다.
- Document/Chunk/Scope/CertificateDocument, JobPosting/Requirement/Match와 관련 관계,
  JobApplication, PiiProcessingAudit는 서버·공식 근거·채용·운영 단계의 계약 영역이다.
  포트폴리오의 지원 문서는 JobApplication이나 실제 제출 기록으로 취급하지 않는다.
- 삭제/수정 감사 이력·동기화·다중 규칙 기록 매핑·학교 연동 후 병합·설정 프로필 매핑·개인 자료 RAG,
  파일·게시/공유/제출 권한은 후속 계약으로 유지한다.

## 검증 결과와 한계

- 저장 안전성 단위의 전체 `flutter test` 77개 통과 결과를 확인했다. 대조표의 테스트 이름과
  검사 내용을 읽어 각 메뉴·저장/관계·삭제/실패·좁은 창의 검증 범위를 확인했다.
- 마지막 Q-Net 변경은 자격 화면 구성과 해당 테스트만 수정했다. 새 관련 2개가 통과했으며
  변경 없는 기존 77개 결과를 재사용했다. 전체 79개를 한 번에 실행했다고 주장하지 않는다.
- 마지막 변경의 `flutter analyze`, `flutter build web`, `flutter build windows` 각각 1회 성공.
  문서·메모 정리 뒤에는 코드 검증을 반복하지 않는다.
- 위젯 테스트는 로컬 저장 mock과 플랫폼 링크 어댑터를 사용한다. 실제 서버·학교 승인·RAG,
  Windows 기본 브라우저·네이티브 DPI/고대비 실행을 검증한 것은 아니다.
  해당 수동 QA와 별도 UX/UI 개선은 미완료 후속 메모에 남긴다.
