# UniversityPath AI

대학 공식 학사정보, 사용자의 학사·활동 데이터, 진로·자격증 및 채용공고를 연결하여 대학생활과 취업 준비를 지원하는 Flutter Web 기반 애플리케이션입니다. Windows 애플리케이션은 3차 MVP 확장 범위입니다.

이 문서는 개발을 시작하기 전에 팀이 공통으로 합의해야 할 MVP 범위, 시스템 구조, 역할, API, 데이터, 개발환경 및 협업 기준을 정리합니다.

코딩 에이전트가 따라야 할 저장소 규칙은 [`AGENTS.md`](AGENTS.md)에 별도로 정의합니다. README는 사람을 위한 프로젝트 설명과 합의 사항을, AGENTS.md는 구현 중 항상 적용할 규칙을 담당합니다.

## 1. MVP 범위

### 필수 기능

- 사용자 학사정보 입력 및 관리
- 일반 사용자용 공용 기능 및 학교 데이터 미등록 상태의 직접 입력 지원
- 학교 관리자용 학교·학과·교육과정·공식 규정 데이터 관리
- 공식 규정 기반 졸업요건 충족 여부 판정
- 학교·자격증 공식 문서 기반 RAG 질의응답
- 프로젝트, 공모전, 봉사, 자격증 등 활동·경험 관리

### 2차 MVP 기능

- 진로 정보 RAG 질의응답
- 채용공고 요구사항 추출 및 개인 경험 비교

### 3차 MVP 기능

- 다수 채용공고의 비교·우선순위화
- 지원 이력 관리와 피드백 기반 추천
- Windows 애플리케이션

### 후순위 기능

- 모바일 애플리케이션
- 알림 및 일정 연동
- 다른 대학으로의 확장
- Agent/MCP 기반 외부 서비스 연동
- 고급 추천 및 자동 포트폴리오 생성

MVP 개발 중 새로운 기능이 제안되면 필수 기능 완성에 미치는 영향을 먼저 검토합니다.

### 검토 중인 외부 서비스 연계 후보

- **디지털서비스 개방 수시신청**: 향후 사용자가 UniversityPath 안에서 공공 봉사활동을 찾아 신청하는 흐름을 검토할 때 참고할 후보다. 초기에는 1365 자원봉사포털을 새 탭으로 여는 외부 링크만 제공하고, 신청 정보·계정·봉사 실적을 UniversityPath와 교환하지 않는다. 현재 공공서비스 직접 연계는 서비스 이용을 희망하는 기업·단체·법인이 신청서류를 갖춰 문서24로 수시신청하는 절차이며, 실제 연계·인증·개인정보 처리 방식은 확정하지 않았다. 도입 검토 시 서비스별 제공 범위, 심의 결과, CI값 기반 연계 요건, 보안대책 및 관련 법령을 확인한다. [공식 수시신청 안내](https://www.openservice.go.kr/onDemandApp)

## 2. 시스템 구조

```text
Flutter Web (1차 MVP) + Windows 애플리케이션 (3차 MVP)
    ↓ REST API
FastAPI
    ├─ Academic Rule Engine
    ├─ School Knowledge RAG
    ├─ Career / Certificate RAG (자격증 1차, 진로 2차)
    ├─ Personalization Module
    └─ Job Analysis Module (2차 MVP)
    ↓
PostgreSQL + pgvector
    ↓
External LLM API
```

초기에는 마이크로서비스로 분리하지 않고 하나의 FastAPI 애플리케이션 안에서 기능별 모듈을 분리합니다.

### 핵심 처리 원칙

```text
RAG         공식 규정과 답변 근거 검색
Rule Engine 졸업요건 충족·미충족 계산
LLM         검색 근거와 판정 결과를 자연어로 설명
```

졸업 가능 여부와 같은 확정적 판정은 LLM이 아닌 Rule Engine이 담당합니다. LLM은 판정 결과를 변경하지 않으며 설명만 생성합니다.

학교 시스템은 학사·졸업·승인 활동 데이터의 기준 원본이다. UniversityPath는 학교 시스템을 대신해 수강, 봉사 승인, 사전교육 또는 소감문을 처리·재판정하지 않는다. 학교의 확정값을 바탕으로 부족한 항목을 보여 주고, 외부 활동 탐색·계획·개인 보조 기록을 돕는다.

### 사용자·학교 관리자 운영 모델

Flutter Web은 역할에 따라 학생 사용자 화면과 학교 관리자 화면을 분리합니다. 두 화면은
같은 애플리케이션과 `/api/v1` API를 사용하며, 관리자 기능은 역할 기반 권한으로 보호합니다.

- 일반 사용자는 등록된 학교·학과 데이터가 없거나 지원하지 않는 학교·학과에 속해도
  자격증, 진로, 활동·경험, 채용 분석 등 공용 모듈을 사용할 수 있다. 학사정보와 과목도
  직접 입력할 수 있다.
- 학교·학과·교육과정에 적용 가능한 공식 규정 데이터가 등록된 경우에만 Rule Engine이
  공식 졸업감사를 실행한다. 데이터가 없으면 졸업 가능 여부를 추정하지 않으며,
  `not_applicable` 또는 필요한 정보 안내를 반환한다.
- 학교 관리자는 자신에게 권한이 부여된 학교 범위의 학과, 교육과정, 과목, 졸업요건 및
  공식 문서의 적용 범위·버전을 등록하고 관리한다. 실제 학교 관리자 검증 방식은 구현
  전에 별도로 합의하며, 특정 인증 공급자를 지금 확정하지 않는다.
- 사용자의 이수기록·자격증·경험 같은 개인 데이터는 학교 데이터 등록 후에도 유지한다.
  사용자가 임시로 입력한 요건은 삭제하지 않고 참고 이력으로 보존하며, 공식 데이터가
  적용 가능해지면 졸업감사와 학교 RAG에는 공식 데이터만 우선 적용한다.

이 정책으로 학교 데이터의 유무가 서비스 접근을 막지 않으면서도, 졸업요건 판정은
공식 근거가 있을 때만 결정론적으로 수행한다.

## 3. 역할 분담

실제 담당자 이름은 팀 합의 후 작성합니다.

| 역할 | 담당자 | 소유 영역 | 주요 업무 |
|---|---|---|---|
| 백엔드·통합 | 미정 | FastAPI, PostgreSQL, Rule Engine, 인증·배포 | API 및 DB 설계, 사용자 데이터 관리, 졸업요건 판정, 인증, 모듈 통합, Docker 기반 배포 |
| AI·RAG·데이터 | 미정 | 문서 처리, 검색, LLM, 데이터 파이프라인 | 공식 문서 수집·정제, 청킹, 메타데이터, 임베딩, RAG, 채용공고 정보 추출, 검색 품질 평가 |
| 프론트엔드·UX·QA | 미정 | Flutter Web(1차)·Windows 애플리케이션(3차), 화면·상태 관리·사용성 검증 | 학사 대시보드, AI 채팅, 활동·포트폴리오, 채용공고 비교 UI, API 연동, E2E 테스트, 데모 시나리오 및 사용자 흐름 검증 |

### 역할 운영 원칙

- 초기 MVP의 기본 접점은 Flutter Web으로 제공한다. Windows 애플리케이션은 웹 핵심 흐름이 안정된 뒤 같은 Flutter 코드베이스에서 3차 MVP 대상으로 확장한다.
- 프론트엔드 담당은 단순 화면 구현에 한정하지 않고, 화면 설계·API 통합·E2E 테스트·사용성 및 데모 흐름 검증을 함께 책임진다.
- 백엔드 담당은 졸업요건의 결정론적 판정을 담당한다. RAG 또는 LLM이 판정 결과를 대신 결정하지 않는다.
- AI·RAG·데이터 담당은 검색 기능뿐 아니라 공식 문서 수집·정제, 청킹, 출처 메타데이터, 검색 품질 평가를 책임진다.
- 배포와 통합은 백엔드 담당이 주도하되, 각 담당자는 자신의 모듈이 Docker 공통 환경에서 동작하도록 검증한다.

### 세부 과제 수행 분담

| 단계 | 세부 과제 | 주 담당 | 협업 담당 | 완료 기준 |
|---|---|---|---|---|
| 공통 기반 | 저장소 구조, Docker 공통 개발환경, `.env.example` 정리 | 백엔드·통합 | 전원 | 각 담당자가 같은 명령으로 로컬 환경을 실행할 수 있음 |
| 공통 기반 | DB ERD, 데이터 모델, Alembic 마이그레이션 설계 | 백엔드·통합 | AI·RAG·데이터, 프론트엔드·UX·QA | `docs/database-erd.md`와 DB 모델이 일치함 |
| 공통 기반 | API 계약 및 OpenAPI 문서 확정 | 백엔드·통합 | 프론트엔드·UX·QA, AI·RAG·데이터 | 요청·응답·오류 형식이 합의되고 테스트됨 |
| 1차 MVP | 회원·역할·사용자·학사정보·이수과목·활동 데이터 API | 백엔드·통합 | 프론트엔드·UX·QA | 일반 사용자와 학교 관리자 권한, CRUD, 입력 검증, 권한·데이터 부재 오류를 확인함 |
| 1차 MVP | 학생 입력·대시보드 및 학교 관리자 데이터 관리 화면 | 프론트엔드·UX·QA | 백엔드·통합 | 역할별 화면 접근, 공용 기능, 직접 입력, 공식 데이터 등록 후 적용 흐름을 확인함 |
| 1차 MVP | 졸업요건 규칙 데이터 구조 및 Rule Engine | 백엔드·통합 | AI·RAG·데이터 | 충족·미충족·경계값·정보 누락 사례를 결정론적으로 판정함 |
| 1차 MVP | 공식 학사 규정 수집·정제·적용 범위 메타데이터 작성 | AI·RAG·데이터 | 백엔드·통합 | 문서 제목·URL·페이지·학교·학과·입학연도 범위를 보존함 |
| 1차 MVP | 문서 청킹, 임베딩, pgvector 검색 파이프라인 | AI·RAG·데이터 | 백엔드·통합 | 검색 결과에 근거 문서와 필터가 포함됨 |
| 1차 MVP | 학교·자격증 RAG 질의응답 및 근거 부족 처리 | AI·RAG·데이터 | 백엔드·통합, 프론트엔드·UX·QA | 출처를 제시하고 근거 부족 시 `insufficient_evidence`를 반환함 |
| 1차 MVP | AI 채팅·출처 표시 화면 | 프론트엔드·UX·QA | AI·RAG·데이터, 백엔드·통합 | 답변, 문서 제목·URL·페이지, 오류·로딩 상태를 표시함 |
| 통합·품질 | API 통합 테스트 및 E2E 핵심 시나리오 | 프론트엔드·UX·QA | 백엔드·통합, AI·RAG·데이터 | 학사 입력 → 졸업 판정 → 근거 질의 흐름을 검증함 |
| 통합·품질 | Rule Engine·RAG 검색 품질 테스트 | 백엔드·통합 / AI·RAG·데이터 | 프론트엔드·UX·QA | 판정 정확성, 검색 근거·출처·필터, 근거 부족 처리를 검증함 |
| 배포 | Staging 구성, Docker 이미지, 로그·환경변수·비밀값 관리 | 백엔드·통합 | 전원 | 실제 개인정보·비밀값 없이 Staging에서 공통 시나리오를 실행함 |
| 2차 MVP | 진로 RAG 및 채용공고 요구사항 추출·경험 비교 | AI·RAG·데이터 | 백엔드·통합, 프론트엔드·UX·QA | 요구사항 근거와 개인 경험 비교 결과를 제공함 |
| 2차 MVP | 채용공고 비교·결과 표시 화면 | 프론트엔드·UX·QA | AI·RAG·데이터, 백엔드·통합 | 추출 결과·비교 결과·오류 상태를 이해하기 쉽게 표시함 |
| 3차 MVP | Windows 애플리케이션 빌드·배포 검증 | 프론트엔드·UX·QA | 백엔드·통합 | Web과 같은 API로 핵심 흐름이 Windows에서 동작함 |

### 공동 결정 영역

- MVP 범위와 데모 시나리오
- 공통 데이터 모델과 DB 스키마
- API 요청·응답 계약
- 개인정보 및 보안 정책
- Staging 검증과 Production 배포 승인

### 모듈별 기본 소유권

| 모듈 | 주 담당 | 협업 영역 |
|---|---|---|
| School Knowledge Module | AI·RAG·데이터 | 백엔드 API 연동 |
| Career / Certificate Module (자격증 1차, 진로 2차) | AI·RAG·데이터 | 프론트 결과 표시 |
| Academic Rule Engine | 백엔드·통합 | AI의 규정 데이터 제공 |
| Job Analysis Module (2차 MVP) | AI·RAG·데이터 | 백엔드의 경험 비교 및 저장 |
| Personalization Module | 백엔드·통합 | 프론트의 입력·표현 |
| Flutter Web (1차)·Windows 애플리케이션 (3차) | 프론트엔드·UX·QA | 전 모듈 API 연동 |

## 4. 핵심 데이터 모델

개발 전에 다음 엔티티와 관계를 ERD로 확정합니다.

```text
User
AcademicRecord
Course
Experience
VolunteerRecord
GraduationRule
GraduationRuleVolunteer
GraduationAudit
Document
DocumentChunk
JobPosting
JobRequirement
JobMatch
```

위 목록 중 `JobPosting`, `JobRequirement`, `JobMatch`는 2차 MVP의 채용 분석
도메인에 속한다. 1차 MVP의 실제 관계 모델은
[`docs/database-erd.md`](docs/database-erd.md)를 따른다.

공식 문서와 검색 결과에는 최소한 다음 출처 정보를 보존합니다.

```text
document_id
title
source_url
page
published_at
curriculum_year
department
document_type
```

DB 테이블과 외부 API의 요청·응답 모델은 분리합니다. DB 내부 구조가 바뀌더라도 가능한 한 기존 API 계약은 유지합니다.

## 5. API 계약

FastAPI의 Pydantic 모델을 원본으로 사용하고 자동 생성되는 OpenAPI 문서를 팀의 API 계약으로 관리합니다.

### 기본 규칙

- API 버전 경로는 `/api/v1`을 사용합니다.
- JSON 필드는 `snake_case`를 사용합니다.
- 식별자는 UUID 문자열을 사용합니다.
- 날짜는 `YYYY-MM-DD`, 시간은 ISO 8601 형식을 사용합니다.
- 상태값은 자유 문자열이 아닌 enum으로 정의합니다.
- 모든 AI 답변에는 가능한 경우 근거 문서와 출처를 포함합니다.
- 모든 오류는 공통 오류 응답 형식을 사용합니다.

### 우선 확정할 API

```text
PUT  /api/v1/academic-record
POST /api/v1/graduation/audits
POST /api/v1/assistant/queries
GET  /health
```

2차 MVP에서 채용 분석 API를 추가한다.

```text
POST /api/v1/job-postings/analyze
POST /api/v1/job-matches
```

### 졸업요건 상태값

```text
satisfied
not_satisfied
needs_review
not_applicable
```

### RAG 답변 상태값

```text
grounded
insufficient_evidence
needs_user_input
failed
```

근거가 충분하지 않으면 답변을 추측하지 않고 `insufficient_evidence`를 반환합니다.

### 공통 오류 형식 예시

```json
{
  "error": {
    "code": "INVALID_ACADEMIC_RECORD",
    "message": "이수학점은 0 이상이어야 합니다.",
    "field_errors": [
      {
        "field": "earned_credits",
        "reason": "must_be_greater_than_or_equal_to_zero"
      }
    ],
    "request_id": "req-example"
  }
}
```

## 6. 저장소 구조

구현을 시작할 때 다음 구조를 기준으로 디렉터리를 생성합니다.

```text
university-path/
├─ frontend/
│  ├─ lib/
│  │  ├─ features/
│  │  ├─ models/
│  │  ├─ services/
│  │  └─ shared/
│  └─ test/
├─ backend/
│  ├─ app/
│  │  ├─ api/
│  │  ├─ models/
│  │  ├─ schemas/
│  │  ├─ services/
│  │  ├─ rag/
│  │  ├─ rules/
│  │  └─ core/
│  ├─ migrations/
│  └─ tests/
├─ data/
│  ├─ raw/
│  └─ samples/
├─ docs/
│  ├─ architecture-erd.md
│  ├─ database-erd.md
│  ├─ initial-plan-comparison.md
│  ├─ specialized-ai-and-supporting-tools-proposal.md
│  ├─ job-matching-decision-layer-proposal.md
│  ├─ application-settings-ux.md
│  ├─ student-contributed-school-information-ux.md
│  ├─ menu-ux/
│  └─ web-windows-ux-guidelines.md
├─ compose.yaml
├─ .env.example
└─ README.md
```

## 7. 공통 개발환경

개발 도구와 개인 작업 방식은 자유롭게 선택할 수 있지만, 실행 환경과 검증 기준은 통일합니다.

### 프로젝트에서 관리할 파일

- `Dockerfile`: FastAPI 실행 환경 및 Python 버전
- `compose.yaml`: API, PostgreSQL, pgvector 구성
- 의존성 잠금 파일: Python 및 Flutter 패키지 버전
- `.env.example`: 필수 환경변수 이름과 예시
- Alembic 마이그레이션: 공통 DB 구조
- 시드 스크립트: 반복 가능한 테스트 데이터
- 테스트 명령어: 병합 전 공통 검증 기준

모든 팀원은 최종적으로 다음 명령으로 공통 환경을 실행할 수 있어야 합니다.

```bash
docker compose up --build
```

개인적으로 Python을 직접 실행하거나 다른 디버깅 방법을 사용해도 되지만, Pull Request를 병합하기 전에는 Docker 환경에서 정상 동작해야 합니다.

### Flutter 프론트엔드 설치 및 실행 (Windows)

`frontend/`는 Flutter Web과 Windows 목업을 함께 제공합니다. Flutter SDK를 내려받아
예를 들어 `C:\develop\flutter`에 압축을 풀고, `C:\develop\flutter\bin`을 사용자
`Path`에 추가합니다. Windows 앱도 빌드하려면 Visual Studio의 **Desktop development
with C++** 워크로드가 필요합니다. 자세한 설치 절차는 [Flutter 수동 설치 안내](https://docs.flutter.dev/install/manual)와 [Windows 개발 환경 안내](https://docs.flutter.dev/platform-integration/windows/setup)를 따른다.

설치 후 PowerShell을 새로 열어 도구를 확인합니다.

```powershell
flutter doctor -v
flutter devices
```

프론트엔드 실행과 검증 명령은 다음과 같습니다.

```powershell
cd frontend
flutter pub get
flutter run -d chrome      # Web 목업 실행
flutter run -d windows     # Windows 앱 실행
flutter analyze
flutter test
flutter build web
flutter build windows
```

Windows Release 실행 파일은 `frontend\build\windows\x64\runner\Release\university_path_frontend.exe`에 생성됩니다. Flutter가 `Path`에 없다면 위 명령의 `flutter` 대신 Flutter SDK의 `bin\flutter.bat` 절대 경로를 사용합니다.

## 8. 환경 분리 및 배포

클라우드 공급자는 MVP 완성도와 비용을 검토한 뒤 결정합니다. 애플리케이션은 특정 클라우드에 종속되지 않도록 Docker 기반으로 개발합니다.

| 환경 | 목적 | 데이터 |
|---|---|---|
| Local | 개인 개발 및 단위 테스트 | 로컬 테스트 데이터 |
| Staging | 팀 통합 테스트 및 시연 전 검증 | 가상 학생 데이터 |
| Production | 최종 서비스 및 발표 | 운영 데이터 |

동일하게 유지할 항목:

- 애플리케이션 코드와 Docker 이미지
- Python, PostgreSQL 및 pgvector 버전
- 라이브러리 버전
- DB 스키마와 API 계약

환경별로 분리할 항목:

- 데이터베이스와 접속 계정
- API 키와 비밀값
- 도메인 및 API 주소
- CORS 허용 주소
- 로그 수준과 데이터

Staging과 Production은 절대로 같은 DB를 사용하지 않습니다. `.env` 파일과 실제 비밀값은 Git에 커밋하지 않습니다.

## 9. Git 협업 방식

```text
main       Production 배포
develop    Staging 배포
feature/*  기능 개발
```

기본 작업 흐름:

```text
feature 브랜치
→ Pull Request
→ 코드 리뷰 및 자동 테스트
→ develop 병합
→ Staging 통합 테스트
→ main 병합
→ Production 배포
```

API 계약이나 DB 스키마 변경은 구두로 처리하지 않고 Pull Request에서 관련 담당자가 함께 검토합니다.

## 10. 테스트 전략

### 자동 테스트

- FastAPI 요청·응답 검증
- Rule Engine 단위 및 경계값 테스트
- API와 DB 통합 테스트
- RAG 검색 결과와 출처 존재 여부 확인
- Flutter 위젯 및 화면 테스트
- 빌드와 `/health` Smoke Test

### 수동 시나리오 테스트

- 학사정보 입력 및 수정
- 졸업요건 충족·미충족 결과 확인
- AI 답변의 근거 문서와 페이지 확인
- 활동·프로젝트 등록
- Flutter Web 화면 확인

### 2차 MVP 수동 시나리오

- 채용공고 입력과 경험 비교

### 3차 MVP 수동 시나리오

- Windows 애플리케이션 화면 및 파일 연동 확인

### 기본 테스트 사용자

- 모든 졸업요건을 충족한 사용자
- 총 학점이 부족한 사용자
- 승인 봉사시간만 부족한 사용자
- 학사정보가 일부 누락된 사용자
- 적용 교육과정이 다른 사용자
- 관련 직무 경험이 있는 사용자와 없는 사용자 (2차 MVP)

## 11. 보안 기본사항

- API 키, 비밀번호 및 `.env`를 Git에 커밋하지 않습니다.
- 실제 학생 개인정보를 개발 및 Staging 테스트에 사용하지 않습니다.
- 테스트 DB와 운영 DB를 분리합니다.
- 파일 업로드 형식과 크기를 제한합니다.
- 비밀번호는 안전한 해시로 저장합니다.
- 로그에 개인정보나 비밀값을 기록하지 않습니다.
- 운영 CORS는 실제 프론트엔드 도메인만 허용합니다.

## 12. 개발 시작 전 체크리스트

- [ ] MVP 필수 기능 확정
- [ ] 역할별 담당자 지정
- [ ] 시스템 구성도 검토
- [ ] 핵심 DB ERD 작성
- [ ] 핵심 API 요청·응답 합의
- [ ] 졸업요건 Rule Engine 입력·출력 정의
- [ ] 데이터 출처와 사용 조건 확인
- [ ] Docker 및 Compose 실행환경 구성
- [ ] `.env.example` 작성
- [ ] Git 브랜치 및 리뷰 규칙 확정
- [ ] 대표 테스트 데이터 준비
- [ ] 1차 데모 시나리오 작성

위 항목 중 DB 구조, API 계약, 졸업요건 판정 방식은 기능 구현을 시작하기 전에 팀 전체가 함께 확정합니다.
