# 학생 학사 기준·진행 상황 API

관리자가 게시한 한 줄 요건·학점표·인증 요건을 해당 학생에게 전달한다.
기존 인증·학업 프로필·개인 기록·학교 과목·졸업 감사·개인 계산 계약은 유지한다.
학교 공식 승인과 특수 학사정책 자동 판정은 이 API에 포함하지 않는다.

## 저장과 소유권

`0018_student_academic`은 기존 schema에 7개 테이블만 추가한다.

| 테이블 | 역할 |
| --- | --- |
| student_academic_workspaces | 학생 소유 전체 연결 version·현재 activation |
| student_academic_contexts | 학교·주/추가 전공·경로·적용 입학연도·교육과정 개정 |
| student_academic_activations | 확인 당시 문맥·선택 지문·시각, 이전 적용본 보존 |
| student_academic_documents | 적용한 요건 개정 FK·대상별 필터링 본문 스냅샷 |
| student_academic_responses | 항목별 O/X/미확인·version·확인 시각·이전 응답·기록 스냅샷 |
| student_academic_course_links | 기존 수강 기록·전공·교육과정 과목 FK·확인한 결과/취득학점 |
| student_academic_receipts | 소유자+client_id별 원자적 쓰기 결과 |

기록 연결은 본인 기록인지 검증한 뒤 종류·ID·확인 당시 version·제목을 스냅샷으로 저장한다.
현재 기록 삭제 후에도 이전 연결을 보여주되 사용할 수 없음을 표시한다.
응답·activation 및 수강 연결에는 소유자 복합 FK를 둔다. 요청의 owner_id를 신뢰하지 않는다.
학생 API는 관리자 학교 권한을 개인 자료 열람 권한으로 취급하지 않는다.

## 실제 경로

모든 경로는 `/api/v1` 기준이며 인증이 필요하다. 정확한 DTO·enum·오류는 생성 OpenAPI가 기준이다.

| 메서드·경로 | 동작 |
| --- | --- |
| GET `/catalog/academic/options?institution_id=...` | 학교 학과·신규 선택 가능한 경로·모든 게시 교육과정 후보 |
| GET/PUT `/me/academic-contexts` | 주전공·추가 전공 전체 조회/교체 |
| GET `/me/academic-requirements/preview` | 후보·추가/제외/변경 개수·본문·대상·기간·교육과정 개정 안내·지문 |
| POST `/me/academic-requirements/activate` | 검토한 지문과 version으로 새 적용 이력을 원자 생성 |
| GET `/me/academic-requirements` | 현재 본문·범위·응답·연결 기록·영역 결과·사용 가능 상태 |
| PUT `/me/academic-requirements/{revision_id}/responses/{item_id}` | 한 줄/인증의 개별 기준 O/X·기록 연결 저장 |
| PUT `/me/course-records/{record_id}/academic-link` | 수강 기록과 전공의 과목 연결·이수 결과·취득학점·산입 여부 |
| GET `/me/academic-credit-progress` | 매 요청마다 현재 자료로 집계한 값·근거·연결 목록 |
| GET `/me/academic-requirements/history` | 본인의 적용 이력 목록 |
| GET `/me/academic-requirements/history/{activation_id}` | 해당 적용 당시 본문·응답, 읽기 전용 |

쓰기는 `client_id`, `expected_version`을 받는다. 처음 저장하는 응답/수강 연결은 version 0이다.
전공 저장·적용은 workspace version, 개별 응답/수강 연결은 해당 행 version을 사용한다.
응답에는 `activation_id`, 기록 참조에는 `expected_version`, 수강 연결에는
`expected_record_version`을 함께 보낸다. 적용은 `expected_digest`도 확인한다.
같은 소유자+client_id+operation+본문은 같은 결과를 반환하며 다른 본문 재사용은 409다.
권한/신원 잠금 아래 현재 계정을 재확인하고 변경과 영수증을 함께 커밋한다.

## 대상과 개정

- 기존 프로필의 학교·주학과·입학연도를 먼저 저장한다. 주전공은 주학과와 일치해야 한다.
- 한 학교 안에서 주전공 하나와 추가 전공을 명시적으로 연결한다. 전공마다 적용 입학연도를 정한다.
- 학교 분류/경로/교육과정은 ID로 연결한다. 이름·코드·기존 자유 입력을 자동 매핑하지 않는다.
- 학교 공통+학과 요건을 포함하고 공통 항목은 중복 표시하지 않는다. 문서·영역·항목·표 행 범위는 AND 상속, 절은 OR다.
- 같은 요건 계보에서도 전공별로 적용되는 가장 높은 게시 개정이 다르면 각각 가져온다.
- 현재 적용본은 새 게시만으로 바뀌지 않는다. 교육과정 새 개정도 알림만 제공하고 학생이 선택한다.
- 전환 시 문장·상위 조건·범위·기간·대상이 같은 안정 ID의 응답만 유지한다. 변경 항목은 이전 응답을 참고로 보존하고 미확인으로 전환한다.
- 철회/기간 경과 요건은 응답 저장을 차단한다. 다른 유효 요건의 저장은 유지한다.
- 프로필·전공 연결이 바뀌면 적용 문맥 불일치를 표시한다. 사용 중지된 경로는 새 선택에서 제외하되 기존 학생 연결은 유지한다.
- 유효기간은 기존 서버 방식과 같이 UTC 현재 일자를 사용한다. 학교별 시간대 정책은 추가하지 않았다.

## 응답과 학점 집계

O/X는 `true/false`, 미확인은 `null`이다. 최초에는 응답 행이 없으며 미확인으로 표시한다.
인증은 본인 자격·활동·경험·성과·수강을 여러 개 연결할 수 있다. 연결만으로 O가 되지 않는다.
기록 수정/삭제 또는 요건 변경 시 stale로 표시하고 재확인을 요구한다.
인증 영역은 유효한 하위 O/X로 모두/택1/택N을 집계한다. 미확인과 X를 구분하고
필터링 뒤 기준 개수가 부족한 택N은 확인 필요로 둔다. 면제 설명·점수표를 해석하지 않는다.

수강의 기존 completion=`recorded`와 grade 문자열은 이수를 증명하지 않는다.
별도 result=`completed/not_completed/needs_review`, earned_credits, included를 사용한다.
예정/수강 중은 제외한다. 원본 수강 version이 바뀌면 재확인 전까지 확정 산입하지 않는다.

- 학교의 분류 ID·exact/subtree·필수 여부로 열을 선택한다. 분류 개정 간에는 같은 학교의 logical_id를 대조한다.
- 산입액은 취득학점과 교육과정 인정학점 중 작은 값이며 Decimal로 계산한다.
- 소계·총계는 지정된 참조의 과목 집합을 합쳐 동일 기록을 한 집계 안에서 한 번만 센다.
- 0·빈칸·해당 없음은 보존한다. 빈 목표에는 부족 학점을 만들지 않는다.
- 재수강의 여러 산입 후보와 전공 간 중복 인정은 자동 선택하지 않는다. 불확실한 값은 확정 합계에서 빼고 참고 금액·사유를 제공한다.
- 열 매핑·수강 연결·이수 결과가 없으면 확인 필요로 구분한다. 표시 이름으로 분류를 추정하지 않는다.

기존 기록/분류/프로필·감사 이력은 변경하지 않는다. 문서 개정·개인 기록·프로필을 매번
재조회해 사용 가능 여부와 집계를 구성하므로 과거 캐시를 현재 확정 결과로 재사용하지 않는다.
