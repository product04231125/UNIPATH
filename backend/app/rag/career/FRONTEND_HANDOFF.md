# 프론트 담당자용 · 내 자료로 공고 찾기

> **2026-11-19 최신 적용법:** [10개 후보·최소 카드·학년별 안내](TEAM_INTEGRATION.md).

> API 승인 대기 시 [고용24 크롤링 전환 가이드](CRAWLING_HANDOFF.md)를 사용한다. 기존 API 경로와 응답 형식을 유지한다.

취업 메뉴의 `career:recommend` 버튼을 새 화면에 연결한다. 학생이 직무·지역과 자료를 선택하고 **분석 실행**을 눌렀을 때 `POST /api/v1/me/job-recommendations`를 한 번 호출한다. 공고 본문을 직접 입력하는 기존 `career:posting`은 기존 단건 분석 흐름을 사용한다.

## 폼과 요청

1. 직무 키워드와 지역을 학생이 직접 선택한다. “전국”도 명시적 선택이다. 특정 지역은 사람인·고용24별 공식 코드 매핑을 `region_codes`로 함께 보낸다. 전국에서는 이 필드를 생략한다.
2. **기기 파일 선택**과 **내 저장 기록 선택**을 제공한다. 이번 요청에서 선택한 파일은 `documents`로, 저장된 기록은 `records`로 보낸다. 과거에 업로드한 원본 파일을 ID로 다시 불러오는 보관함 API는 아직 없다. 파일 인용 ID는 재사용할 수 없다.
3. 지원 확장자는 PNG, JPG/JPEG, WebP, PDF, DOCX, UTF-8 TXT/MD다. 총 5개·합계 8MiB 이하, 단일 사진 2,500만 화소 이하, PDF당 100쪽 이하, 요청당 OCR 20장 이하다. 저장 기록과 추출한 문서 조각을 합쳐 최대 20개다. 사진·스캔 PDF의 OCR은 서버가 수행한다.
4. 선택한 파일명과 기록을 보여주고 **선택 자료에서 추출한 텍스트를 외부 Gemini에 보내 공고와 비교한다**는 동의를 받는다. 실행 중 버튼을 비활성화하고 파일 처리·공고 비교에 시간이 걸릴 수 있음을 표시한다. 자동 재전송은 추가 유료 호출이 될 수 있다.

기존 Flutter `ApiGateway`의 로그인 세션을 재사용한다. 아래 예시의 base64는 UTF-8로 인코딩한 “Python project”다. 실제 사진/PDF는 파일 바이트에 `base64Encode(bytes)`를 적용하고 data URL 접두어는 붙이지 않는다.

```dart
final result = await api.request('POST', 'me/job-recommendations', {
  'keyword': 'Engineer',
  'region': '서울',
  'documents': [
    {'filename': 'portfolio.txt', 'content_base64': 'UHl0aG9uIHByb2plY3Q='},
  ],
  'records': [],
  'external_processing_consent': true, // 화면에서 동의를 받은 경우
  'limit': 1, // 1~3, 생략하면 3
});
```

저장 기록은 각 항목에 `kind`, `record_id`(UUID), `expected_version`(정수)을 넣는다. 종류는 course, activity, experience, credential, achievement다. 파일과 기록 중 적어도 하나가 필요하다. 기존 [단건 분석 클라이언트](../../../../frontend/lib/features/api/job_analysis_api.dart)의 최상위 응답 파서는 새 추천 응답과 구조가 다르므로 별도 응답 모델을 사용한다.

## 응답을 화면에 연결

[전체 JSON 예시](examples/document-recommendation-response.json)는 합성 공고와 모의 모델로 실행한 추천 핸들러의 실제 출력이다. **부분 성공 + 추천 한 건**을 테스트할 때 사용한다.

| 화면 | 읽을 필드와 표시 방법 |
|---|---|
| 추천 목록 | 서버가 정렬한 `recommendations[]` 순서로 제목·회사·원문 URL을 표시한다. `required_to_check`는 근거가 충분하지 않은 필수조건 개수다. 추천은 필수조건을 모두 충족한 공고뿐이라 항상 0이다(2026-11-25). |
| 카드 펼치기 | 카드와 `items[].posting`을 `(source, source_id)`로 연결한다. 지역·마감·출처, `warnings`와 전체 `comparisons`를 표시한다. 사람인의 `metadata_only`는 공고 요약 기준, `excerpt`는 본문 일부 기준이다. |
| 왜 추천됐나요? | `matched_requirements[].posting_evidence.excerpt`와 `personal_evidence[].excerpt`를 나란히 표시한다. 지원 여부를 판정하는 점수로 바꾸지 않는다. |
| 내 자료 인용 | 개인 인용의 `record_id`로 `document_locations`를 조회한다. 있으면 `filename`과 `location`을, `method == "ocr"`이면 “자동 문자 인식 · 원본 확인”을 표시한다. 없으면 선택한 저장 기록의 종류·ID·버전으로 표시한다. |
| 자료 주의사항 | `document_warnings`를 표시한다. PDF 쪽수는 1부터 시작한다. 업로드 인용의 `offset`은 가림 처리된 페이지 내 조각 시작 위치다. |

**추천이 비어 있으면** 최상위 검색 상태와 공고별 분석 상태를 순서대로 확인한다.

| 응답 | 화면 동작 |
|---|---|
| HTTP 200, `needs_user_input` / `not_configured` | 이 응답에는 목록이 없다. `missing_fields`로 동의·자료 선택을 안내하거나 서버 준비 중을 표시한다. |
| `partial` | 성공한 수집처의 카드도 표시한다. `sources`에서 미설정·실패·시간 제한으로 생략한 수집처를 구분한다. |
| `no_results` / `not_available` | 전자는 검색에 성공한 수집처에서 표시할 공고가 없는 경우, 후자는 성공한 수집처가 없는 경우다. |
| 후보는 있으나 추천 0건 | `items[].analysis_status`가 `completed`면 비교한 요건을 보여준다. `insufficient_evidence`면 비교 근거 부족, `failed`·`not_configured`·`budget_exhausted`면 분석 실패·설정 필요·이번 요청의 분석 한도로 표시한다. |
| HTTP 401 / 404 / 409 | 세션 재확인 / 선택 자료 또는 API 경로 확인 / 기록 새로고침 후 재선택. |
| HTTP 413 / 422 / 429 / 503 | 파일 용량 축소 / 형식·판독 가능 여부 확인 / 호출 제한 후 재시도 / OCR 서버 상태 확인. 응답의 오류 메시지를 활용한다. |

화면 QA는 ① 추천 한 건에서 공고 인용과 파일 출처 펼치기 ② 같은 화면에서 추천 0건과 공급자 실패 구분 ③ 한글 자격증 사진과 혼합 PDF에서 OCR 표시·쪽수 확인 ④ 글자가 없는 사진의 오류 안내 순서로 진행할 수 있다. API가 404이면 [서버 적용 문서](SERVER_HANDOFF.md)의 실행 프로필부터 확인한다.
