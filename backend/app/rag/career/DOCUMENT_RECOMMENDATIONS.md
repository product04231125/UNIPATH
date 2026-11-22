# 개인 문서 기반 취업 추천 API

[서버 적용 가이드](SERVER_HANDOFF.md) · [프론트 연동 가이드와 응답 예시](FRONTEND_HANDOFF.md)

기준 커밋은 develop의 `bd09f9f`다. Flutter 취업 분석 화면은 공고 본문 한 건과 사용자가 고른 개인 기록을 기존 `POST /api/v1/me/job-analyses`로 보낸다. 백엔드는 소유권·기록 버전·외부 처리 동의를 검사하고 Vertex 응답의 공고 인용과 기록 인용을 검증한다. RAG의 기존 PDF 수집은 학교 문서용이고, 기존 다중 공고 검색기는 개인 기록에 대한 비교 결과를 수집처 순서로 반환한다.

이번 API는 학생이 직접 선택한 포트폴리오·자격 자료와 저장된 기록을 함께 받아 최대 3건의 공고를 비교한다. 일반 학사규정은 개인의 이력을 증명하는 자료로 등록하지 않는다.

## 실행

기본 API(`app.main`)가 이 라우터를 함께 제공한다. 기존 세션·DB·인증과 채용 분석의 Gemini 모델을 그대로 쓴다. 기본 API 이미지(`backend/Dockerfile`)에 PDF 렌더러와 한글·영문 Tesseract OCR이 들어 있어 별도 이미지나 실행 명령이 필요 없다.

```sh
docker compose up -d --build api
```

Docker 없이 실행할 때는 서버에 Tesseract와 kor·eng 언어 데이터를 설치하고 `--group ingestion` 의존성으로 기본 API를 실행한다. 학생 기기에는 설치할 프로그램이 없다. API 명세는 `/api/v1/docs`에서 확인한다.

기존 Vertex 설정(VERTEX_PROJECT, VERTEX_LOCATION, VERTEX_MODEL 3개)과 해당 프로젝트의 ADC가 필요하다. Compose에서는 VERTEX_CREDENTIALS_FILE로 서비스 계정 파일 경로를 지정한다. 추천 기능도 다른 Gemini 기능과 같은 `VERTEX_LOCATION`·`VERTEX_MODEL`을 쓴다(D2). 스테이징은 `asia-northeast1`, `gemini-3.5-flash`다. 모델·리전을 바꾸려면 팀 결정(D2)을 먼저 고친다.

기본 공개 공고는 Sendbird의 Greenhouse 채용 보드에서 조회한다. CAREER_GREENHOUSE_BOARD로 기업 보드 토큰을 변경하거나 빈 값으로 끌 수 있다. 직무는 공고 제목에서 대소문자 구분 없이 검색한다. 영문 제목은 영문 직무 키워드를 사용한다. SARAMIN_ACCESS_KEY, WORK24_AUTH_KEY가 있으면 기존 수집기도 호출한다. 잡코리아는 기존 승인 명세가 필요하다.

## 프론트 요청

인증된 학생 세션으로 JSON을 `POST /api/v1/me/job-recommendations`에 전송한다.

```json
{
  "keyword": "Engineer",
  "region": "서울",
  "documents": [{"filename": "portfolio.txt", "content_base64": "UHl0aG9uIHByb2plY3Q="}],
  "records": [],
  "external_processing_consent": true,
  "limit": 2
}
```

- `records`는 기존 API의 kind, record_id, expected_version 형식이다. 문서와 저장 기록 중 하나 이상을 선택한다.
- `content_base64`에는 파일 바이트만 base64로 인코딩한다. PNG·JPEG·WebP, PDF, DOCX 본문, UTF-8 TXT/MD를 지원한다. 사진과 텍스트가 없는 PDF 페이지는 서버에서 OCR 처리한다. 추출한 텍스트의 제어 문자(일부 PDF 글꼴이 공백 대신 내는 `\x01` 등)는 공백으로 바꾼 뒤 모델에 보낸다. 파일 선택기에 .png/.jpg/.jpeg/.webp를 추가하고 기존과 같은 documents 배열로 전송한다. 단일 이미지 최대 2,500만 화소, 요청당 OCR 최대 20장이다. PDF는 최대 100쪽, 파일 최대 5개, 총 8MiB, 개인 기록과 추출 조각 합계 최대 20개다. 서버 앞 프록시의 본문 제한이 더 작으면 413을 받을 수 있다.
- 직무 대분류는 `category_codes`(고용24 1차·2차 직종 코드, 최대 10개)로 보낸다. 대분류가 있으면 `keyword`는 세부 검색어이고 비워도 된다. 목록과 동작은 [대분류 검색](CATEGORY_SEARCH_HANDOFF.md)을 따른다.
- 사람인/고용24의 지역 검색에는 `region_codes`에 선택한 지역의 공식 공급자별 코드를 보낸다. `region: "전국"`은 명시적 국내 전국 선택이다. Greenhouse는 서울·경기의 영문 별칭, 그 외 지역은 공고 위치의 표기를 사용한다.
- 개인 자료는 연락처·이메일 등 패턴과 로그인 이름을 가린 뒤 모델에 전달한다. 파일명은 모델에 보내지 않는다. 원문에 다른 사람의 이름이나 식별 정보가 남을 수 있어 외부 처리 동의를 먼저 받는다.

## 응답과 화면

1. `recommendations`가 추천 카드 목록이다. 회사·제목·URL과 `matched_requirements`에 들어 있는 개인 기록 및 공고 인용을 함께 표시한다. 미확인 필수조건 수가 작은 순서, 이어 근거가 확인된 요건 수가 많은 순서다. 최소 한 요건이 supported여야 하고, 필수조건이 있으면 적어도 하나가 supported여야 추천한다.
2. `items`는 비교 대상 공고 전체다. 각 항목의 `analysis_status`, `analysis_scope`, `warnings`와 각 요건의 필수/우대·비교 상태를 표시한다. 미확인 조건이 남을 수 있다. 요약 메타데이터만 있는 공고는 해당 범위를 카드에 표시한다.
3. 업로드 자료의 인용 record_id를 `document_locations`에서 찾아 파일명과 페이지/본문을 보여준다. offset은 가림 처리된 페이지 또는 본문 내 조각의 시작 위치다. method가 ocr이면 인용 옆에 “자동 문자 인식 · 원본 확인”을 표시한다. OCR 결과도 개인 식별 정보 가림 처리를 거친다. 파일 인용 ID는 해당 요청에서만 유효하다. `document_warnings`에는 일부 페이지에서 텍스트를 추출하지 못한 경우가 담긴다. 공고별 `items[].warnings`에는 일부 기록만 비교했거나, 원문에서 확인하지 못한 요건을 빼거나 근거 부족으로 바꾼 경우의 안내가 담긴다([인용 검사](../../../../docs/api/job-analysis.md#응답과-검증)).
4. `status=needs_user_input`은 자료 또는 동의 필요, `not_configured`는 모델 설정 필요다. 검색 이후 최상위 상태와 `sources`는 수집 결과다. 추천이 비었을 때는 `items[].analysis_status`로 모델 실패·근거 부족을 구분한다. 동의 없이 모델을 호출하지 않는다.
5. 읽을 수 있는 글자가 없는 파일은 422, OCR 엔진이나 언어 데이터가 준비되지 않았거나 서버가 사용 중이면 503이다.
6. 일반 실행 명령 `app.main:app`과 기존 프론트에는 이 엔드포인트가 등록되지 않는다. 로컬에서는 위의 실행 프로필을 사용한다. 스테이징 적용 시 이미지와 게이트웨이의 경로·요청 크기·타임아웃 설정도 함께 확인한다.

## 연결된 환경에서 모델 호출 검증

backend 디렉터리에서 아래 명령으로 DB나 프론트 로그인 없이 동일한 수집기·문서 처리·비교기를 실행할 수 있다. 스테이징 모델 검증에는 합성 포트폴리오를 사용한다. 실제 학생 파일을 실행할 때는 해당 학생이 외부 전송에 동의한 자료만 선택한다. 출력에는 개인 인용이 있으므로 공유 로그에 저장하지 않는다.

```sh
uv run --frozen --group ingestion python -m app.rag.career \
  ./synthetic-portfolio.pdf --keyword Engineer --region 서울 --limit 1 --consent
```
