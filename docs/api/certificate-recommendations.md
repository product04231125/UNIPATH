# 자격증 추천·시험 일정 API (2026-11-24)

자격 메뉴의 `자격증 추천`과 `시험 일정` 탭이 쓰는 API다. 관리자용 자격증·발급기관 마스터([certificates.md](certificates.md))와는 별개다.

- **AI가 맡는 부분:** 추천 대상 고르기와 추천 이유.
- **공식 데이터가 맡는 부분:** 날짜, 응시료, 시험 과목, 응시자격 안내. AI가 만들지 않는다.

## 데이터 출처

| 대상 | 출처 | 방식 |
| --- | --- | --- |
| 국가기술자격 513종목 | Q-Net 공개 API `InquiryTestInformationNTQSVC/getJMList?jmCd=` | 실시간(6시간 캐시) |
| 국가전문자격 100종목(37계열) | Q-Net 공개 API `InquiryTestDatesNationalProfessionalQualificationSVC/getList?seriesCd=` | 실시간(6시간 캐시) |
| 응시료 | `InquiryTestInformationNTQSVC/getFeeList?jmCd=` | 24시간 캐시 |
| 시험 과목·방법·합격 기준(취득방법), 출제경향 | `InquiryInformationTradeNTQSVC/getList?jmCd=` | 24시간 캐시 |
| 종목 목록 613개 | `InquiryListNationalQualifcationSVC/getList` | 저장소 사본 `backend/app/rag/career/data/qnet_qualifications.json` |
| 그 밖의 자주 찾는 자격(SQLD, ADsP, 컴활, 토익 등) | 시행 기관 공식 공지 | 직접 확인해 `data/private_certificates.json`에 원문 링크·확인일과 함께 저장 |

### Q-Net 공개 API
- `openapi.q-net.or.kr`의 위 경로들은 2026-11-24 기준으로 인증키 없이 응답한다.
- HTTP로만 열려 있다.
- 졸업작품이라 키 없이 쓴다.
- 정식 서비스로 바꿀 때는 키 방식으로 옮긴다.
  - 공공데이터포털에서 활용신청을 하고 `QNET_SERVICE_KEY`를 설정한다. 키는 `ServiceKey`로 붙는다.
  - 필요하면 `QNET_API_BASE`로 주소를 바꾼다.
- 실패한 요청은 2분 동안 다시 부르지 않는다.

### 그 밖의 자격
- 데이터자격검정은 robots.txt가 전체를 막는다. 대한상공회의소는 자격 페이지 경로를 막는다.
- 그래서 자동으로 수집하지 않는다. 공식 공지를 사람이 확인해 넣는다.
- 확인일이 지난 데이터는 공식 사이트 링크로 다시 확인하게 한다.

### 연도 범위
Q-Net API는 해당 시험 연도의 회차만 준다. 다음 연도 일정이 아직 올라오지 않았으면 다음과 같이 처리한다.
- `status=unpublished`로 표시한다.
- 올해 회차를 `reference_rounds`(참고)로 보여 준다.

## `GET /api/v1/me/certificates?query=`
카탈로그에서 이름으로 찾는다. 별칭도 이름으로 본다. 정확히 같은 이름, 앞부분이 같은 이름, 이름에 포함된 것 순서로 최대 20개를 돌려준다. AI를 쓰지 않는다.

## `GET /api/v1/me/certificates/{id}`
- **id:** `qnet-<종목코드>` 또는 `private-<id>`.
- **응답 필드:** `name`, `kind`/`kind_label`, `issuer`, `grade`, `field`, `official_url`, `fee`, `method`(취득방법), `trend`(출제경향), `subjects`, `pass_criteria`, `eligibility_note`, `schedule`.
- **응시자격 안내:** 기사·기술사·기능장 등급에는 학력·경력 응시자격이 있다는 안내를 붙인다. 충족 여부는 판정하지 않는다.

`schedule`의 필드:

| 필드 | 내용 |
| --- | --- |
| `status` | `upcoming`, `unpublished`, `always`(상시 시험), `unavailable`(불러오기 실패) |
| `rounds` | 아직 끝나지 않은 회차 |
| `reference_rounds` | 참고용 올해 회차 |
| `next_registration` | 아직 끝나지 않은 가장 이른 접수 |
| `next_event` | 아직 끝나지 않은 가장 이른 일정 |
| `source`, `source_url`, `checked_at` | 출처, 원문 링크, 확인일 |
| `failure_reason`, `note` | 실패 이유, 참고 메모 |

각 회차는 `{name, events: [{kind: registration|exam|result|document, label, start, end}]}`이다.

## `POST /api/v1/me/certificate-recommendations`
요청은 `records`(저장된 기록 전체), `academic_stage`, `external_processing_consent`다. 목표 직무가 없으면 `needs_user_input`과 `career_goal`을 돌려준다.

### 처리
1. 가장 최근에 저장된 목표 직무 분석에서 다음을 꺼낸다.
   - 부족 요건과 각 요건이 나온 공고 수
   - 분석한 공고 수
2. 자격 기록 제목으로 이미 가진 자격을 찾아 카탈로그에서 뺀다.
3. AI를 한 번 호출한다(최대 110초).
   - 입력: 목표 직무, 부족 요건, 개인정보를 가린 기록, 학년, 카탈로그 이름 목록.
   - 카탈로그에 있는 이름만 받는다. 별칭이 정확히 같아도 받는다.
   - 보완 요건과 관련 기록은 받은 원문과 똑같은 것만 남긴다.
   - 보유 자격과 중복은 버린다.
   - AI에게 날짜·응시료·응시자격·합격률을 말하지 말라고 지시한다.
4. 기록이 바뀌지 않았는지 다시 확인한다. 그다음 추천마다 공식 일정 `schedule`과 공고 근거 `evidence [{requirement, frequency}]`를 붙인다.

### 응답
`status`, `goal`, `gap_basis {analyzed_at, gaps, postings}`, `recommendations[]`, `held`, `summary`, `model`, `generated_at`.

`recommendations[]`의 각 항목:

| 필드 | 내용 |
| --- | --- |
| `certificate` | 카탈로그 항목 |
| `reason` | 추천 이유 |
| `requirements` | 보완하는 부족 요건 |
| `related_records` | 시험 범위를 이미 다룬 내 기록 |
| `timing` | 준비 시기 |
| `weeks` | 예상 공부 기간(주) |
| `evidence` | 공고 근거(요건과 나온 공고 수) |
| `schedule` | 공식 일정 |

게이트웨이·웹 nginx는 이 경로에 180초를 허용한다.
