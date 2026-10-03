# 자격

## 목적

자격증·어학·교육 이수 기록을 개인 자격·인증 기준과 연결 가능한 보조 기록으로 관리한다.

## 현재 구현

- `frontend/lib/features/records/credential/credential_page.dart`가 화면·입력 상태를 소유한다.
- 예시 행은 `frontend/lib/features/records/fixtures/credential_fixture.dart`에 있다.
- 자격명·발급 기관·점수/등급·취득/만료일·보유 상태·증빙 링크를 분리 입력한다.
  기기 로컬 개인 기록 CRUD를 제공하며 자격증 번호는 수집하지 않는다.
  상세 경계는 [ERD 대조](../manual-input-boundaries.md)를 따른다.

## 목업 경계

- 현재 상태와 직접 입력은 취득 진위, 학교 필수 여부, 공식 인증을 뜻하지 않는다.
- Q-Net 등 외부 기관의 자동 등록·취득 처리는 구현하지 않는다.

## 후속 계약·검증

- 화면의 입력 라벨과 받은 상태 표시는 합의된 API 계약에 연결한다. 서버 필드와 상태 enum의
  의미는 이 문서에서 정의하지 않는다.
- 직접 입력의 메뉴 내 반영을 위젯 테스트한다.
