# PR #48 API 누락 재감사 — 2026-11-07

## 범위와 검증 방법

기준 HEAD: `1a0e73040901a73958ed4b454663fb246252ab90`. PR #48의 develop 대비 **84개 커밋 메시지·본문**, 변경 파일 목록, 개인 메모의 관련 완료 이력(입력 임시저장, 활동/논문 간소화, 한 줄 요건, 학점표/인증, 역할 분리, 이력 필터, 자료/채용)과 활성 계약 의존성을 대조했다. PR #52의 구현·계획·병합은 다른 채팅 범위이므로 검토/수정하지 않았다. 아래 판단은 이 HEAD의 계약에 한정한다.

메모를 현재 구현의 증거로 대체하지 않았다. 화면 입력/클라이언트 DTO·adapter → FastAPI 경로/스키마 → 서비스/계산 → 재조회 경계를 확인했다. OpenAPI(174개 경로)의 관련 DTO·쿼리를 추출했다. 변경 프로덕션 파일은 98개이며, API 없는 시각/배치 변경은 아래 범위표에서 묶었다. 이 문서는 코드·계약 감사이며 실서버/실계정·브라우저 E2E 완료를 뜻하지 않는다. 초록 CI는 이 문서에 적은 미연결 기능의 완료 근거가 아니다.

## 결론

앞서 PR에 적은 봉사 계산·한 줄 체크리스트·졸업 기준 저장만으로는 부족했다. **추가 백엔드 요청은 과목 학과 소속, 관리 이력 서버 필터, 역할 분리 가입·심사, 채용 URL/파일 입력 계약**이다. 개인 자료 PDF/RAG 등은 기존 별도 후속 범위로 유지한다. **논문 계산, 기존 채용 텍스트 API 연결, 실행본 승인 UI, 수강 후보 범위는 기존 API를 사용하는 FE 후속**이다. 구현을 함께 요청받은 감사가 아니므로 이번 변경은 전달 문서이며 미연결 화면을 구현한 것으로 표시하지 않는다.

## 백엔드 변경·확정이 필요한 항목

| ID / 영향 | 대상 API | 현재 근거·왜 안 되는가 | 요청 계약과 수용 조건 |
| --- | --- | --- | --- |
| B1 개인 최소 봉사 시간 | `POST /api/v1/me/personal-evaluations`, `minimum_volunteer_hours` | `c998b51`이 활동 입력을 이름·reported_hours·메모로 줄였다. [서버](../../../backend/app/services/evaluations.py#L202)는 관찰일/승인/approved_hours만 사용한다. 새 입력 시간이 개인 계산에 반영되지 않는다. | 선택한 활동의 reported_hours를 합산. 승인/관찰일을 이 조건의 전제로 요구하지 않음. 기존 approved_hours만 있는 기록의 호환 정책, null/0/기준일 의미 확정. 10시간/최소10/승인·관찰일 없음 사례와 미선택 기록 제외를 회귀 검증. 공식 감사의 승인 시간 로직은 분리 유지. |
| B2 과목 원본의 학과 소속 **추가 누락** | `POST /api/v1/admin/courses`, `PATCH /api/v1/admin/courses/{record_id}`, 관리자/카탈로그 과목 목록·상세 응답 | 11/02 개인 메모·PR #45 요청 이력. [CourseCreate/Update/View](../../../backend/app/schemas/academic.py#L54)에 department_id 없음. 실제 DTO에 넣으면 extra_forbidden. 교육과정 연결의 department와 과목 원본 소속은 같은 계약이 아니다. | department_id 저장·반환, 같은 학교 학과 검증, 변경/삭제 참조 처리, 기존 과목 이전·학과 공통/학교 공통 과목의 null 정책 확정. 목록 학과 표시는 서버 저장값 기준. catalog의 기존 department_id 쿼리는 있으므로 새 쿼리라고 요청하지 않는다. 원본 소속과 교육과정 조인 필터의 의미를 함께 정렬. |
| B3 관리 이력 서버 검색·필터 **추가 누락** | `GET /api/v1/admin/audit-logs` | `aaad736`은 받은 이력의 로컬 검색·종류/행동 필터만 추가. [라우트](../../../backend/app/api/academic.py#L177)·OpenAPI는 institution_id/cursor/limit뿐. 화면의 기간·수행자·결과 검색 요구를 서버 계약으로 전달하지 않았다. | 대상/수행자/기간/결과·텍스트 검색의 지원 범위·정확한 쿼리명·시간대/기간 경계 확정. 기존 items/next_cursor, 학교 권한과 필터 변경 시 cursor 초기화 유지. 현재 로컬 필터 자체의 동작을 API 실패로 보지는 않음. |
| B4 가입·심사 역할 분리 **추가 누락 / 이미 합의된 목표 미구현** | `POST /api/v1/auth/school-admin-signups`, `POST /api/v1/auth/login`, `POST /api/v1/me/school-admin-applications`, `/api/v1/admin/school-admin-applications` 목록/상세/approve/reject, `/api/v1/admin/scopes` 생성·`/{id}/revoke` | #47의 [목표 계약](../../api/authentication.md)·[신청 계약](../../api/school-admin-applications.md). 현재 [가입](../../../backend/app/services/admin_signups.py#L136)은 auth.establish로 세션 발급. [로그인](../../../backend/app/services/auth.py#L154)은 신청 상태 가드 없이 establish. [추가 신청](../../../backend/app/services/admin_applications.py#L69)은 super_admin만 금지하여 학생이 신청 가능. 심사 read/list/decide 및 scope 쓰기는 require_super. FE에서 학생 신청을 숨기는 것으로 서버 정책이 완료되지 않는다. | 학생 계정의 추가 신청은 403 STUDENT_SCHOOL_ADMIN_APPLY_FORBIDDEN. 학교관리자 가입 201은 승인 전 세션/학생 셸 진입 없음. 로그인은 pending/rejected/cancelled와 반려 review_note를 전달하는 목표 오류 계약 확정. 기존 학교 추가 인력은 해당 학교 school_admin만 학교 전체 범위 승인/반려·부여/회수, 타 학교 접근 금지·동시성·권한 버전 검증. 최초/미등록 학교·첫 관리자는 super_admin 심사 유지. 하위 조교 역할 신설 아님. FE DTO·분기·테스트도 계약 확정 뒤 함께 변경 필요. |
| B5 관리자 학점표·인증 그룹 영속화 | 경로/메서드 미확정. 관리자 저장·읽기와 학생 조회 계약 필요 | [학점표](../../../frontend/lib/features/admin/graduation_credit_grid_page.dart#L419)·[인증](../../../frontend/lib/features/admin/graduation_certification_page.dart#L311)은 저장 버튼 disabled. 편집 복사본/미리보기뿐이며 rule-programs의 단일 계산 조건으로 표·그룹을 저장할 수 없다. | 학교/학과/교육과정/입학연도/경로별 버전과 안정 ID. 표의 열 그룹·행·셀·숫자/빈값/해당없음·비고, 소수 학점. 인증 그룹 모두/택1/택N·중첩·항목 순서·면제. 저장→재접속 재조회→학생 동일 내용 표시, 권한·버전 충돌·필드 오류 계약. API 경로를 FE가 추측하지 않음. |
| B6 학생 직접 체크의 영속화·집계 | 경로/메서드 미확정. 기존 공식 감사 생성/이력과 분리한 소유자별 체크 계약 필요 | `3f50a61`의 [학생 체크](../../../frontend/lib/features/graduation/official_graduation_page.dart#L128)는 _lineMarks 메모리만 변경, 키는 ruleId/문장. 재접속 유실·같은 문장 중복·문구 변경 추적 불가. 체크가 공식 감사 결과를 바꾸지 않는다. | 안정적인 줄/항목 ID와 기준 버전, 완료/미완료/미확인 저장·조회, 기준 변경 시 재확인, 항목별/그룹별 집계와 면제/해당없음. 학교 공식 판정과 학생 자기확인 결과는 응답에서 구별. 저장 성공 뒤 확정·실패 입력 보존·계정 격리·버전 충돌. 과거 불변 감사 결과를 학생 체크로 덮어쓰지 않음. |
| B7 채용 주소·PDF/캡처 입력 **추가 누락** | 기존 `POST /api/v1/me/job-analyses`, `POST /api/v1/me/personalization-contexts` 존재. URL/파일 수집 API 경로·전송 방식 미확정 | [JobAnalysisRequest](../../../backend/app/schemas/job_analysis.py#L16)는 records + 필수 posting_text만 받음. URL만 보내면 posting_text missing/URL extra_forbidden. [화면](../../../frontend/lib/features/records/portfolio/job_analysis_page.dart#L132)은 텍스트/주소/파일 중 하나 허용하지만 서버 호출 없음. | 텍스트 최소 API는 재개발 요청하지 않는다. 주소만/파일만인 입력을 서버가 받을 전송·원문 수집/추출·지원 형식/크기·실패/근거 계약 확정. 선택 기록의 UUID/버전·동의와 소유자 재검증 유지. 실제 분석기는 별도 담당 작업이며 PR #52 구현은 여기서 검토·변경하지 않음. 현재 HEAD의 기본 분석기는 not_configured 가능하므로 FE 연결만으로 분석 성공을 약속하지 않는다. |

### 이번 PR에서 이미 변경한 백엔드 계약 — 추가 구현 요청과 구분

`06f3fa0`: ProgramRuleInput.evidence_chunk_ids 생략/0–8개, 근거 없는 manual_review의 요건 종류·근거 적용 검사 예외. 대상은 `/admin/rule-programs` POST, `/{id}` PUT, `/{id}/approve`와 `/catalog/rule-programs` 목록/상세. [schema](../../../backend/app/schemas/rule_programs.py#L97), [저장](../../../backend/app/services/rule_programs.py#L159), [적용 검사](../../../backend/app/services/rule_programs.py#L456). 저장/승인/조회 회귀와 OpenAPI 일치 검사는 통과했다. 담당자 검토가 필요하지만 미구현 새 API로 다시 요청하지 않는다. manual_review는 여전히 자동 충족 계산이 아니다.

## 기존 계약으로 처리할 FE 누락·후속

| ID | 문제 / 근거 | 필요한 FE 작업과 API 변경 여부 |
| --- | --- | --- |
| F1 논문·졸업작품 완료 관찰 | `c998b51`에서 승인 선택·승인일·requiresApproval 토글 제거. [draft](../../../frontend/lib/features/graduation/personal_calculation_draft.dart#L140)는 requiresApproval=true, 관찰 approval 기본 needs_review. 새 기록은 완료를 골라도 needs_review. | 사용자 의도인 완료 기반 개인 확인은 기존 requires_approval=false로 전송 가능. 기존 이력/명시 승인 요구 조건의 호환과 accepted_grades 유지. API 신규 필드 불필요. 합성 엔진에서 동일 완료 레코드가 true→needs_review, false→satisfied를 확인. 수정 전에는 이 흐름의 완료 기능을 완료로 표시하지 않는다. |
| F2 채용 텍스트 최소 API 미연결 | 화면은 API가 없다고 표시하지만 backend/api/personalization.py와 OpenAPI에 두 경로 및 Dart 모델 존재. | 텍스트+사용자 선택 records(UUID/expected_version)의 기존 계약으로 연결 가능. 응답은 comparisons·근거·status/reason이지 임의 answer 문자열이 아님. UI 연결과 기본 분석기/주소·파일 계약 B7을 구분. PR #52 작업은 건드리지 않음. |
| F3 한 줄 실행 초안→학생 노출 | 관리자 패널은 create/replace만 호출하고 승인 UI는 없다. 공개 선택은 승인본만 반환. | 기존 rule-programs 승인/회수·검토 계약을 연결할 FE/운영 절차가 필요하다. 초안 저장 후 학생에 자동 노출된다고 안내하면 안 된다. 새 승인 API는 필요하지 않음. |
| F4 수강 후보의 적용 범위 | [loadCoursePickOptions](../../../frontend/lib/features/records/course/course_pick_options.dart#L55)는 school만 전달하고 모든 교육과정 연결을 courseId별 category에 합친다. 설정의 학과/교육과정과 다를 수 있음. | 기존 catalog/courses와 curriculum-courses의 department_id/curriculum_id 필터를 적용하는 FE 후속. 과목 원본 department_id 추가(B2)와 구분. 실제 선택 경로/프로필별 회귀 필요. API에 없는 필터를 만들 필요 없음. |
| F5 소수 학점표 | [parseCreditNumber](../../../frontend/lib/features/admin/graduation_credit_grid.dart#L63)는 int.tryParse, 합계도 int. | 소수 학점 파싱/정밀도·입력·합계·검증의 FE 보완. 기존 CourseCreate.credits는 Decimal(소수3자리) 지원하므로 과목 학점 API 변경 요청 아님. 표 저장은 B5 미확정 계약. |
| F6 공식 문서/기록/자격 관리의 남은 화면 | 개인 메모의 추출본 신규 등록·페이지 수정, 규칙 승인/회수, 자격 마스터, 학생 기록 교체 대상 선택은 기존 지식/공식기록/자격 API가 존재. | 기존 API 연결·권한 UI 후속. 새로운 저장 API가 없는 항목(B5/B6/개인 PDF)과 묶어 백엔드 재개발 요청하지 않음. |

### F7 공개 실행본 adapter의 빈 근거 거부 — 추가 재현

[OfficialProgramApi._validatePublic](../../../frontend/lib/features/api/rule_program_api.dart#L46)는 `rule.evidence.isEmpty`면 조건 종류와 무관하게 `Execution criterion lacks evidence` 예외를 낸다. B1~B7과 별개로, 이번 PR에서 서버가 허용한 빈 근거 manual_review를 FE adapter가 거부하는 계약 불일치다. 합성 approved/manual_review/evidence=[] 응답으로 `get()`의 FormatException을 재현했다.

현재 제품 lib에서 OfficialProgramApi 사용처는 해당 선언뿐이며 호출은 테스트에 있다. 실제 공식 감사 화면은 GraduationApi(`/me/graduation-audits`)를 사용하므로 이 발견만으로 현재 감사 화면 전체의 실패를 주장하지 않는다. 다만 공개 실행본 조회 연결 시에는 manual_review+근거0 예외를 FE에도 적용하고 일반 실행 조건의 근거 검사는 유지해야 한다. **새 백엔드 API는 필요하지 않다.** 감사용 임시 재현 테스트 1건을 실행한 뒤 제품 테스트 디렉터리에서 제거했다(로컬 tmp 보관).

## 이전 작업 전체의 기능별 대조표

| 커밋/메모 묶음 | 확인한 화면/상태·전송/저장 경계 | 판정 |
| --- | --- | --- |
| 로그인·계정 보안·루프백/CORS / 8dab020,e700f7e,076f8d9 | AuthApi/resolveApiBaseUrl, auth login/register/security, settings account entry, 동일 호스트 쿠키·Windows 토큰. 변경은 경로/호스트/진입·안내. | 기존 인증/보안 API. 목표 역할 분리는 B4. 새 비밀번호 API 불필요. |
| 학생 셸·휴대폰 탐색·설정 출처 / 3747c05~7a920fb,69e56c3,d1db4ce | workspace menu routing, planning profile 이름/카탈로그 IDs, 공식 감사와 개인 계산 분기 | 기존 profile/catalog/evaluation API. 셸용·연도 선택 전용 API 불필요. |
| 입학/수강 연도·학기 / d80579d,16ee013,247584a,1a0e730 | CourseTerm free-text term 인코딩·기존 원문 보존, admission_year int와 term 문자열 계약 | 기존 planning-profile/course-records. year/semester 새 필드 불필요. |
| 일정/홈 프로필 게이트·게스트 / 7f5c48e,d5573d9,e889558 | RemotePlanningRepository 생성/수정/삭제, version·실패 입력 보존과 미리보기 쓰기 차단 | 기존 /me/events·planning-profile. 새 일정 API 불필요. |
| 활동·경험 통합 / 9de9f89,c998b51 | ActivityPage에서 봉사·기타→activity-records, 프로젝트·인턴·동아리→experience-records; 숨긴 기존 필드 보존 | CRUD 변경 불필요. 개인 봉사 계산 B1, 논문 F1. |
| 자격·공식 출처/PDF / 2fada58 | credential-records와 official sources/files 경계, PDF 저장 취소와 오류 | 개인/학교 공식 자격은 별개. 기존 조회·제출 API. 정부24는 아래 별도 미착수. |
| 한 줄 요건·학생 표시 / 3f50a61,06f3fa0 | manual_review instruction·초안 저장·승인 공개·학생 메모리 mark | 이미 수정한 계약 + B6/F3. |
| 학점표·인증 / 39cbe05,b66efde,c149b80 | 로컬 복사본·미리보기·group validation | B5/F5. 저장/학생 전달 미완. |
| 관리자 카탈로그/수정·신규·전체 학교 / 51d06f5,47d4583,e71bfe8,77b6d01 | RemoteAdminRepository _body/saveWithResult POST/PATCH, expected_version, 학교 필터 | 기존 학사 API. 과목 학과만 B2. 인라인 폼·목록 배치용 API 불필요. |
| 관리자 계정 역할/상태 / 402edfa | PATCH /admin/users/{id}/access, role/account_status/expected_version | 기존 UserAccessChange 계약. 역할 편집 자체의 신규 API 불필요. B4의 신청/범위 권한 정책과 별개. |
| 관리 이력·신청 필터 / aaad736,a08d7c5 | 이력 로컬 필터, 신청 status/institution_id/cursor 기존 쿼리 | 이력 서버 고급 필터 B3. 신청 목록 필터 신규 API 불필요. |
| 게스트 미리보기 / 414b3d9,5dbe7e1,09fff51 | AuthIdentity 유지·GuestPreviewScope와 서버 현재 권한, 학생 데이터 쓰기/가져오기 차단 | 새로운 역할·학생 가장 API 불필요. B4 권한을 FE 플래그로 대체하지 않음. |
| 자료/포트폴리오/지원문서 / e66a1f7,bd4eb74,12e446b | 로컬 MaterialDatabase PDF, 서버 achievement/composition/application JSON, audience 닫힌 enum | 기존 JSON CRUD·오류 처리는 계약 변경 없음. 개인 PDF 서버 전송은 아래 별도 범위. |
| 채용 입력 / af53e50,69a7472 | 텍스트/주소/파일 로컬 보존, 선택 기록에서 수강 제외, 파일 서명 검사 | B7/F2. 존재하는 최소 API를 부재로 안내한 문서/화면의 낡은 상태 확인. |
| 임시저장 / bdff1a0,b21632c | 계정×화면 FormDraftStore, Web sessionStorage/Windows SharedPreferences, 로그아웃 초안 제거 | 사용자 의도는 클라이언트 임시저장. 서버/기기간 동기화 API는 요구하지 않음. |
| 검색·커서·선택 / 9173f7d,b9195af,61cefa8,4d9ed91 | 기존 카탈로그 next_cursor 순회·중복 cursor 차단·선택값 누락 표시 | 서버 정상 계약 유지. 검색 팝업 전용 API 불필요. |
| 순수 시각/배치/테마 / ed78baa,08b7ec1,634fb68,d555e23,56985f2,328fb5f,8c5390d 외 | FeaturePage/FeatureLine, 목록 높이·카드·ㄷ자·호버·숫자 안내·버튼 순서 | 새 API/데이터 저장 변경 없음. |

### 별도 후속 요구 — 지금 구현된 기능과 혼동 금지

- 개인 PDF/내용 서버 업로드·보관/삭제·동의·추출/RAG·근거 조회: 현재 자료 메뉴는 로컬 보관이다. 기존 `/me/record-sources`의 학교 발급 공식 PDF 경로를 개인 자료 업로드로 재사용하지 않는다. 미정 API 경로를 만들어 게시하지 않음.
- 정부24/Q-Net/CODEF, 관리자 CSV 템플릿·검증/미리보기/일괄 저장, 대화 이력 저장은 메모의 별도 미착수/후속 계약이다. 현재 PR의 자동 인증·외부 조회·클라우드 대화 보존 완료로 주장하지 않는다.
- 학사 안내/채용·맞춤 AI 관련 PR #52 진행/코드는 다른 채팅 소유. 이 감사에서 재조사·수정·전달 범위를 확대하지 않는다.
- docs/frontend/architecture.md의 '공식 졸업 판정 API 미연결', portfolio.md의 '채용 경로 없음' 같은 과거 서술은 현재 코드/OpenAPI와 충돌한다. 현재 API 존재/FE 미연결/별도 미계약을 이 문서처럼 나누어 읽어야 한다.

## 수행 검증과 한계

- `pytest backend/tests/test_student_contracts.py -q`: 1통과. 게시 OpenAPI와 이 HEAD의 FastAPI 스키마 동일.
- 합성 DTO 검사: CourseCreate.department_id → extra_forbidden; URL-only JobAnalysisRequest → posting_text missing + posting_url extra_forbidden.
- 합성 엔진 검사: 완료 논문/승인 needs_review, requires_approval=true → needs_review; false → satisfied. 승인 관찰 없는 봉사 → needs_review. 서비스의 reported_hours 미사용은 코드와 함께 대조했다.
- FE 공개 조회 합성 재현: approved/manual_review/evidence=[]를 전달하면 FormatException을 내는 현행 adapter 동작 확인(재현 1통과).
- 프로덕션 코드 수정 없음. API·DB·브라우저 E2E는 이번 감사에서 실행하지 않았고, 합성 검사로 실서버 권한 경합/계약 수용 조건 전체가 검증됐다고 하지 않는다. 이전 최종 CI(Frontend 736통과/11생략, Backend 성공)는 당시 HEAD의 회귀 결과다.
- 산출물: 이 근거표와 PR #48 백엔드 요청 보완. B/F 항목 구현은 남아 있다. 실제 분석/외부 연계·새 계약 완료를 Ready와 동일시하지 않는다.

## 조사한 커밋 목록

```text
1a0e730 fix(frontend): 수강 기간 보존과 현재 UX 기준 CI 회귀 정렬
4d9ed91 fix(ui): 선택 목록 갱신 후 사라진 값의 표시 예외 방지
b21632c fix(drafts): Web 임시저장을 표준 브라우저 바인딩으로 전환
06f3fa0 fix(rules): 근거 없는 수동 체크리스트의 적용 검사와 계약 정렬
789f3f1 merge: develop 문서 충돌 5개를 목표 계약 표기와 FE 설명으로 맞춘다
e359bdd feat(forms): digitsOnly 필드에 빨간 숫자만 안내를 단다
0833d77 fix(ui): 추가 버튼을 불러오기보다 앞에 둔다
bdff1a0 feat(forms): 클라이언트 임시저장·불러오기와 폐기 3선택을 넣는다
8c5390d fix(ui): 관리 혼합 화면을 목록 감싸기 배치로 되돌린다
b9195af fix(catalog): 반복 next_cursor로 카탈로그 페이지네이션이 멈추지 않던 문제를 막는다
61cefa8 fix(ui): 검색형 AnchoredSelect 메뉴 열기 시 hasSize assert 폭주를 막는다
0cdb12b fix(ui): 검색 메뉴의 불필요한 null 단언을 뺀다
12e446b fix(ui): 내 자료 목록 카드를 등록 폼과 같은 높이로 맞춘다
c66a62d fix(ui): 관리 화면은 등록 정보 아래 목록을 둔다
77b6d01 fix(ui): 슈퍼관리자는 기본으로 전체 학교를 본다
c998b51 fix(ui): 활동 기록을 이름·시간·메모로 줄인다
9173f7d fix(ui): 검색창을 고정하고 선택만 스크롤한다
bc28c80 fix(admin): 졸업요건 보기 전환을 함수 선언으로 둔다
402edfa fix(admin): 사용자 수정에서 역할과 계정 상태를 연다
3f50a61 feat(admin): 한 줄 요건을 규정 문장과 충족 표시로 바꾼다
39cbe05 feat(admin): 학점표와 인증 요건을 카드로 두고 추가한 항목을 제거한다
be74116 fix(admin): 졸업요건에서 지금 보는 보기를 채운 버튼으로 구분한다
8cade93 fix(admin): 목록 세로선을 등록 기본 정보와의 경계로 옮긴다
b66efde fix(admin): 잘못된 택 N은 오류로 보여 주고 미리보기는 연다
a08d7c5 fix(admin): 관리 이력 검색 시 기술 식별자 펼침이 다른 기록으로 옮겨가지 않게 한다
e71bfe8 fix(admin): 교육과정·과목 새 등록이 이전 레코드를 덮어쓰지 않게 한다
47d4583 fix(admin): 학교·학과 새 등록이 이전 레코드를 덮어쓰지 않게 한다
c149b80 fix(admin): 졸업요건 초안이 원본을 바꾸거나 이전 응답을 덮지 않게 한다
09fff51 fix(admin): 학교관리자 화면에 슈퍼관리자 메뉴가 나오지 않게 한다
bd4eb74 fix(portfolio): 알 수 없는 사용 의도를 읽기 실패로 유지한다
69a7472 fix(job-analysis): PNG 서명 전체 8바이트를 검사한다
d39f37a fix(settings): 저장 중 프로필 입력의 키보드 포커스도 차단한다
e66a1f7 fix(materials): 자료 종류 잔상과 초안 중복 열기·저장을 막는다
9de9f89 feat(activity): 활동 메뉴에 경험 기록을 다시 통합한다
2fada58 fix(credential): 공식 출처 조회 실패와 PDF 저장 취소를 고친다
3b1a220 fix(activity): 게스트 전환 중 저장·삭제와 승인 안내를 고친다
d995841 fix(graduation): 프로필 조회 실패와 교육과정 재조회를 구분한다
d1db4ce feat(graduation): 졸업 요건이 설정의 등록·개인 출처를 따른다
26f2dfd fix(graduation): 게스트 쓰기·빈/오류 구분과 요건 전환 혼입을 고친다
fac26ba fix(course): 과목 후보 실패 안내와 게스트 삭제 차단을 보강한다
d5573d9 fix(schedule): 게스트·쓰기 차단과 일정 저장 실패 보존을 보강한다
e889558 fix(home): 게스트 미리보기에서 홈 일정 추가를 막는다
414b3d9 fix(guest): 기록 폼·프로필 적용과 미리보기 학교 문맥 누락을 막는다
247584a fix(course): 범위 밖 연도·비표준 학기 수정이 막히지 않게 한다
5dbe7e1 fix(guest): 미리보기에서 개인 교육과정 쓰기와 학교 문맥을 지킨다
aa8aaaf docs(frontend): product-ux에 등록·개인 출처와 연도 선택 원칙을 반영한다
2411db9 docs(frontend): 등록·개인 설정 구분과 연도 선택 규칙을 반영한다
d80579d feat(settings): 입학연도를 1900~현재 검색 선택으로 바꾼다
16ee013 feat(course): 수강 연도·학기를 검색 선택으로 통일한다
7f5c48e feat(planning): 학업 프로필 없이 수강·일정 추가를 막는다
f344e5b feat(records): 수강 목록 딱지를 빼고 개인 설정 작업에 붙인다
69e56c3 feat(settings): 학업 프로필 출처를 등록·개인 설정으로 표시한다
af53e50 fix(portfolio): 채용 분석 비교 기록에서 수강을 제외한다
328fb5f docs(frontend): 현황·등록 틀과 FeaturePage 카드 규칙을 반영한다
65be288 fix(ui): 학생·관리자 FeaturePage 빈 본문을 SurfaceCard로 통일한다
43ef769 fix(admin): 등록 목록에 ㄷ자 테두리를 두고 섹션 Divider를 없앤다
a6bfafe fix(admin): 현황 초안을 제거하고 바로가기·자료 등록을 맞춘다
e97fbfe fix(ui): 제목줄 학교·목록/접수/테마 필드 겹침을 줄인다
fd1cd8b fix(ui): FeatureLine.reload를 섹션용 compact(~36)로 줄인다
aaad736 feat(admin): 제목줄 학교·목록 밀도·이력 필터·게스트 미리보기를 넣는다
2150c9e fix(ui): 필수 표기·수강 선택·관리자 목록·역할 trailing을 복구한다
51d06f5 feat(admin): 목록 수정을 상시 폼으로 옮기고 취소·저장을 가로로 둔다
978e259 merge: develop의 관리자·자료·채용·Gherkin 보강을 가져온다
56985f2 fix(ui): 본문 시작선과 일정 가시성을 맞춘다
d555e23 fix(ui): 본문 섹션 위아래 간격을 틀에 넣는다
c8b607e fix(ui): 개인 규칙 섹션 제목 중복을 제거한다
33ffe8c feat(ui): 개인 학업 입력을 관리자 혼합 틀에 맞춘다
15fe7d5 feat(ui): 졸업을 요약·기준일로 줄이고 설정을 통일한다
634fb68 fix(ui): 수강 목록 제목과 연도·학기 필터가 겹치지 않게 한다
08b7ec1 fix(ui): 학생·관리자 본문을 줄 틀로 옮긴다
ed78baa feat(ui): 메뉴 FeaturePage와 한 줄·두 줄 본문 틀을 둔다
1bb155b feat(ui): 관리자 전역 RAG 배너와 판정 아님 문구를 제거한다.
2b69600 feat(ui): 졸업·공식기록 화면에서 판정 아님 문구를 뺀다.
af8fbcd feat(ui): 학생 메뉴를 제목과 한 줄 설명으로 정리한다.
276d32a fix(ui): PhoneChromeScope가 없으면 화면 비율로 밀도를 켜지 않는다
32cfeaa docs(ui): 휴대폰 셸 인증 후 브라우저 실기를 기록한다
b063d08 fix(ui): 휴대폰 여백·헤더·하단바 밀도를 줄여 스크롤을 줄인다
7a920fb fix(ui): 휴대폰 하단을 일정·졸업·홈·자료·채용 순으로 둔다
076f8d9 fix(ui): 계정 보안·학교 신청을 설정으로 옮긴다
d8c4546 feat(ui): 학생 메뉴를 자료·채용공고 분석으로 맞춘다
1311514 feat(planning): 학업 프로필 준비 여부와 설정 이동 CTA를 공통화한다
1274484 fix(ui): 목업용 예시 데이터 토글과 제품 fixture를 제거한다
e700f7e fix(auth): Web 루프백 API 호스트를 페이지에 맞춰 Strict 쿠키가 붙게 한다
8dab020 fix(auth): Web 로그인 CORS와 비밀번호 remount를 맞춘다
```
