# 수강 연도·학기 — 2026-10-25

## 요구와 구현 근거

| 요구 | 구현 및 확인 |
| --- | --- |
| 연도와 학기 구분 입력·표시 | RecordMenuPage의 수강 전용 연도 입력, CourseTerm의 기존 term 인코딩·표시. 신규는 올해 기본값을 수정 가능하며 과거/계획 연도와 자유 학기 이름 지원 |
| 연도·학기 조합 필터와 합계 | 개인 기록에서 선택지를 생성, 두 조건을 함께 적용하고 필터 결과만 개인 학점 합계에 반영. 같은 1학기를 2025/2026/미지정으로 구분 |
| 기존 연도 없는 자료 보존·보완 | 기존 수정에서 연도는 공란. 임의 올해 배정 없이 미지정 표시·필터. 확인한 연도 입력 후 명시 저장. 기간 미수정 시 term 원문/공백 보존 |
| 계약 유지 | docs/api/openapi.json CourseRecordCreate의 필수 term 문자열 1~128자 사용. DTO·서버·API 변경 없음. 테스트에서 POST 전체 키와 PATCH expected_version/client_id 경계 확인 |
| 입력·취소·재시도 보호 | 기본 연도만 있는 폼·공백은 빈 폼, 실제 연도 변경은 작성 상태. 계속 작성 보존, 서버 실패 후 동일 ID/본문 재시도, 기존 버전/원래 term 보존 |
| 필터 항목 소멸 | 마지막 필터 대상 삭제 후 선택지/선택값 유지·빈 결과 안내. 전체 연도/학기로 복귀 가능 |

수강 연도는 사용자가 지정하는 학년도다. 달력 날짜에서 학기나 겨울학기의 학년도를 계산하지 않는다.
해석하는 기존 형식은 YYYY년/학년도 + 공백 + 학기, YYYY-1/2, YYYY/1 또는 YYYY/2다.
다른 자유 문자열은 연도를 추론하지 않는다. 기존 서버 문자열 계약에 대한 클라이언트 표현 규칙이며
서버의 구조화된 연도 검색이나 공식 수강 연도 계약을 새로 정의하지 않는다.

## 자동 검증

최종 데스크톱 회귀 55개 통과:

```powershell
D:/Project/flutter-3.47.5/bin/cache/dart-sdk/bin/dart.exe D:/Project/flutter-3.47.5/bin/cache/flutter_tools.snapshot test test/course_period_test.dart test/personal_records_test.dart test/remote_personal_ui_test.dart test/personal_record_codec_test.dart test/input_dialog_test.dart test/thesis_record_test.dart test/page_header_test.dart --name '^(?!.*(Size\(480|narrow|course prioritizes personal records)).*$' --reporter expanded
```

- 신규 기간 테스트 7개: 인식 형식/자유 문자열·학년도 검증, 200% 데스크톱 조합 필터, 과거 계절학기·문자열 길이·재로드, 기존 원문 보존/연도 보완, 마지막 필터 대상 삭제, 공백 취소, 기본 연도/변경 폐기 확인.
- 서버 신규 1개: 실패 후 연도/학기 보존·동일 create 재시도·기존 term payload·버전 있는 수정.
  기존 서버 충돌 2개(1440×900, 배율 1/2)에 원래 2026-2 보존 검사를 추가했다.
- 공유 기록 폼은 수강 분기에 한정해 변경했다. 활동·경험·자격·성과 CRUD/입력 보호·헤더/codec 회귀를 포함했다.
  공통 저장소·테마·탐색·의존성 변경은 없어 전체 제품 테스트는 반복하지 않았다.
- 테스트 실행 5회: 기간5개, 서버3개, 관련53개, 입력 보호 보완20개, 최종55개 모두 통과.
  별도 1회는 Windows bat의 선택식 전달 오류로 테스트 시작 전 종료했다. 최종은 SDK 실행 파일로 직접 전달했다.
- 분석 3회: 최초 조건문 스타일1건을 고친 뒤 통과, 마지막 입력 보호/기간 해석 변경 후 다시 통과.
- Web/Windows 빌드 각2회: 초기 성공 뒤 공백 입력 보호·기간 해석이 바뀌어 최종 코드로 재실행했다.
- 로그는 로컬 frontend/course-management-final-test.log, course-management-analyze.log,
  course-management-web-build.log, course-management-windows-build.log에 둔다(저장소 미추적).

## 렌더링과 검증 한계

Web debug 샘플 1440×1100에서 과거 연도 2025·여름 계절학기 입력/저장·필터 적용·3학점 합계를 확인했다.
모달 입력과 저장 후 목록은 frontend/build/admin-audit/course-period-form.jpg,
course-period-filtered.jpg에 캡처했다(로컬 산출물).

학교 공식 기록·운영 서버 HTTP 왕복·Windows 네이티브 실기는 이번 범위 밖이며 합성 gateway 테스트와
Windows 빌드 성공으로 구분한다. 좁은 화면 검증은 사용자 결정으로 제외했다. 새 API나 서버 연도 필드가
준비됐다고 표시하지 않는다. 별도 구조화 연도 계약이 생기면 이 기존 문자열 표현과의 이전 정책을 확인한다.
