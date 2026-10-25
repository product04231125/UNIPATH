# 관리자 화면 데스크톱 배치 검토 — 2026-10-25

## 범위와 한계

- 대상: feature/frontend-integration-audit 21d059f, Flutter Web 개발 샘플, 크림·브라운 테마, 1440×900, 기본 글자 크기.
- 슈퍼관리자: 관리 현황, 학교/학과, 교육과정/과목, 졸업요건, 공식 문서, 관리 이력, 관리자 관리, 설정, 학교관리자 신청 접수 안내.
- 학교관리자: 관리 현황, 학교/학과, 교육과정/과목, 졸업요건, 공식 문서, 관리 이력, 설정, 학교 상세.
- 샘플 접수 메뉴는 실제 계정 필요 안내까지만 확인했다. 실제 서버 접수 목록/심사, 학교 문서 근거 검토 화면, 많은 데이터, 다른 테마, 글자 확대 및 Windows 네이티브는 이번 시각 검토 대상에 포함하지 않았다.
- 사용자 결정으로 좁은 화면 대응 검증은 앞으로 제외한다. 기존 반응형 구현을 제거하는 결정은 아니다.
- UI 코드는 변경하지 않았다. 문서만 추가하므로 분석·테스트·빌드는 재실행하지 않았다.

## 주요 발견과 수정 후보

| 우선순위 | 발견 | 영향과 수정 후보 | 근거 |
| --- | --- | --- | --- |
| P1 | 메뉴를 바꿔도 이전 스크롤 위치가 남는다. 교육과정 과목 연결 영역까지 이동 후 관리자 관리로 전환하면 사용자 목록 아래에서 시작한다. 짧은 관리 현황을 거쳐 재진입하면 상단부터 보인다. | 새 메뉴의 제목·첫 작업을 놓친다. 명시적 메뉴 전환 시 스크롤 초기화 또는 경로별 스크롤 소유권을 정의한다. 뒤로가기 복원과 동일 화면 편집의 위치 보존은 구분한다. | admin_workspace.dart:940, content_scroll_view.dart:20, super-accounts.jpg / super-accounts-top.jpg |
| P1 | 슈퍼관리자 사용자 목록이 왼쪽 절반만 사용하고 오른쪽은 비어 있다. 사용자의 관리 범위는 아래 별도 목록/폼에 있다. | 세 명도 첫 화면에 모두 보이지 않으며 사용자와 범위의 관계를 비교하기 어렵다. 목록 전체 폭 또는 선택 사용자/관리 범위의 양쪽 배치를 검토한다. 전역 사용자 목록에는 현재 학교의 적용 범위를 명확히 표시한다. | admin_workspace.dart:361, super-accounts-top.jpg |
| P2 | 교육과정·과목·연결 등록이 긴 본문에서 떨어져 있다. 연결 폼에서는 위 교육과정의 문맥이 사라진다. | 선택 교육과정과 연결 과목/추가 행동을 가까이 묶는다. 기존 계약의 필드를 임의로 변경하지 않는다. | super-curricula.jpg, super-course-link.jpg, school-curricula.jpg |
| P2 | 역할·작업 공간·현재 학교·관리 범위가 제목보다 먼저 반복된다. 학교와 무관한 테마 설정에도 학교 선택이 남는다. | 제목과 실제 작업이 아래로 밀린다. 문맥을 한 줄로 묶고 화면에 필요한 학교 선택만 표시하는 시안을 비교한다. | admin_workspace.dart:934 이후, super-settings.jpg, school-settings.jpg |
| P2 | 짧은 정보에도 큰 카드와 반복 행동이 배치된다. 상시 등록 폼과 같은 이름의 등록 버튼이 함께 나타난다. | 목록의 이름/상태/행동을 정렬하고 폼 이동 버튼의 의미를 분명히 한다. 삭제의 붉은 배경·확인 정책을 유지하면서 일반 조회/수정과의 시각적 우선순위를 조정한다. | super-schools.jpg, school-schools.jpg, super-accounts-top.jpg |
| P2 | 학교 상세의 전체 폭 목록 복귀 버튼이 대상 제목보다 앞선다. 기본 정보와 변경 정보가 멀리 떨어진다. | 작은 복귀 제어와 대상명/수정 행동을 묶는다. 기술 식별자의 접힌 보조 영역은 유지한다. | admin_workspace.dart:572, school-school-detail.jpg |

선택 메뉴의 강조와 보조 설명 글씨도 약하게 보인다. 이는 시각적 관찰이며 대비 수치 측정이나 접근성 적합 판정은 아니다. 관리 현황은 초안 0개에서 확인 행동을 간결하게 하고 다음 등록 작업의 우선순위를 드러낼 수 있다. 설정의 여백을 채우기 위해 기능을 추가하지 않는다.

## 유지할 부분과 다음 순서

학교관리자는 관리자 관리/학교관리자 접수 메뉴가 숨겨지고 두 역할의 탐색 구조는 일관된다. 본문 등록 폼, 입력 보호, 접힌 기술 식별자와 기존 삭제 정책은 유지할 요소다. 이번에는 입력 보호의 모든 동작을 재검증하지 않았다.

구현 후보 순서는 메뉴 전환 스크롤 → 공통 문맥 헤더 → 사용자/관리 범위와 교육과정/과목 관계 → 목록 밀도다. 검토 완료와 개선 구현 완료는 구분한다.

## 로컬 시각 근거

캡처는 이 체크아웃의 `frontend/build/admin-audit/`에 저장했다. Git에 포함하지 않은 로컬 파일이므로 다른 체크아웃에는 존재하지 않는다.

- 슈퍼관리자: super-overview.jpg, super-schools.jpg, super-curricula.jpg, super-course-link.jpg, super-accounts.jpg, super-accounts-top.jpg, super-documents.jpg, super-rules.jpg, super-history.jpg, super-settings.jpg, super-inbox.jpg.
- 학교관리자: school-overview.jpg, school-schools.jpg, school-curricula.jpg, school-rules.jpg, school-documents.jpg, school-history.jpg, school-settings.jpg, school-school-detail.jpg.
