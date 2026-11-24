# 활동 추천 API (2026-11-24)

`POST /api/v1/me/activity-recommendations`는 목표 직무를 준비하는 데 도움이 될 외부 활동의 **종류**를 추천한다. 대상은 해커톤, 공모전, 대외활동, 인턴·일경험, 봉사, 교육·훈련, 개인·팀 프로젝트다. 각 활동에 추천 이유와 검색어, 찾을 곳을 붙이고, 고용24의 실제 인턴 모집 공고도 함께 보여 준다. 합격 가능성이나 지원 자격 판정이 아니며 항상 `official=false`다.

## 요청

```json
{
  "records": [{"kind": "experience", "record_id": "…", "expected_version": 1}],
  "regions": ["서울", "경기"],
  "academic_stage": "graduating",
  "external_processing_consent": true
}
```

- `records`: 저장된 기록 전체(공고 찾기와 같은 형식).
- `regions`: 인턴 공고를 찾을 지역. 비우면 전국에서 찾는다. 이름 목록은 [공고 찾기](../../backend/app/rag/career/DOCUMENT_RECOMMENDATIONS.md)와 같다.
- `academic_stage`: `year1`~`year4`, `graduating`, `graduate`.
- 목표 직무는 저장된 `career-goal`을 쓴다. 없으면 `needs_user_input`과 `missing_fields: ["career_goal"]`을 돌려준다.

## 처리

1. 계정에 저장된 가장 최근 목표 직무 분석 결과(`analysis_results`, `kind=gap`)에서 '준비됨'이 아닌 요건을 최대 10개 꺼낸다. 이것이 부족 요건이다. 결과가 없으면 부족 요건 없이 목표 직무와 기록만으로 추천한다.
2. 인턴 공고를 수집한다. 목표 직무의 고용24 직종 코드와 고른 지역 코드로 `인턴`을 검색한다(최대 40초). 제목에 인턴·일경험·체험형·현장실습이 들어간 공고만 최대 5건 남긴다. 공고 본문은 응답에 넣지 않는다.
3. AI를 한 번 호출한다(최대 110초). 입력은 목표 직무, 부족 요건, 개인정보를 가린 기록, 학년, 지역, 사이트 목록이다.
   - 특정 행사·주최·날짜·링크는 만들지 않고, 활동의 종류만 3~6개 추천한다.
   - 서버가 응답을 검사한다.
     - 종류는 정해진 7가지만 받는다.
     - 보완 요건은 받은 부족 요건과 정확히 같은 글만 남긴다.
     - 찾을 곳은 서버 사이트 목록에 있고 종류가 맞는 것만 남기고, 없으면 그 종류의 기본 사이트로 채운다.
     - 검색어는 3개, 기간은 1~26주로 제한한다.

## 응답(완료)

`status`, `goal`, `region_label`, `gap_basis {analyzed_at, gaps}`, `recommendations[]`, `summary`, `internships[]`, `internship_sources[]`, `sites {id: {name, url}}`, `model`, `generated_at`.

`recommendations[]`의 각 항목:

| 필드 | 내용 |
| --- | --- |
| `kind`, `kind_label` | 활동 종류와 한글 이름 |
| `title` | 할 일 |
| `reason` | 추천 이유 |
| `requirements` | 보완하는 부족 요건 |
| `keywords` | 검색어(최대 3개) |
| `sites` | 찾을 곳의 사이트 id |
| `deliverable` | 활동 후 기록할 결과 |
| `weeks` | 예상 기간(주) |

## 찾을 곳과 자동 수집

- 대외활동·공모전 사이트는 링크와 검색어만 준다.
  - 대상: 링커리어, 캠퍼스픽, 요즘것들, 씽굿, 콘테스트코리아, 위비티, 데이콘, Devpost.
  - 2026-11-24에 각 사이트 이용약관을 확인했다. 자동 접근·크롤링을 금지하거나, 사전 승낙 없는 복제·제3자 제공을 금지한다. 데이콘은 봇 차단 때문에 약관을 읽지 못했다.
  - 목록을 자동으로 가져오려면 서면 허락이나 제휴가 있어야 한다.
- 공식 API가 있는 공공 출처는 키를 발급받으면 실제 목록을 붙일 수 있다. 1365 자원봉사, 온통청년, 고용24 직업훈련, 잡알리오 체험형 인턴이 해당한다. 지금은 서버에 키가 없어 링크만 준다.
- 인턴 공고는 이미 쓰는 고용24 수집기(robots.txt 확인, 5분 캐시)로 가져온다.

게이트웨이·웹 nginx는 이 경로에 180초를 허용한다.
