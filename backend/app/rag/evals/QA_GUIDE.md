# 독립 QA 및 원문 검토 안내

2026-10-25, develop 535cd69 기준. 자동화 도구는 모두 RAG 내부이며 서버 변경·모델 호출·승인을 하지 않는다.

## 홍요아 님이 할 일

1. 개발용 questions.jsonl/scope_questions.jsonl의 표현을 복사하지 않고 PDF 원문에서 새 질문을 만든다.
2. AI 답변을 보기 전에 질문, 학교·학과·연도·이수경로, 기대 답변의 숫자/조건, 근거 문서·페이지·정확한 발췌를 기록한다.
3. 정상 답변 외에 근거 없음, 연도 충돌, 조건 누락, 졸업 판정 질문을 포함한다.
4. 별도 검토자가 원문과 기대 답을 대조한 뒤 reviewed를 true로 바꾼다. holdout은 작성자와 검토자 이름이 달라야 한다. 이름만으로 독립성을 인증하는 것은 아니다.
5. 실제 답변에서 숫자·조건·예외·출처·부정 표현을 사람이 확인하고, 오답 사유를 별도로 기록한다.

QA는 공식 문서 승인이 아니다. 기대 답이 잘못됐을 수도 있으므로 이견은 원문으로 재검토한다.
권장 초기 규모는 신규 20문항이며 팀 합의된 통과 기준은 아니다. holdout은 모델/프롬프트 튜닝에 사용하지 말고 평가 시점에만 공개한다.

## 입력과 실행

명령은 backend/에서 실행한다. 예제는 가상 자료이며 실제 학교 기준이 아니다.
`qa-worksheet.json`을 복사하여 작성한다. 예제는 reviewed=false여서 그대로 컴파일하면 실패한다.
source_versions의 해시는 원문 판본을 고정한다. DB 자료는 서버가 부여한 문서/청크 ID와 같은 판본의 코퍼스를 사용한다. 로컬 UUID를 서버 UUID로 추측해서 바꾸지 않는다.

```bash
python -m app.rag.evals.qa --worksheet /private/qa.json \
  --chunks app/rag/output/sections/chunks.jsonl --output app/rag/output/qa-cases.jsonl
python -m app.rag.evals.answers --cases app/rag/output/qa-cases.jsonl \
  --predictions /private/predictions.jsonl --chunks app/rag/output/sections/chunks.jsonl \
  --output app/rag/output/qa-result.json
```

predictions는 한 줄에 `{"id":"질문 ID","result":{...}}` 형태다. result는 기존 질의 응답이며 examples/synthetic-predictions.jsonl을 참고한다. 모든 질문 ID가 정확히 한 번 있어야 한다.
컴파일은 성공 0, 잘못된 입력/기존 출력 파일 2. 답변 평가는 전부 통과 0, 불일치 1, 잘못된 입력 2다.

required_phrases/forbidden_phrases는 정규식이 아닌 일반 문자열 목록이다.
예: `2026학년도`, `단일전공`, `36시간`. 공백 차이는 허용하고 36을 136/36.5로 잘못 일치시키지 않는다.
숫자만 맞고 조건이 틀린 답도 잡으려면 연도·이수경로·예외를 함께 기록한다.
이 검사는 단어 존재 여부다. “36시간이 아니다”처럼 부정/모순이 있는 답은 통과할 수 있어 인간 검토가 필수다. 자동 점수를 사실 정확도로 발표하지 않는다.

## 원문 대조 자료

```bash
python -m app.rag.ingestion --chunking year-sections --output-dir app/rag/output/sections
python -m app.rag.ingestion.review_pack --chunks app/rag/output/sections/chunks.jsonl \
  --output app/rag/output/review.html
```

HTML을 브라우저에서 열고 PDF 원본과 나란히 비교한다. 본문은 HTML escape하며 외부 스크립트/네트워크 자원을 사용하지 않는다. 기존 출력은 덮어쓰지 않는다.
원문 이미지가 포함되지는 않는다. 표의 행/열, 수치, 각주를 PDF와 직접 확인한다.
미확인 연도/이수경로, 출처 URL, 추출 경고, 누락/검토한 빈 페이지가 표시된다.
검토 기록은 `문서 ID / 페이지 / 청크 ID / 원문 위치 / 문제 / 수정 제안 / 검토자 / 검토일`로 별도 작성한다.
공유 자료에 개인 학생 데이터나 인증 정보를 넣지 않는다. 실제 학교 승인 플래그는 자동 변경하지 않는다.

## 현재 범위

새 DB 계약의 reviewed_blank_pages를 readiness가 반영한다. 검색기에 의해 선언 무결성을 먼저 검증하며 임의 누락 페이지를 빈 페이지로 추정하지 않는다.
실제 표의 숫자 정답은 검토 전 자동 생성하지 않는다. 합성 숫자·연도·이수경로 회귀와 사람이 작성한 QA를 연결한다.
기존 backend/scripts/import_school_knowledge.py를 재사용한다. 가져오기는 초안 등록이며 승인과 다르다.
모델 비교의 실제 호출, UUID 채팅 연결, 감사 결과의 AI 설명 API는 별도 통합 작업으로 남는다.
