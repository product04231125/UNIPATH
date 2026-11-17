# 서버 담당자용 · 문서 기반 취업 추천 적용

학생이 선택한 직무·지역으로 공고를 검색하고, 업로드한 문서와 본인 기록에서 찾은 근거를 함께 돌려주는 인증 API다. 적용할 경로는 `POST /api/v1/me/job-recommendations`다. 구현은 `feature/rag-document-job-recommendations` 작업본에 있다. 다음 명령은 해당 파일들이 포함된 체크아웃의 저장소 루트에서 실행한다.

## 1. 로컬에서 이미지와 라우트 확인

```sh
docker compose -f compose.yaml -f backend/app/rag/career/compose.documents.yaml up -d --build api
docker compose exec -T api tesseract --list-langs
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H 'Content-Type: application/json' -d '{"keyword":"Engineer","region":"서울"}' \
  http://127.0.0.1:8010/api/v1/me/job-recommendations
```

기본 포트는 8010이다. `API_PORT`를 바꿨다면 해당 포트를 사용한다. OCR 목록에 `kor`, `eng`가 있고, 인증 없는 위 요청이 401이면 이미지와 인증 라우트가 준비된 것이다. 404이면 실행 명령을 확인한다. [OCR 이미지](Dockerfile)와 [Compose 설정](compose.documents.yaml)은 기존 앱을 생성한 뒤 추천 라우터를 붙이는 `app.rag.career.api:create_app --factory`를 사용한다.

## 2. 스테이징 환경 설정

| 서버 환경 변수 | 적용 방법 |
|---|---|
| `VERTEX_PROJECT`, `VERTEX_LOCATION`, `VERTEX_MODEL` | 기존 앱 설정을 그대로 쓴다. 추천기도 다른 Gemini 기능과 같은 리전·모델을 사용한다(D2, 스테이징 `asia-northeast1`·`gemini-3.5-flash`). 11월 16일 실측의 `gemini-3.8-flash`는 도쿄에서 404였고 `global`에서만 성공했으므로, 이 모델을 쓰려면 학생 자료 처리 리전을 팀에서 다시 정해야 한다. |
| `VERTEX_CREDENTIALS_FILE` | 호스트의 서비스 계정 JSON 경로. API 컨테이너의 `/run/secrets/vertex-credentials.json`에 읽기 전용으로 마운트하고 `GOOGLE_APPLICATION_CREDENTIALS`가 이를 가리키게 한다. UID 10001의 읽기 권한을 확인한다. |
| `SARAMIN_ACCESS_KEY` | 현재 승인 대기. 승인 후 스테이징 비밀 설정에 추가하고 **api 컨테이너 환경에 전달**한 뒤 재생성한다. |
| `WORK24_AUTH_KEY` | 고용24에서 발급받은 경우 같은 방식으로 전달한다. |
| `CAREER_GREENHOUSE_BOARD` | 기본값 `sendbird`. 승인 대기 중 공개 공고 테스트에 사용한다. 빈 문자열은 이 수집처를 끈다. |

지역 설정은 다른 Vertex 기능과 공유한다. 기존 스테이징 설정을 변경하기 전에 학생 자료 처리 위치와 다른 기능에 미치는 영향을 확인한다. 합성 자료로 global 호출은 확인했으며 실제 학생 자료를 사용할 리전은 팀에서 확정한다. 프론트에는 공급자 키를 전달하지 않는다.

## 3. 기존 서버 배포 구성에 반영

1. [서버 Compose](../../../../compose.server.yaml)는 검증된 이미지 ID를 참조한다. 로컬용 오버레이를 운영에 그대로 덮어쓰지 말고, **api 서비스에만** 취업 OCR 이미지·전용 실행 명령·위 환경 변수를 적용한다. `migrate`는 기존 마이그레이션 이미지와 명령을 유지한다. OCR 이미지는 마이그레이션 디렉터리를 포함하지 않는다. 이전 API 이미지 ID와 설정으로 되돌릴 수 있게 기록한다.
2. 외부 게이트웨이와 웹 프록시 양쪽에서 새 POST 경로가 API로 전달되는지 확인한다. 현재 [웹 프록시](../../../../deploy/preview/nginx.conf)의 일반 `/api/v1/me/` 제한은 256k다. 원본 합계 8MiB는 base64만 약 10.7MiB이므로, 전체 범위를 허용하려면 해당 경로에 JSON 여유분까지 포함한 본문 한도(예: 12m)를 적용한다. 프록시와 앱 중 작은 한도가 실제 업로드 한도다.
3. OCR과 공급자 호출을 순차 실행하는 동기 요청이다. OCR 예산 45초, 검색·비교 예산 60초는 전체 HTTP 강제 종료 시간이 아니다. 스테이징에서 이미지와 공고 1~3건으로 측정해 클라이언트와 각 프록시의 타임아웃을 맞춘다. 개인 문서 본문·base64·인용문·키는 로그에 남기지 않는다.

## 4. 인수 확인

- **인증된 요청**으로 [프론트 요청 예시](FRONTEND_HANDOFF.md)를 실행한다. 먼저 서울 / Engineer / 1건과 합성 PNG로 확인한다. `sources`에서 Greenhouse 상태, `items[].analysis_status`에서 모델 비교 결과, `document_locations`에서 OCR 출처를 각각 확인한다. 성공적으로 비교해도 추천은 0건일 수 있다.
- **사람인 승인 후** 같은 API에 `region: "전국"`과 한국어 직무를 보내고 `sources` 중 `source: "saramin"`이 `completed`인지 확인한다. 사람인 실공고 표시까지 확인하려면 `items[].posting.source`도 확인한다. 지역 지정 검색에는 사람인 공식 지역 코드가 필요하다.
- **장애 구분** — 413은 프록시/업로드 크기, 422는 요청·문서·OCR 판독, 503은 OCR 설치·언어·혼잡, 429는 호출 제한을 확인한다. HTTP 200의 `not_configured`는 분석기 설정, 개별 공고의 `analysis_status: "failed"`는 모델 호출 또는 인용 검증 실패다. 요청 ID로 추적한다.
- **검증 범위** — Linux 이미지에서 한글·영문 사진과 스캔 PDF OCR을 확인했다. 실제 Vertex와 공개 공고의 비교도 확인했다. 추천 카드가 나온 테스트는 합성 모델 응답을 사용했다. 사람인 실호출과 학생 화면 전체 흐름은 승인·배포·화면 연결 후 검증할 항목이다.
