# 자격증 추천·시험 일정 API (2026-11-24)

자격증 메뉴의 `자격증 추천`과 `시험 일정` 탭이 쓰는 API다. 관리자용 자격증·발급기관 마스터([certificates.md](certificates.md))와는 별개다.

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
| 다음 연도 국가기술자격 정기검정(등급별) | 고용노동부 공고 제2026-518호 「2027년도 국가기술자격 검정시행계획」 한국산업인력공단 편 | `data/hrdk_exam_plan.json` |
| 그 밖의 자주 찾는 자격 19종 | 시행 기관 공식 공지 | 직접 확인해 `data/private_certificates.json`에 원문 링크·확인일과 함께 저장 |

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

### 그 밖의 자격 19종
SQLD, ADsP, 빅데이터분석기사, 컴활, 정보보안기사, 리눅스마스터, 네트워크관리사, TOEIC, TOEIC Speaking, OPIc, 한국사, 전산회계, 전산세무, GTQ, 유통관리사, 무역영어, AWS SAA, JLPT, HSK다.
- **출처:** 회차마다 공식 출처 URL과 확인일(2026-11-24)이 있다.
- **robots.txt로 막힌 사이트:** dataq, cq.or.kr, opic 등이다. 읽지 않았다.
- **대체 출처:** 고용노동부 시행계획 공고, 그리고 기관이 공공데이터포털에 올린 파일로 채웠다.
- **일정 상태**
  - 2027 일정이 아직 공고되지 않은 자격은 `unpublished`로 두고, 2026 회차를 참고로 보여 준다.
  - 공식 출처를 읽지 못한 자격(SQLD·ADsP·네트워크관리사·전산회계·전산세무)은 `unconfirmed`로 표시한다.
  - 상시 시험(컴활·OPIc·AWS)은 `always`다.

### 연도 범위
Q-Net API는 해당 시험 연도의 회차만 준다.
- **시행계획으로 대신:** 국가기술자격 종목에 다음 접수가 없으면, 같은 등급의 고용노동부 시행계획 회차를 대신 쓴다. 등급은 기사(산업기사 포함), 기능사, 기술사, 기능장이다. 이때 `source`는 공고 이름이고, 일부 회차는 종목에 따라 시행하지 않을 수 있다는 `note`를 붙인다.
- **Q-Net이 우선:** Q-Net에 다음 연도 회차가 올라오면 Q-Net 일정을 쓴다.
- **둘 다 없을 때:** `status=unpublished`로 두고 다음을 보여 준다.
  - 아직 끝나지 않은 회차: `rounds`
  - 지난 회차(참고): `reference_rounds`
- **기술사:** 두 번째 단계를 `면접`으로 표시한다.

## `GET /api/v1/me/certificates?query=`
카탈로그에서 이름으로 찾는다. 별칭도 이름으로 본다. 정확히 같은 이름, 앞부분이 같은 이름, 이름에 포함된 것 순서로 최대 20개를 돌려준다. AI를 쓰지 않는다.

## `GET /api/v1/me/certificates/{id}`
- **id:** `qnet-<종목코드>` 또는 `private-<id>`.
- **응답 필드:** `name`, `kind`/`kind_label`, `issuer`, `grade`, `field`, `official_url`, `fee`, `method`(취득방법), `subjects_text`(시험과목 및 배점), `eligibility`(Q-Net 응시자격 원문), `trend`(출제경향), `subjects`, `pass_criteria`, `eligibility_note`, `schedule`.
- **응시자격 안내:** 기사·기술사·기능장 등급에는 학력·경력 응시자격이 있다는 안내를 붙인다. 충족 여부는 판정하지 않는다.

`schedule`의 필드:

| 필드 | 내용 |
| --- | --- |
| `status` | `upcoming`, `unpublished`, `unconfirmed`(공식 출처 확인 못 함), `always`(상시 시험), `unavailable`(불러오기 실패) |
| `rounds` | 아직 끝나지 않은 회차 |
| `reference_rounds` | 참고용 올해 회차 |
| `next_registration` | 아직 끝나지 않은 가장 이른 접수 |
| `next_event` | 아직 끝나지 않은 가장 이른 일정 |
| `source`, `source_url`, `checked_at` | 출처, 원문 링크, 확인일 |
| `failure_reason`, `note` | 실패 이유, 참고 메모 |

각 회차는 `{name, events: [{kind: registration|exam|result|document, label, start, end}]}`이다.

## `POST /api/v1/me/certificate-recommendations`
요청은 `records`(저장된 기록 전체), `academic_stage`, `external_processing_consent`다. 목표 직무가 없으면 `needs_user_input`과 `career_goal`을 돌려준다. 앱은 학업 프로필의 학년을 `academic_stage` 기본값으로 보내고, 끝난 결과를 [저장된 분석 결과](materials-and-results.md)에 `kind=certificate`로 저장한다(이 API는 저장하지 않는다).

### 처리
1. 가장 최근에 저장된 목표 직무 분석에서 다음을 꺼낸다.
   - 부족 요건과 각 요건이 나온 공고 수
   - 분석한 공고 수
2. 이미 가진 자격을 찾아 카탈로그에서 뺀다(응답 `held`).
   - 보유로 보는 자격 기록: 취득일이 오늘(한국 날짜) 이전인 것, 또는 상태·취득일 없이 이름만 있는 것.
   - 상태만 있고 취득일이 없는 자격(예: `필기 합격, 실기 준비 중`)은 빼지 않는다. AI가 기록의 상태를 읽고 이미 딴 것이면 추천하지 않고, 준비 중이면 그 준비를 이어 가는 시기로 추천할 수 있다(2026-11-25).
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

## `POST /api/v1/me/certificate-study-plans`
고른 자격증의 시험일까지 주차별 학습 계획을 만든다. 요청은 다음과 같다.
- `certificate_id`
- `exam_date`: 내일부터 2년 안. 벗어나면 422.
- `hours_per_week`: 1~40.
- `records`: 저장된 기록 전체.
- `external_processing_consent`

### 처리
1. **공식 범위를 정한다.**
   - Q-Net 종목: `시험과목 및 배점`, `취득방법`, `출제경향` 원문을 쓴다. 과목 이름은 `취득방법`의 `시험과목` 구역에서 뽑는다(`- 필기 1. A 2. B`, `- 실기 : C`).
   - 그 밖의 자격: 저장한 과목 목록을 쓴다.
   - 불러오지 못하면 범위가 비고 `scope.source=null`이 된다. 화면은 이때 AI가 일반 지식으로 짰다고 경고한다.
2. **주 수를 정한다.** 시험일까지 남은 날을 7로 나눠 올림하고, 최대 26주다.
3. **AI를 한 번 호출한다.**
   - 주마다 목표, 과목, 할 일(최대 4개), 시간, 참고 기록을 받는다.
   - 서버가 다음을 검사한다.
     - 과목: 공식 목록에 있거나 공식 원문에 실제로 들어 있는 글만 남긴다.
     - 시간: 주당 시간을 넘지 않는다.
     - 참고 기록: 기록 제목과 같은 것만 남긴다.
     - 주 수: 절반에 못 미치면 실패로 처리한다.
4. **날짜를 서버가 붙인다.** 시험일에서 거꾸로 계산하며, 오늘 이전이나 시험 당일에 걸리지 않게 한다.

### 응답
`status`, `certificate`, `exam_date`, `hours_per_week`, `scope {subjects, source}`, `weeks[{week, start, end, focus, subjects, tasks, hours, related_records}]`, `advice`.

화면은 시험 일정 탭 상세에서 다음을 보여 준다.
- `학습 계획` 카드: 목표 시험일(기본은 다음 공식 시험일)과 주당 시간
- 주차별 카드
- `주차 목표를 일정에 추가`: 주마다 첫날에 `학업` 일정으로 넣는다.

동의 항목은 `AiConsentFeature.certificateStudyPlan`이다.
