# 백엔드 개발환경

Python 3.12, FastAPI, SQLAlchemy, Psycopg, Alembic, PostgreSQL 17과 pgvector를
사용한다. Docker 기반 이미지는 Python 3.12.14와 pgvector 0.8.6을 포함하며 digest로
잠근다. Python 의존성은 `uv.lock`에 잠그며 Docker와 호스트가 같은 잠금 파일을
사용한다. 이메일·비밀번호/서버 세션 인증과 역할·학교 전체 범위를 구현했다.
외부 인증/SSO, LLM 및 클라우드 공급자는 미정이다. [인증 API](../docs/api/authentication.md)를 따른다.

## Docker로 시작

저장소 루트에서 실행한다. Docker Engine/Desktop과 Compose v2 이상이 필요하다.

```bash
cp .env.example .env
# .env의 POSTGRES_PASSWORD를 로컬 개발용 비밀번호로 변경
docker compose up --build -d
docker compose ps -a
```

PowerShell에서는 첫 명령을 `Copy-Item .env.example .env`로 실행한다.

DB가 준비되면 `migrate` 서비스가 `alembic upgrade head`를 실행한 뒤 API가
시작한다. `migrate`의 `Exited (0)` 상태는 정상이다.

| 대상 | 주소 / 설명 |
|---|---|
| Swagger UI | http://localhost:8010/api/v1/docs |
| OpenAPI JSON | http://localhost:8010/api/v1/openapi.json |
| 프로세스 상태 | http://localhost:8010/api/v1/health |
| DB 준비 상태 | http://localhost:8010/api/v1/health/ready |
| PostgreSQL | `127.0.0.1:5433`, DB/사용자 `unipath`, 비밀번호는 `.env` |

`/health`는 README의 Smoke Test를 위한 별칭이다. 준비 상태 API는 pgvector 확장과
Alembic revision을 확인하며 연결 실패나 초기화 누락에 HTTP 503 공통 오류를 반환한다.
공개 API는 `/api/v1` 아래에 둔다. 상태 확인 API와 학교 질의
`POST /api/v1/assistant/queries`가 구현되어 있다. 요청·응답은
[`../docs/api/assistant.md`](../docs/api/assistant.md)를 따른다.

포트 충돌 시 `.env`의 `API_PORT`와 `POSTGRES_PORT`를 바꾼다. 기본 공개 주소는
로컬 루프백이다. 도메인을 사용하는 Staging·배포 채널은
[`docs/releases.md`](../docs/releases.md)의 환경별 Compose 프로젝트·DB·HTTPS 게이트웨이
설정을 따른다. 팀 통합·앱 빌드·릴리스·서버 배포 담당은 이어진이다.

```bash
# Python 소스 변경 시 자동 재시작
docker compose -f compose.yaml -f compose.dev.yaml up --build -d
# 기본 실행으로 돌아가기
docker compose up -d
# 로그와 종료 (DB 데이터 유지)
docker compose logs -f api
docker compose down
```

`postgres_data` 볼륨이 DB 데이터를 보존한다. `.env`의 DB 비밀번호를 변경해도
기존 볼륨의 DB 계정 비밀번호가 자동으로 바뀌지는 않는다. 초기화가 필요할 때에는
데이터를 확인하고 백업한 뒤 별도로 볼륨 삭제 여부를 결정한다.

## 호스트 Python으로 개발

[uv 설치 안내](https://docs.astral.sh/uv/getting-started/installation/)에 따라
uv 0.12.21을 설치한다. Python 3.12가 없으면 `uv python install 3.12`로 설치한다.

```bash
# 저장소 루트: DB 기동과 마이그레이션
docker compose up --build -d db migrate
cd backend
uv sync --frozen
uv run --frozen uvicorn app.main:app --host 127.0.0.1 --port 8011 --reload --no-access-log
```

이미 Docker API가 8010에서 실행 중일 수 있어 호스트 API 예시는 8011을 사용한다.
호스트 설정은 저장소 루트 `.env`를 읽는다. Docker 내부에서는 DB 주소를
`db:5432`로 덮어쓰므로 호스트 포트와 독립적으로 동작한다.
Flutter Web은 예를 들어 `flutter run -d chrome --web-port 3000`으로 고정 포트를
사용한다. 다른 포트를 쓰면 `.env`의 `CORS_ORIGINS` JSON 배열도 갱신한다.
프론트엔드 학교 질의는 `POST /api/v1/assistant/queries`와 연결한다.
인증은 실제 서버와 연결하고 개인 기록은 계정별 기기 저장, 공식 졸업 판정은 미연결이다. Web 실행 주소는
`http://localhost:3000`, 빌드 설정 `API_BASE_URL`은 실제 API 주소에 맞춘다.

## RAG 팀 모듈과 학교 질의 API

RAG 팀의 PDF 추출·학교별 BM25 검색 모듈을 공통 백엔드에 연결했다.
`uv sync --frozen`은 PDF 추출·기존 RAG 테스트 의존성도 설치한다. 추출 의존성은
별도 `ingestion` 그룹에 있으며 일반 API 런타임에는 설치하지 않는다.

```bash
# backend/에서 실행: 검토용 청크 생성과 개발용 평가
uv run --frozen python -m app.rag.ingestion
uv run --frozen python -m app.rag.evals
```

호스트 API에 청크를 연결하려면 루트 `.env`에
`SCHOOL_RAG_CORPUS_PATH=backend/app/rag/output/chunks.jsonl`을 설정하고 API를 재시작한다.
설정이 없으면 빈 인덱스로 시작하고, 문맥이 충분한 질의에 `insufficient_evidence`를
반환한다. 경로를 명시했는데 파일이 없거나 내용 검증이 실패하면 시작을 거부한다.
인덱스는 수명주기당 한 번만 읽으므로 청크 변경 후 재시작이 필요하다.

Docker는 저장소 루트에서 다음과 같이 실행한다.

```bash
docker compose -f compose.yaml -f compose.rag.yaml up --build -d
docker compose -f compose.yaml -f compose.rag.yaml ps -a
python3 backend/scripts/smoke_api.py
```

`rag-ingest`는 선택 의존성과 저장소 PDF를 포함하는 별도 이미지로 추출한 뒤 종료한다.
산출물은 `rag_data` 볼륨에 남고 API는 읽기 전용으로 연결한다. `Exited (0)`은 정상이다.
입력 문서 변경 후에는 `rag-ingest`를 다시 실행하고 API를 재시작한다.
기본 `compose.yaml`만 실행하면 파일 코퍼스를 연결하지 않는다.

Smoke Test는 DB 준비, OpenAPI, 근거 부족·문맥 부족·졸업 판정 분리와 검증 오류를
확인한다. 포트를 바꿨다면 `--base-url http://127.0.0.1:변경한포트`를 지정한다.
PowerShell에서 Python 실행 명령이 `python`이면 `python3` 대신 사용한다.

현재 PDF는 모두 미승인이며 공식 출처 URL·적용 범위가 확인되지 않았다. HTTP API에는
preview 옵션이 없어 이 자료로 답변이나 인용을 만들지 않는다. 실제 LLM·임베딩 공급자는
연결하지 않았다. 파일의 승인 플래그는 관리자 승인 시스템이 아니므로 JSONL 코퍼스는
`APP_ENV=local`에서만 허용한다. 인증·공식 문서 승인·DB의 범위/버전/유효기간 관리가
구현되기 전에는 운영 질의 시스템으로 배포하지 않는다.

동기 RAG 함수는 FastAPI 작업 스레드에서 실행하며 질문·답변·후보를 저장하거나 로그에
기록하지 않는다. 졸업 가능 여부 질문은 `rule_engine_required`와 `graduation_audit`
추가 정보 요구를 반환한다. 실제 졸업감사 API는 아직 없다.

## 검증과 마이그레이션

```bash
# backend/에서 실행: DB 없이 검증
uv run --frozen ruff check .
uv run --frozen ruff format --check .
uv run --frozen pytest -q

# DB 모델을 추가한 후 마이그레이션 생성·검토·적용
uv run --frozen alembic revision --autogenerate -m "describe schema change"
uv run --frozen alembic upgrade head
uv run --frozen alembic check
```

새 모델은 `app/models/`에 두고 `app/models/__init__.py`에서 import해 Alembic의
metadata에 포함한다. 생성된 마이그레이션은 직접 검토하며 공유된 파일을 수정하지 않는다.
첫 마이그레이션은 vector 확장, `0002_identity_sessions`는 계정·세션·역할·학교 범위 관련
6개 테이블을 생성한다. 임베딩 차원과 공식 학사/졸업 규칙 물리 스키마는 후속이다.
준비 상태 API는 현재 migration head까지 적용되어야 200을 반환한다.
첫 마이그레이션의 downgrade는 다른 벡터 테이블을 보호하기 위해 확장을 유지한다.

저장소 루트에서 Docker와 실제 PostgreSQL/pgvector 검증을 실행한다.

```bash
docker compose --profile test run --build --rm test
```

호스트에서도 `RUN_DB_TESTS=1 uv run --frozen pytest -q`로 DB 테스트를 포함할 수 있다.
PowerShell에서는 `$env:RUN_DB_TESTS='1'`을 설정한 뒤 테스트 명령을 실행한다.
통합 테스트는 합성 벡터를 임시 테이블에 넣어 최근접 검색을 확인하고 종료 시 제거한다.
인증 통합 테스트는 매번 별도 임시 스키마에 합성 계정을 만들고 종료 시 제거한다. 기본/공유
관리자 계정은 시드하지 않는다. 실제 학생 데이터는 테스트하지 않는다. CI는 린트·단위 테스트,
Docker 빌드·마이그레이션·실제 DB 통합 테스트·API Smoke 및 합성 DB 복구 검증을 실행한다.
앱 다운로드 워크플로도 같은 백엔드·복구 검증을 거쳐 Web·Windows를 빌드한다.

## 혼자 진행할 수 있는 판정·운영 도구

```bash
# backend/에서 실행: DB·LLM 없이 개인 기준 코어 계산과 테스트
uv run --frozen python -m app.rules --demo
uv run --frozen pytest tests/test_rules.py -q
# 실제 학교 자료 없이 임시 DB의 백업·복구·동시 변경·손상 검사
uv run --frozen python -m scripts.smoke_db_backup
# 기존 Local DB 읽기 전용 백업 (Docker DB 실행 필요)
uv run --frozen python -m app.operations.db_backups backup --environment local
# 위 명령이 출력한 백업 디렉터리만 새 임시 DB에서 검증
uv run --frozen python -m app.operations.db_backups verify ../backups/시각-식별자
```

코어는 공식 규칙 계산과 개인 기준 계산을 구분한다. 개인 자료 DB와 개인 계산 API·이력은
연결했고 공식 졸업감사 API·DB는 후속이다. 실제 학교 기준을 내장하거나 RAG/LLM이 판정을 대신하지 않는다.
[판정 코어 계약](../docs/rule-engine.md)과 [DB 백업·복구 검증](../docs/database-backups.md)을
따른다. 백업 파일은 비공개 `backups/`에 보관하며 Git·Docker 컨텍스트에서 제외한다.

## 코드 구조와 설정

- `app/api/`: 라우터 및 의존성
- `app/schemas/`: Pydantic 요청·응답과 공통 오류
- `app/models/`: SQLAlchemy 모델과 공통 metadata
- `app/services/`: 서비스, Personalization 및 Job Analysis 경계
- `app/rules/`: 결정론적인 Academic Rule Engine 구현 위치
- `app/operations/`: 호스트용 DB 백업·격리 복구 검증 도구
- `app/rag/school/`, `app/rag/career_certificate/`: 공식 근거 검색 구현 위치
- `app/core/`: 환경변수, DB 연결, request_id와 오류 처리
- `migrations/`: Alembic 마이그레이션
- `tests/`: API·설정·PostgreSQL/pgvector 검증

인증·역할·학교 전체 범위와 졸업 판정 코어는 구현했다. 학사 CRUD·개인 자료 API/DB와 학생용 카탈로그를 구현했고 공식 졸업감사 API는 후속이다. 학교 RAG는 팀의
오프라인 모듈과 HTTP 어댑터를 연결했으며 공식 문서 승인·운영 DB·실제 생성기는
후속 구현 대상이다. 신규 패키지는 용도에 맞춰 최소한으로 추가한다.

| 의존성 | 용도 |
|---|---|
| FastAPI / Uvicorn | API·OpenAPI / ASGI 서버 |
| SQLAlchemy / Psycopg | DB 모델·세션 / PostgreSQL 드라이버 |
| Alembic | DB 마이그레이션 |
| pydantic-settings | 환경변수와 `.env` 설정 |
| pytest / httpx2 | 자동 테스트 / ASGI 테스트 클라이언트 |
| Ruff | 린트와 포맷 |
| pdfplumber (ingestion 그룹) | 팀의 PDF 텍스트·표 추출과 RAG 테스트 |

`.env.example`이 환경변수 목록의 기준이다. `APP_ENV`는 `local`, `staging`,
`production` 중 하나이며 각 환경의 DB와 비밀값을 분리한다. `DATABASE_URL`은
호스트 실행/외부 배포에서 사용할 선택적 전체 연결 문자열이다. 로컬 Compose는
`POSTGRES_*`를 사용하며 외부 DB 연결 문자열을 가져오지 않는다.
Psycopg 연결 문자열은 `postgresql+psycopg://`로 시작해야 한다.
`APP_ENV`는 세션 쿠키의 Secure·이름 정책에 반영된다. 역할·소유권은 환경 이름이 아닌
실제 서버 계정·세션·범위로 검증한다.

오류는 `error.code`, `message`, `field_errors`, UUID `request_id`로 반환한다.
`X-Request-ID`로 UUID를 보내면 같은 값을 응답에 포함하고, 없거나 잘못된 형식이면
새 UUID를 만든다. 검증 오류에 원본 입력값을 포함하지 않으며 DB 오류나 내부 예외의
상세 내용도 응답에 노출하지 않는다. 기본 서버 실행에서는 URL 쿼리의 개인정보가
로그에 남지 않도록 접근 로그를 끈다.

구성 참고: [FastAPI Docker 안내](https://fastapi.tiangolo.com/deployment/docker/),
[pgvector 공식 Docker 이미지](https://github.com/pgvector/pgvector#docker),
[Starlette TestClient](https://www.starlette.io/testclient/).

## 관리자 학사 API

`0003_academic_catalog`가 학사 메타데이터 7개 테이블을 추가한다. 당시 총 13개 테이블이며
학교·학과·교육과정·과목·연결, 검토 기준/문서 버전·관리 이력을 실제 관리자 화면과 연결한다.
조건 설명은 실행 가능한 Rule Engine 규칙이 아니며 문서 적용은 RAG 원문 승인이 아니다.
[학사 계약](../docs/api/academic.md)을 따른다. 학생 개인 자료 API는 아래와 같으며 공식 졸업감사는 후속이다.

## 학생 개인 자료·카탈로그 API

`0004_personal_records`는 개인 프로필·11개 개인 컬렉션·순서 있는 초안 참조·생성 재시도 영수증의
15개 테이블을 추가한다. `0005_personal_evaluations`는 개인 계산 이력을 추가해
현재 물리 테이블은 총 29개다(Alembic 테이블 제외).
`/api/v1/me/*`는 세션 소유자만 읽고 변경하며 관리자 역할로 다른 학생 기록을 조회하지 못한다.
`/api/v1/catalog/*`는 로그인한 학생에게 적용본과 등록된 학교·과정·과목 메타데이터만 조회한다.
[개인 자료 계약](../docs/api/personal.md), [학생 카탈로그](../docs/api/student-catalog.md)를 따른다.
비밀번호 변경은 `/auth/change-password`에서 기존 비밀번호 검증·전체 세션 폐기를 수행한다.

프론트 전송 DTO는 아래 명령으로 Pydantic에서 재생성한다. 기존 개인 화면은 계속 로컬 저장이다.

```bash
uv run --frozen python ../scripts/export_student_contracts.py
# 저장소 루트에서 실행
dart format frontend/lib/features/api/student_api_models.dart
```

## 개인 기준 계산 API

`POST /api/v1/me/personal-evaluations`는 본인 개인 교육과정의 활성 규칙과 저장된 개인
기록을 명시적인 다섯 종류 조건으로 계산한다. 조건 설명/직접 적은 현재 값을 실행하지 않으며
누락 조건은 확인 필요로 유지한다. 결과는 항상 개인 기준 표시를 포함한다.
결과·조건·최소 입력 snapshot을 불변 이력으로 저장하고 목록/상세/본인 삭제를 제공한다.
소유권·버전·재시도를 검증하고 원본이 바뀌어도 과거 결과는 유지한다.
[계산 계약](../docs/api/personal-evaluations.md)을 따른다. Flutter typed 전송 adapter는
`personal_evaluation_api.dart`이며 현재 개인 화면은 로컬 저장·계산 API 미연결이다.
