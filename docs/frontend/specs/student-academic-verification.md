# 학생 학사 기준 연결 검증 — 2026-11-08

관리자 4ba309d를 기반으로 codex/student-academic-integration에서 구현했다.
현재 실제 계약은 [학생 학사 API](../../api/student-academic.md)와 생성 OpenAPI다.

| 검사 | 결과 |
| --- | --- |
| 백엔드 전체 | 568 통과, 기존 3 생략, 75 subtests 통과 |
| 새 학생 실제 PostgreSQL 검사 | 8 통과, 전체 결과에 포함 |
| 프런트 전체 | 854 통과, 기존 13 생략 |
| 새 학생 UI·상태·복구 검사 | 9 통과, 최종 캡처 환경에서도 재확인 |
| Flutter analyze / Ruff | 문제 없음 |
| Web / Windows release build | 모두 성공 |
| 생성 OpenAPI | 실행 앱과 일치, 기존 path/schema 의미 보존, 총 205 paths |
| Alembic check | 0018과 모델의 차이 없음 |
| migration 보존 | 0017↔0018 왕복 후 62개 기존 테이블의 합성 8행 완전 동일 |

DB 검사는 작업 전용 PostgreSQL17/pgvector 컨테이너와 격리 schema를 사용했다.
전체 검사에는 기존 개인 CRUD·공식 감사·개인 계산·관리자 회귀가 포함된다.
보존 검사에는 기존 학교/학과/교육과정/과목과 학생 프로필·수강·자격을 넣었으며
새 학생 테이블이 비어 있음을 확인한 합성 DB에서만 migration을 왕복 적용했다.

검증한 학생 동작:

- 주전공·추가 전공, 공통 문장 중복 제거, 전공별 서로 다른 개정 선택과 개정 안내
- O/X·미확인 초기화·타인 접근 거부·version 충돌·동일 요청 결과 재사용
- 기준 전환 후 동일 항목만 응답 유지, 바뀐 항목 재확인, 이전 적용본 조회, 철회 저장 차단
- 인증 기록 연결이 O를 자동 선택하지 않음, 본인 기록만 연결, 수정/삭제 뒤 재확인
- 다단 학점표·정확한 소수·인정학점 상한·0/빈칸/해당 없음·참조 소계
- 재수강 산입 기록 선택, 전공 간 중복 인정 확인 필요, 불확실한 참고 금액 분리
- 쓰기 응답 유실 후 동일 요청 재시도, 성공 뒤 재조회 실패에는 쓰기를 반복하지 않음
- 등록 학교 학생은 새 기본 화면, 기존 감사·개인 계산·이력 및 미등록 학교의 개인 흐름 유지

1440×1100 데스크톱 Flutter 렌더로 적용 전 본문·다단 표, 한 줄 O/X,
인증 요건, 추가 전공 모달, 학점 진행 상황을 확인했다. 캡처 재생성:

```powershell
flutter test test/student_academic_integration_test.dart --dart-define=STUDENT_ACADEMIC_CAPTURE=true
```

캡처와 실행 로그는 worktree의 output/student-academic 및 output/student-*.log에 두고
Git에 넣지 않는다. 렌더는 합성 API gateway를 사용하며 실제 DB 검증과 구분한다.
배포 서버에 연결한 브라우저/네이티브 종단 실기, 운영 DB 적용·배포·제품 원격 push/PR은
수행하지 않았다. 좁은 화면 신규 수동 검증은 기존 사용자 보류를 유지한다.
