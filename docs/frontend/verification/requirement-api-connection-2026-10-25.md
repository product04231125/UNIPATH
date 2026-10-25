# 졸업요건 학생·관리자 API 연결 검증 — 2026-10-25

## 연결 범위와 계약

사용자 요청은 학생·관리자 폼의 종류별 입력을 기존 API에 연결하는 것이다. 신규 백엔드/DTO/enum은 추가하지 않았다.
계약 근거는 docs/api/openapi.json의 ProgramCreate/ProgramReplace/ProgramRuleInput 및 조건 스키마,
학사 rules API, 개인 계산 API와 생성된 Dart 모델이다. 설명 문자열을 실행식으로 해석하지 않는다.

| 흐름 | 연결 및 확인한 결과 |
| --- | --- |
| 학생 설명 저장 | 기존 개인 규칙 CRUD. 종류별 입력에 맞춰 메타데이터를 저장하고 자유 현재 값은 숨김 |
| 학생 조건 저장·계산 | 기존 개인 계산 요청/불변 이력. 최소120 전송, 같은 요청 ID/본문 재시도, 동일 요건 버전 조건 복원, 서버 결과 표시 |
| 관리자 설명 저장 | 기존 rules POST/PATCH. 응답 UUID 유지, 저장 후 폼 유지, 계산 조건 저장 때문에 요건을 재생성하지 않음 |
| 관리자 적용 | 명시적 확인 후 기존 apply. 묶음 소속이면 전체 적용 확인. 자동 실행 승인 없음 |
| 관리자 조건 저장 | 기존 rule-programs POST/PUT. 실제 rule/version·선택 근거·입학연도·이수 경로 전송 |
| 기존 묶음 수정 | 다른 규칙의 조건/근거/원본 버전과 실행본 expected_version 보존 |
| 실패/권한 | 422 입력 오류/입력 보존, 409 잠금 및 같은 초안 재선택 복구, 503 생성 응답 불명 뒤 조회/기존 UUID PUT, 403 근거 캐시 제거·성공 표시 없음 |
| 참조·작성 보호 | 6종 조건 왕복, 과목 버전 변경 거부·재선택, 종류별 초안 보존·폐기/계속 작성, 근거 페이지 버전 변경 거부 |

## 자동 검증

- 관련 8개 파일의 최종 데스크톱/비레이아웃 회귀 **68개 통과**. 이어 학교관리자 인증·학교 범위·동일 기존 실행 endpoint 요청 **1개 통과**. 총 서로 다른 관련 검사 69개.
- 선택 파일: admin_requirement_connection_test.dart, admin_workspace_test.dart, admin_list_panel_test.dart,
  remote_admin_test.dart, personal_requirement_panel_test.dart, student_graduation_layout_test.dart,
  personal_calculation_test.dart, personal_graduation_test.dart.
- 선택식: `^(?!.*(480|narrow|compact=true|compact admin header|inline registration preserves failures|student creates school department)).*$`.
  이름에 narrow가 없는 내부 480 전환 사례도 통째로 제외했다.
- 학생의 기존 5종 조건·명시적 관찰·버전 고정·소유자 격리·응답 유실 복구와 개인 기록 CRUD를 포함한다.
- 새 관리자 파일은 신규 UUID 연결/POST→PUT, 묶음 보존/동일 초안409복구, 422/409/503,
  종류 전환/폐기, 403, 근거 변경, 6종 DTO, 학교관리자 범위의 10개다.
- 최종 `flutter analyze --no-pub` 문제 없음. 마지막 학교관리자 추가는 테스트 코드만 변경했다.
- 최종 `flutter build web --no-pub`, `flutter build windows --no-pub` 모두 성공.
- 로그: frontend/requirement-connection-final-regression.log, requirement-school-admin-test.log,
  requirement-admin-final-test.log, requirement-admin-final-analyze.log,
  requirement-admin-final-web.log, requirement-admin-final-windows.log (로컬, Git 제외).

## 수정 중 실패와 재실행

이번 관리자 단위의 테스트 명령은 13회(잘못된 프로젝트 폴더에서 시작 전 종료한 1회 포함) 실행했다.
초기 합성 서버의 근거 경로/자격 URL/오류 문구를 실제 어댑터에 맞췄다. 초안 재조회 때 입력창이 갱신되지 않는
문제와 같은 UUID의409복구 문제를 고쳤고, 오래된 여러 줄 설명 기대를 한 줄 설명으로 변경했다.
배치 테스트의 TextFormField 속성 탐색 컴파일 오류는 내부 TextField 탐색으로 수정했다.
실패한 검사 중심으로 재실행하고 마지막 68개/학교관리자1개의 통과를 확인했다.
분석은 SDK 접근 차단1회 후 실제 실행4회이며 스타일 진단을 정리해 최종 문제 없음이다.
Web/Windows 빌드는 각각2회: 첫 성공 뒤 브라우저에서 새 관리자 입력의 라벨을 기존 외부 라벨과 맞춰
관련 검사를 재실행하고 양쪽을 다시 빌드했다. 라벨 수정 전 결과를 최종 결과로 대체하지 않았다.

## 브라우저 확인과 제한

로컬 debug 앱의 기본 데스크톱 viewport(1280×720)에서 관리자 규칙 종류 선택→최소 학점 입력,
외부 라벨·한 줄 설명·기간 행 배치, 미저장 입력 상태의 로그아웃 폐기 확인을 확인했다.
학생은 졸업 요건→내 학교·학과 기준 설정→개인 규칙→최소 학점 선택과 저장 불가 샘플 경계를 확인했다.
캡처는 frontend/build/admin-audit/requirement-admin-credit.jpg 및 requirement-student-form.jpg다.
이 캡처는 샘플 레이아웃 근거이며 실제 서버 저장 증거가 아니다.

HTTP 검증은 기존 AuthApi/RemoteAdminRepository/생성 DTO를 사용하는 합성 서버 테스트다.
운영 서버·실학교 데이터·Windows 실행 실기·최종 학교 승인은 미검증이다. 좁은 화면은 사용자 지시로 제외했다.
관리자는 계산 조건 초안까지 연결하며 승인/회수 화면은 이 변경 범위에 포함하지 않는다.
학생 조건은 개인 규칙의 typed 영속 필드가 없어 기존 계산 이력에 저장하며 현재 버전의 최신 이력에서 복원한다.

## 기존 관리자 PR #39 반영 검증

원본331983a의 관리자 변경을 develop 기반 기존 codex/admin-ui-layout에1e67a7b로 분리했다.
학생 계산 조건 파일·학생 기능 문서는 PR #40에 유지하며 이 PR에 포함하지 않는다.
위69개 통합 검증은 원본 브랜치 결과다. PR #39의 현재 코드에서는 관리자 관련4개 테스트 파일
(admin_requirement_connection/admin_workspace/admin_list_panel/remote_admin)의47개를 별도로 실행해 통과했다.
선택식은 `^(?!.*(480|narrow|compact=true|compact admin header|inline registration preserves failures)).*$`이다.
정적 분석 문제 없음·Web/Windows 빌드 각1회 성공. 로컬 로그 requirement-pr39-{test,analyze,web,windows}.log.
종류별 실행 초안 저장·메타데이터 적용·기존 관리자 CRUD/배치/권한·입력 보호의 분리 브랜치 검증이다.
운영 서버/Windows 실기 미검증과 별도 실행 승인 경계는 그대로다.
