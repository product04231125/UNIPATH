# 휴대폰 세로 Web 하단바 검증 (2026-11-03)

현재 정책은 [제품 UX](../product-ux.md)·[탐색](../features/navigation.md)·[플랫폼 차이](../platform-differences.md)를 따른다.

## 범위

- 판별: `width < 600 && height / width > 1.6` (`isPhonePortraitShell`)
- 셸: 학생·관리자 하단바 4+더보기, Web 상단 제목/탐색 chrome 숨김, 목업·서비스 재설명 문구 숨김
- 비대상: `480×520`·정확 `480×768`(비율 1.6)·`900×768`은 좌측 메뉴. 샘플 로그인 부울(`kShowDebugSampleLogin=false`) 미변경

## 자동 검증

- `flutter test test/phone_shell_layout_test.dart test/phone_shell_test.dart test/workspace_ux_test.dart` 통과 (로컬 `3747c05`)
- 위젯은 `startAuthenticated`로 셸만 확인. 브라우저 E2E 로그인은 샘플 진입이 꺼져 있어 실계정 없이는 로그인 후 하단바까지 실기하지 못함

## 브라우저 실기

- 목표: `390×844`에서 로그인 화면·(가능 시) 인증 후 하단바
- 결과는 같은 작업 단위의 완료 보고와 이 절을 갱신한다.
