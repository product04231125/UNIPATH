# 학교 분류·과목 화면 정리 검증

## 범위

- 기준: develop `288af01`, 브랜치 `codex/school-classification-ui`.
- 학생 설정의 고정 이수 경로 선택지를 제거하고 학업 프로필에서 기존 저장값을 읽기 전용으로 표시한다. 학교별 조회 API 대기이며 기존 track 값을 변환·삭제하지 않는다.
- 과목·교육과정 연결의 category/required와 추가 분류를 같은 구역에 배치한다. 기존 저장 요청·부분 성공 복구·초안 ID/복원 형식은 유지한다.
- 세 탭의 숨겨진 항목 간격 누적을 제거한다. 학교 분류는 경계·제목·개수·빈 상태·compact 수정/위험 삭제·3행 목록 스크롤과 끝 여백을 사용한다.
- 한 줄 요건·학점표·인증 조건·관련 규칙 묶음은 제외한다. 전용 코드와 기존 API 요청 내용은 보존하며 공유 선택기는 기본 표시를 그대로 유지한다.

## 검증 결과

- Windows / Flutter 3.47.5 / Dart 3.13.4.
- 설정 관련 7 통과: null/학교별 기존 track, 고정 목록 부재, 계획 학년 저장 실패·재시도 후 track 보존, 기존 학교 카탈로그 저장.
- 관리자 기존 회귀 59 통과: 과목 저장·분류 ID 연결·학점표 ID 유지·학교별 초안·관리자 입력/권한/목록.
- 레이아웃 4 통과: 기존 이수 경로 표시, 빈/데이터 있음의 세 탭 동일 시작 좌표, 다른 학교 분류 부재·긴 목록 스크롤.
- `flutter analyze --no-pub`: 문제 없음.
- `flutter test --reporter expanded`: **836 통과 / 13 생략 / 실패 0**. 제외 영역의 기존 회귀도 포함한다. 기존 생략 조건은 변경하지 않았다.
- 생략 13건은 격리 HTTP 서버 주소 미설정 11건(계정 보안 4, 개인 기록 2, 개인 계산 2, 학업/일정 1, 공식 감사 1, 원본 검토 1)과 기존 선택 실행 캡처 2건이다. 이번 화면 캡처 4건은 별도 옵션으로 실행·확인했다.
- `flutter build web --release --no-pub`: 성공(컴파일 31.9초).
- `flutter build windows --release --no-pub`: 성공(28.9초).

## 렌더링과 제한

- `flutter test --dart-define=SCHOOL_CLASSIFICATION_CAPTURE=true test/school_classification_layout_test.dart`로 실제 앱 테마·폰트의 1440×1100 위젯 렌더링을 생성하고 육안 확인했다.
- 캡처: `output/school-classification-ui/`의 settings, course, curriculum, curriculumCourse 및 classification-lists(cream/blue/orange). 산출물은 Git 제외다.
- 브라우저/Windows OS 창 수동 실기나 운영 계정 저장은 수행하지 않았다. 좁은 화면 신규/수동 검증도 추가하지 않았다.
- 학교 분류 CRUD·학교별 이수 경로 조회·추가 분류 참조 저장은 서버 계약 대기다. 기존 category/required 저장과 구분하며 backend·OpenAPI는 수정하지 않았다.
- API 요청 문서에는 이번 범위의 추가 요청만 적었고 기존 졸업요건 관련 요청 본문은 변경하지 않았다. 담당자 메시지 전송은 하지 않는다.
- 제품 원격 푸시·PR 생성은 이번 범위에서 제외한다.
