# DB 백업과 격리된 복구 검증

이어진이 서버에서 사용하는 호스트 도구다. 기존 Python/Psycopg와 Docker를 사용하며
새 서비스·스토리지 공급자·인증 공급자를 도입하지 않는다. 공개 API와 독립적으로 실행한다.
`main` PR을 만들거나 프로덕트 애플리케이션을 배포하지 않아도 백업을 확인할 수 있다.

## 백업

`backend/`에서 실행한다. 각 환경의 Compose DB와 루프백 포트가 실행 중이어야 한다.

```bash
uv run --frozen python -m app.operations.db_backups backup --environment local
uv run --frozen python -m app.operations.db_backups backup --environment staging
uv run --frozen python -m app.operations.db_backups backup --environment production
```

환경별 `.env`, `.env.staging`, `.env.production`을 읽는다. 쉘의 DB 환경변수로 다른 환경에
접속하지 않도록 설정 원점을 제한하고, 프로젝트 라벨·루프백 포트·DB/사용자 이름을 실제
컨테이너와 대조한다. 외부 `DATABASE_URL` DB나 다른 프로젝트의 DB는 지원하지 않는다.

원본은 **REPEATABLE READ · READ ONLY** 트랜잭션이다. `pg_export_snapshot()`의
스냅샷을 `pg_dump --snapshot`과 공유해 백업 중 쓰기가 있어도 덤프와 검증용 행 지문이
동일한 시점의 데이터를 사용한다. 원본 DB의 스키마·자료·권한을 변경하지 않는다.

결과는 저장소 루트의 `backups/시각-식별자/`에 저장한다.

| 파일 | 내용 |
|---|---|
| `database.dump` | PostgreSQL 17 custom-format DB 아카이브 |
| `manifest.json` | 환경·시각·식별자·실행 시 저장소 HEAD와 수정 여부, 이미지 digest, 파일 SHA-256·크기, 검증 목록 |
| `verification-*.json` | 성공한 임시 DB 복원 검증의 시각·덤프 해시·검증 방식 |

디렉터리는 700, 파일은 600이며 `backups/`와 `*.dump`는 Git 및 백엔드 Docker 컨텍스트에서
제외한다. 덤프에는 DB 자료가 포함되므로 팀 PR·앱 ZIP·공용 문서로 복사하지 않는다.
실패한 백업은 manifest 없이 남을 수 있으며 완료된 백업으로 취급하지 않는다.

## 복구 검증

백업 명령이 출력한 디렉터리를 지정한다.

```bash
uv run --frozen python -m app.operations.db_backups verify ../backups/시각-식별자
```

검증은 개인 권한·심볼릭 링크·아카이브 경로·해시·크기와 pgvector 이미지 digest를 먼저
확인한다. 직접 생성한 신뢰할 백업을 대상으로 사용한다.

이후 새 이름·새 임시 볼륨·임시 비밀번호·랜덤 루프백 포트의 PostgreSQL 컨테이너에
`pg_restore --single-transaction --exit-on-error --no-owner --no-acl`로 복원한다.
사용자가 기존 DB 주소나 컨테이너를 복원 대상으로 지정하는 옵션은 없다.

복원된 테이블 열·타입·NULL/기본값, 인덱스·제약조건·확장 버전, 행 수와 순서 무관한
행 내용 지문(MD5)을 스냅샷 목록과 비교한다. 아카이브 자체는 SHA-256으로 검사한다.
세션의 검색 경로·시간대·날짜 표현을 통일해 같은 값이 다르게 비교되지 않게 한다.
PostgreSQL 복원 시 달라질 수 있는 varchar 문자열 리터럴 배열의 text 형변환 표기만
동등하게 정규화한다. 허용 값·연산자·다른 타입, 나머지 스키마와 데이터 지문은 그대로 비교한다.
nullable 열의 `IS NULL OR ...` 검사는 같은 열을 확인하는 완전한 enum 제약일 때만 처리한다.
인용한 문자열 안의 SQL 모양 내용은 변환하지 않으며, 다른 조건·NULL 분기·문자열 변경은 차이로 남긴다.
검증이 성공한 경우에만 report를 쓰고, 실패해도 자신이 생성한 컨테이너·임시 볼륨은 제거한다.
원본·Staging·Production DB에 덮어쓰기 복원을 하지 않는다.

이 도구는 DB 하나의 논리 백업이다. 클러스터 역할·비밀번호·원 소유자·권한, 서버 설정,
외부 업로드 파일을 복원하는 도구가 아니다. 운영 장애의 실제 DB 교체는 별도 작업으로
백업 선택·대상 확인·애플리케이션 정지·권한 복구·마이그레이션 확인을 준비해야 한다.
현재 보관·외부 복제·자동 스케줄은 설정하지 않았으며 기존 백업을 자동 삭제하지 않는다.

## 합성 데이터 검증과 CI

```bash
uv run --frozen pytest tests/test_db_backups.py -q
uv run --frozen python -m scripts.smoke_db_backup
```

Smoke는 원본도 임시 DB로 만들어 한글·JSON·소수·벡터·외래키·인덱스를 넣는다.
학교 발급 자료와 검토 이벤트 테이블을 포함한 실제 마이그레이션도 복원하며, BYTEA 원본의
0x00/0xff 바이트를 포함한 합성 파일이 행 내용 지문과 함께 복원되는지도 검사한다.
스냅샷을 내보낸 뒤 덤프 실행 전에 별도 연결에서 데이터를 변경해, 동시 쓰기가 백업의
시점과 섞이지 않는지 검증한다. 손상된 아카이브, 해시는 맞지만 읽을 수 없는 아카이브의
복원 실패 및 임시 자원 정리도 확인한다. 실제 학생 자료는 사용하지 않는다.
백엔드 CI와 앱 다운로드 워크플로의 검증 단계에서 같은 Smoke를 실행한다.

구현 근거: [PostgreSQL 17 pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html),
[pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html),
[스냅샷 내보내기](https://www.postgresql.org/docs/17/functions-admin.html).
