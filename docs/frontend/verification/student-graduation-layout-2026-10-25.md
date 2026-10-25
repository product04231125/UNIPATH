# 학생 졸업 기준의 혼합형 배치 — 2026-10-25

## 범위

학생 졸업 요건의 `내 학교·학과 기준 설정`에서 사용하는 LocalRecordWorkbench를 관리자 4번 혼합형과
같은 배치로 바꿨다. 학교·학과·교육과정·교육과정 과목·개인 규칙 모두 한 바깥 틀을 사용한다.
실제 계정에서는 기존과 같이 서버 계약이 있는 교육과정·과목·규칙만 제공한다.

- 상단: 왼쪽 목록(제목·개수·빈 상태 또는 등록 자료/수정·삭제·프로필 적용), 오른쪽 이름/학교·교육과정 연결.
- 하단: 전체 폭 적용 범위·상세·취소/저장. 짧은 항목은 2열, 설명/조건/URL은 전체 폭이다.
- 내부 목록 카드/입력 카드의 중첩 경계를 없앴다. 하나의 FormState와 기존 컨트롤러·검증·저장 동작을 유지한다.
- 공식 감사 화면과 개인 계산/이력·로컬/서버 repository·OpenAPI·DTO는 변경하지 않았다.
  실제 전송 키는 PersonalCurriculum/Create, Course/Create, Rule/Create의 기존 계약을 유지한다.

## 자동 검증

```powershell
D:/Project/flutter-3.47.5/bin/cache/dart-sdk/bin/dart.exe D:/Project/flutter-3.47.5/bin/cache/flutter_tools.snapshot test test/student_graduation_layout_test.dart test/personal_graduation_test.dart test/remote_personal_ui_test.dart test/page_header_test.dart test/official_graduation_ui_test.dart --name '^(?!.*(Size\(480|480x520|narrow|student creates school department)).*$' --reporter expanded
```

- 관련 데스크톱 회귀 19개 통과. 기존 학교/학과 검사 중 좁은 화면으로 바꾸는 복합 사례도 제외했고,
  신규 데스크톱 검사에서 학교 선택·학과 저장·탭 전환 입력 보호를 확인했다. 좁은 화면은 검증하지 않았다.
- 신규3개: 다섯 탭의 단일 바깥 틀·내부 카드 중첩 없음·목록/기본/상세의 위치/너비·필드 누락/중복 없음·
  연도 같은 행/긴 메모 전체 폭, 탭 변경 계속 작성·학교 연결 저장, 서버 수정 실패 입력 보존/재시도·기존 버전과 키.
- 기존 회귀: 교육과정/과목/규칙 CRUD·연결·검증·삭제·프로필 적용, 서버 저장소 사용,
  데스크톱 배율1/2 헤더·입력/공식 감사 재시도·이력 구분.
- 테스트 명령3회: 신규 테스트 첫 실행 2통과/1실패(기대값에 PATCH에서 제외되는 client_id를 포함한 테스트 오류),
  해당1개 정정 후 통과, 최종 관련19개 통과. 제품 저장 계약은 고치지 않았다.
- 분석2회: 신규 테스트의 조건문 중괄호 스타일1건을 정리한 뒤 문제 없음.
- Web/Windows 빌드 각1회 성공. 단일 화면 프레젠테이션 변경이라 전체 제품 테스트는 반복하지 않았다.
- 로컬 로그: frontend/student-graduation-regression.log, student-graduation-analyze.log,
  student-graduation-web-build.log, student-graduation-windows-build.log (Git 미추적).

## 브라우저 확인과 한계

Web 개발용 학생 샘플 1440×1100에서 빈 교육과정 목록·연도 2열·전체 폭 메모·서버 아님 안내를 확인했다.
합성 교육과정을 저장해 목록1개 반영과 수정 진입을 확인했고, 전체 프레임/버튼은 1440×1400에서도 캡처했다.
로컬 캡처는 frontend/build/admin-audit/student-graduation-empty.jpg 및 student-graduation-filled.jpg다.

운영 서버·실제 학교 데이터·Windows 네이티브 실기는 수행하지 않았다. 서버 실패/재시도는 합성 gateway
테스트이며 Windows 확인은 빌드 성공이다. 새 API나 공식 졸업 판정을 구현한 것으로 표시하지 않는다.
