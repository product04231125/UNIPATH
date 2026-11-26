# 학교 안내 진입 정리

- 기준: `origin/develop` `bd09f9f`, 작업 브랜치 `codex/chat-guidance-cleanup`.
- PR #67: 학교 게시 기준 카드·빈 상태 보완과 렌더링 검사(2dd7eda, 8ee82b2, 1abab51).
- PR #68: 등록 자료 표시·수강 선택 제외(981f011), 홈 초기 스크롤 수정(d42abd8).
- PR #69: 기존 OCR/추천 API 구현과 프런트 연결·검증 기록(d88180b, f11266d, 4c9f1da). 기존 서버 구현을 가져왔으며 백엔드·DB·RAG를 새로 구현하거나 수정하지 않았다.
- Workspace 충돌은 계정별 자료 저장소 공유·변경 후 채팅 갱신과 추천 화면을 함께 보존해 해결했다. 이후 학교 안내의 취업 화면 이동은 제거했다.

## 변경 및 수용 조건

- 서버가 취업 노드를 보내도 학교 안내에 취업 그룹·하위 항목·workflow 이동 버튼이 나타나지 않는다.
- 학교 메뉴·원문·일반 기준·공식 감사·맞춤 LLM 질문과 명시적 기록 선택은 유지한다.
- 분리 창에서도 취업 노드 이동을 보내지 않으며 제거된 취업 IPC 명령은 거부한다.
- 취업 업무는 기존 채용공고 분석 메뉴에서 실행한다. 추천 화면 복귀 시 공고 본문을 보존한다.

## 검증

- 최종 전체 `flutter test --no-pub`: **907 통과, 기존 선택형 13 생략, 실패 0**. 여러 PR의 Workspace·자료 저장소·IPC 통합을 함께 검사했다.
- 분석의 테스트 중복 import 한 건을 제거한 뒤 영향받은 학교 안내 테스트 **12 통과**, `flutter analyze --no-pub` **문제 없음**.
- `flutter build web --release --no-pub`, `flutter build windows --release --no-pub` **성공**. Windows 일반 앱 EXE를 빌드했으며 실행 실기와 구분한다.
- 로그는 비추적 `output/chat-guidance-cleanup/{flutter-test,guidance-test,flutter-analyze,build-web,build-windows}.log`에 보관한다.
- 렌더링: 1440×1000/DPR 1, 실제 Pretendard·MaterialIcons, 크림·블루 100%와 다크 오렌지 200%. 합성 서버 응답으로 학교 그룹 유지·취업 그룹 제거·학교 하위 탐색을 확인한다. 이미지: 작업 폴더 `output/chat-guidance-cleanup/school_*.png`.
- 실제 학생 데이터·OCR·외부 모델 실행·서버 배포·브라우저/네이티브 EXE 수동 실기는 수행하지 않는다. 학교 미연결·모델 미설정 등 기존 계약 제한을 유지한다.
