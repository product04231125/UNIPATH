# 개인 기준 계산 API

`/api/v1/me/personal-evaluations`는 로그인한 본인의 저장된 개인 교육과정·규칙·기록을
결정론적인 Rule Engine으로 계산한다. 결과는 항상 `official=false`,
`label="개인 기준 계산 · 학교 공식 판정 아님"`이다. 관리자도 다른 사용자의 자료나 결과에
접근할 수 없다. 공식 졸업감사, 학교 학적 확인, RAG/LLM 호출과는 별도다.

## 경로와 수명

| 메서드·경로 | 동작 |
|---|---|
| `POST /me/personal-evaluations` | 본인 자료를 읽어 결과·조건·입력 snapshot을 원자적으로 저장, 201 |
| `GET /me/personal-evaluations` | 본인 결과 요약 목록. `curriculum_id`, `cursor`, `limit=1..100` |
| `GET /me/personal-evaluations/{id}` | 저장 당시 조건·요건별 결과·사용한 자료 버전 |
| `DELETE /me/personal-evaluations/{id}?expected_version=1` | 본인의 결과와 내부 snapshot 삭제, 204 |

목록은 `created_at DESC, id DESC`이며 상세 결과·개인 입력 snapshot을 포함하지 않는다.
다음 페이지에는 `next_cursor`를 전달한다. 다른 소유자 또는 삭제된 cursor는 404다.
결과는 version=1인 불변 이력이다. PATCH는 없으며 재계산은 새로운 POST다.
원본 교육과정·규칙·기록을 수정하거나 삭제해도 기존 결과는 바뀌지 않는다. 기록 식별자는
역사적 참조이므로 원본이 이미 삭제됐을 수 있다. 내부 snapshot은 HTTP 응답에 노출하지 않는다.

## 요청과 동시 변경

필수 필드는 `curriculum_id`, `expected_curriculum_version`이다. `as_of`는 YYYY-MM-DD이며
생략하면 서버 UTC 오늘이다. `calculations`에는 저장된 규칙의 `rule_id`, `expected_version`,
명시적 `condition`을 넣는다. 추가로 `expected_source_versions`에
`{kind, record_id, version}`을 넣어 화면에서 확인한 자료 버전을 고정할 수 있다.
실제 읽은 시점의 버전은 응답 `source_versions`에 보존한다.

변경 중에는 권한 변경·개인 자료 변경과 같은 transaction lock에서 세션을 다시 확인한다.
교육과정/규칙/지정 자료 버전이 다르면 409이며 타인·없는 참조는 404다. owner나 official을
요청으로 지정할 수 없다. 결과를 저장하기 전에 DTO·관계·계산 결과를 검증한다.

해당 교육과정의 **기준일에 활성인 모든 개인 규칙**을 포함한다. 시작일·종료일은 포함한다.
계산 조건을 생략한 활성 규칙도 결과에 남으며 `needs_review / explicit_condition_required`다.
다른 과정·비활성 규칙을 조건에 지정하면 422다. 규칙이 없으면 `not_applicable`이다.
저장된 `condition`, `required_value`, `current_value`, 상태 설명 등 자유 텍스트는 실행하지 않는다.

## 명시적 조건

| `kind` | 조건·자료 | 해석 |
|---|---|---|
| `minimum_credits` | `minimum`, 선택적 `category`, `course_record_ids` | 해당 개인 과정에 연결된 수강 기록만 사용. 목록 생략은 연결된 전체 기록, `[]`는 빈 선택. 분류는 수강 기록 기준. `recorded`의 credits만 합산하고 중복 연결은 한 번 반영 |
| `required_courses` | `courses[{curriculum_course_id, minimum_credits?, minimum_grade_points?, comparison_grade_scale?}]`, `grades[{course_record_id, points, scale}]` | 개인 과정 과목 ID로 지정. 원 성적 A+를 숫자로 환산하지 않음. 점수 기준과 척도는 함께 지정. 동일 수강 기록을 두 필수과목으로 지정하면 `ambiguous_personal_course_mapping` 확인 필요 |
| `minimum_volunteer_hours` | `minimum`, `activity_ids` | 개인 활동의 `approval`, `approved_hours`, `observed_on` 사용. 기준일 이후/없는 관찰일은 미확인, reported_hours는 합산하지 않음 |
| `any_certificate` | `certificates[{credential_id, possession, validity_known}]` | possession은 held/not_held/unknown, 기본 unknown. validity_known 기본 false. 개인 기록 만료일은 해당 날짜까지 유효. 미래 취득·만료 자격은 충족 근거가 되지 않음 |
| `thesis` | `thesis_type`, `requires_approval=true`, `accepted_grades=[]`, `records[{achievement_id, completion, approval}]` | 개인 성과에 thesis_type 필요. completion 기본 unknown, approval 기본 needs_review. 승인 조건이 있으면 기준일 이내 thesis_approved_on도 필요. 원 성적을 허용 문자열과 비교 |

모든 관찰은 사용자 본인의 참고 입력이며 기관 검증을 뜻하지 않는다. 누락 정보는 임의로
충족시키지 않는다. 선택한 각 목록은 그 조건에서 계산하려는 자료 집합이어야 한다.
수치는 유한한 음수 아닌 Decimal이며 요청/응답에서는 정밀도 보존을 위해 문자열을 사용한다.
조건 숫자의 전체 자릿수·소수 자릿수·범위는 [OpenAPI](openapi.json)의 Amount 계약을 따른다.

요건별 `status`, `reason`, `current`, `required`, `deficit`, `evidence_record_ids`와
`missing_course_ids`, `uncertain_course_ids`를 반환한다. 두 과목 ID 목록은 개인 과정 과목 ID다.
계산 불명확 시 부족량은 null일 수 있다. 전체 상태 우선순위는 확정 미충족 → 확인 필요 →
모두 충족이며 상세 정책은 [Rule Engine](../rule-engine.md)을 따른다.

```json
{
  "curriculum_id": "00000000-0000-4000-8000-000000000001",
  "expected_curriculum_version": 1,
  "client_id": "00000000-0000-4000-8000-000000000003",
  "as_of": "2026-10-19",
  "calculations": [{
    "rule_id": "00000000-0000-4000-8000-000000000002",
    "expected_version": 1,
    "condition": {"kind": "minimum_credits", "minimum": "130"}
  }]
}
```

예시 UUID는 합성 값이며 실제로 저장한 본인 자료의 서버 UUID로 바꿔야 한다.

## 재시도·제한·오류

선택적 `client_id`는 같은 소유자/자원에서 중복 생성을 막는다. 같은 키·같은 정규화 요청의
재시도는 원본이 변경·삭제됐더라도 이전 결과를 반환한다. 같은 키·다른 요청은 409다.
결과를 삭제한 뒤 같은 키로 다시 생성하면 409이며 삭제된 결과를 되살리지 않는다.
새 계산에는 새 키를 쓴다. 생략 필드와 명시한 기본값은 다른 요청 지문일 수 있으므로
재시도할 때는 원래 요청 본문을 그대로 유지한다.

- 활성 규칙/계산 조건 최대 100개, 선택한 과정 과목 최대 500개.
- 명시적 자료 참조·실제 사용 자료 버전·요건별 snapshot 연결 합계는 각각 최대 2000개.
- POST는 사용자당 15분에 60회이며 재시도도 포함한다. 프록시 요청 본문 제한은 256 KiB다.
- 중복 선택, 상충하는 같은 자료의 성적/자격/논문 관찰, 다른 과목의 성적 입력은 422다.
- 미인증/만료 401, 타인·없는 자료 404, 버전·재시도 충돌 409, 입력 오류 422, 빈도 제한 429.
  공통 오류와 no-store 정책을 사용하며 입력 원문·비밀번호·내부 DB 오류를 반환하지 않는다.

## 프론트엔드와 보관

`frontend/lib/features/api/personal_evaluation_api.dart`에 조건/결과 모델과 공통 AuthApi를
사용하는 전송 adapter가 있다. 다른 소유자·공식 표시 결과를 거부한다. 현재 개인 화면과
계산 버튼은 아직 이 API에 연결하지 않았다. 로컬 자료를 자동 업로드하지 않으며
자료 이전은 [개인 자료 API](personal.md)의 동의·ID 치환·날짜/시간 변환 계약을 따른다.

`0005_personal_evaluations`는 `personal_evaluations` 하나를 추가한다. 전체 계산 결과와
정규화된 최소 계산 입력·자료 버전을 소유자 범위로 보관한다. 실제 원문 메모·자격 번호·
질문/답변을 snapshot에 복사하지 않는다. 내부 replay 함수로 당시 입력을 재계산할 수 있으며
이는 공개 endpoint가 아니다. 삭제 시 원본 개인 기록은 유지하고 결과/snapshot만 제거한다.
