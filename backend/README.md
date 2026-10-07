# 백엔드 개발환경

Python 3.12, FastAPI, SQLAlchemy, Psycopg, Alembic, PostgreSQL 17과 pgvector를
사용한다. Docker 기반 이미지는 Python 3.12.14와 pgvector 0.8.6을 포함하며 digest로
잠근다. Python 의존성은 `uv.lock`에 잠그며 Docker와 호스트가 같은 잠금 파일을
사용한다. 인증 방식, LLM 및 클라우드 공급자는 아직 결정하지 않았다.

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
로컬 루프백이다. 다른 PC에서 접근하는 Staging 구성은 별도로 설정한다.

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
프론트엔드는 현재 목업이며 실제 API 연동은 다음 작업이다.

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
첫 마이그레이션은 `vector` 확장만 활성화한다. 도메인 테이블, 임베딩 차원과
공식 졸업 규칙의 물리 스키마는 팀 합의 후 새 마이그레이션으로 구현한다.
첫 마이그레이션의 downgrade는 다른 벡터 테이블을 보호하기 위해 확장을 유지한다.

저장소 루트에서 Docker와 실제 PostgreSQL/pgvector 검증을 실행한다.

```bash
docker compose --profile test run --build --rm test
```

호스트에서도 `RUN_DB_TESTS=1 uv run --frozen pytest -q`로 DB 테스트를 포함할 수 있다.
PowerShell에서는 `$env:RUN_DB_TESTS='1'`을 설정한 뒤 테스트 명령을 실행한다.
통합 테스트는 합성 벡터를 임시 테이블에 넣어 최근접 검색을 확인하고 종료 시 제거한다.
현재 도메인 테이블이 없으므로 학생 시드 데이터는 넣지 않는다. 실제 학생 데이터는
테스트에 사용하지 않는다. GitHub Actions 템플릿은 린트, 단위 테스트, Docker 빌드,
마이그레이션, 실제 DB 통합 테스트와 API Smoke Test를 실행하도록 구성했다.
현재 자동 CI는 활성화되지 않았다. 저장소 생성용 OAuth 토큰의 `workflow` 권한이
없어 활성 워크플로 파일을 푸시할 수 없으므로
`../.github/workflow-templates/backend-ci.yaml`에 보관한다. 권한을 가진 팀원이
`.github/workflows/backend-ci.yaml`로 옮겨 푸시해 활성화한다.

## 코드 구조와 설정

- `app/api/`: 라우터 및 의존성
- `app/schemas/`: Pydantic 요청·응답과 공통 오류
- `app/models/`: SQLAlchemy 모델과 공통 metadata
- `app/services/`: 서비스, Personalization 및 Job Analysis 경계
- `app/rules/`: 결정론적인 Academic Rule Engine 구현 위치
- `app/rag/school/`, `app/rag/career_certificate/`: 공식 근거 검색 구현 위치
- `app/core/`: 환경변수, DB 연결, request_id와 오류 처리
- `migrations/`: Alembic 마이그레이션
- `tests/`: API·설정·PostgreSQL/pgvector 검증

졸업 판정, 인증과 CRUD 패키지는 아직 모듈 경계만 마련했다. 학교 RAG는 팀의
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
현재 `APP_ENV` 자체가 인증이나 배포 정책을 구현하지는 않는다.

오류는 `error.code`, `message`, `field_errors`, UUID `request_id`로 반환한다.
`X-Request-ID`로 UUID를 보내면 같은 값을 응답에 포함하고, 없거나 잘못된 형식이면
새 UUID를 만든다. 검증 오류에 원본 입력값을 포함하지 않으며 DB 오류나 내부 예외의
상세 내용도 응답에 노출하지 않는다. 기본 서버 실행에서는 URL 쿼리의 개인정보가
로그에 남지 않도록 접근 로그를 끈다.

구성 참고: [FastAPI Docker 안내](https://fastapi.tiangolo.com/deployment/docker/),
[pgvector 공식 Docker 이미지](https://github.com/pgvector/pgvector#docker),
[Starlette TestClient](https://www.starlette.io/testclient/).
