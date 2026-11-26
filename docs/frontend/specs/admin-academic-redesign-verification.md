# 관리자 학사 재설계 검증 (2026-11-08)

범위: 관리자 학교·학과 / 교육과정·과목 / 졸업요건과 그 DB·API.
학생 모델·API·O/X·개인 기록 연결은 이번 변경에 포함하지 않았다.

## 검증 결과

| 검사 | 결과 |
| --- | --- |
| Flutter 전체 테스트 | 845 통과, 기존 13 생략 |
| 마지막 오류 표시·재조회 수정 후 관련 검사 | 24 통과 |
| Flutter analyze | No issues found |
| Web·Windows release build | 마지막 오류 표시·재조회 수정 후 재빌드 성공 |
| Backend 전체 검사 및 환경 실패 재검사 | 총 560 통과, 기존 3 생략 |
| Ruff | 전체 통과 |
| Alembic check | 0017 head와 모델 차이 없음 |
| 생성 OpenAPI | 실행 앱과 동일, 기존 path/schema 의미 보존, 총 195 paths |
| 기존 행 보존 | 격리 DB에서 0014↔0017 왕복 후 50개 기존 테이블의 5개 합성 행이 완전 동일 |

백엔드 최초 실행은 Windows cp949 기본 인코딩으로 일부 기존 한글 fixture 검사가
실패했다. `PYTHONUTF8=1`로 실패 항목만 재실행했다. 기존 공유 가상환경에는
BeautifulSoup이 없어 작업 전용 tmp/test-python에 uv.lock과 같은 버전을 설치한 뒤
남은 6개 검사도 통과했다. 제품 의존성·공유 가상환경은 변경하지 않았다.

## 확인한 동작

- 실제 PostgreSQL에서 학교 권한·교차 학교 FK·잘못된 분류·version 충돌을 거부한다.
- 동일 client_id 재시도는 과목·연결·개정이 중복 생성되지 않고 같은 결과를 반환한다.
- 원본 과목 하나를 여러 교육과정의 다른 분류·필수 여부·인정학점으로 연결한다.
- 기존 교육과정·과목 연결·요건을 가져와도 원본을 보존한다. 게시본 복사와 안정 ID를 보존한다.
- 한 줄 문장 순서·중복 문장의 별개 ID, 인증 하위 영역을 포함한 택N,
  학점표 3단 헤더·정확한 소수·0/빈칸/해당 없음·순환 거부를 검사했다.
- 위젯에서 세 요건의 저장·응답 유실·동일 요청 재시도를 검사했다.

데스크톱 1440×1100의 실제 Flutter 위젯 렌더로 한 줄 요건·빈 인증 요건·빈 학점표·
3단 학점표 미리보기를 확인했다. 재생성 명령:

```powershell
flutter test test/admin_academic_requirements_test.dart --dart-define=ACADEMIC_CAPTURE=true
```

이미지·실행 로그는 작업 공간 output/admin-academic-redesign에 생성하며 Git에 넣지 않는다.
렌더는 합성 API gateway를 사용한다. 실제 배포 서버와 브라우저/네이티브 앱을 연결한
종단 실기 검증, 운영 DB migration·배포·제품 원격 push/PR은 수행하지 않았다.
좁은 화면 신규 수동 검증은 사용자 보류를 유지한다.
