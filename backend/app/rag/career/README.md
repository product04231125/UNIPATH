# 취업 공고 검색·개인 근거 비교 모듈

2026-11-06. AI/RAG 내부 라이브러리이며 HTTP API나 실제 서비스 연결은 아니다.
학사 안내에는 LLM을 쓰지 않고, 이 모듈에서 취업 공고와 선택한 개인 자료를 비교한다.

## 구현 범위

- `SearchQuery`: 사용자가 직무 키워드와 지역을 직접 선택한다. 전국도 명시적으로 선택한다.
  지역별 검색은 사이트별 공식 지역 코드 매핑이 필요하다. 코드가 없으면 전국으로 대체하지 않는다.
- `Saramin`, `Work24`: 공식 API 검색 결과를 공통 공고 구조로 변환한다.
  인증키가 필요하며 기본 네트워크는 꺼져 있다. 실 API 성공 여부는 아직 검증하지 않았다.
- `JobKorea`: 승인 및 전용 주소·명세가 필요하므로 미설정 상태를 반환하는 자리만 준비했다.
  HTML 크롤러나 로그인 우회 기능은 구현하지 않았다.
- `CareerService.recommend`: 공개 검색 조건만 수집처에 전달한다. 중복·명시적 마감 공고를 제외하고,
  선택 자료의 분석은 `allow_personal_analysis=True`일 때만 실행한다.
- `EvidenceAnalyzer.analyze_profile`: 선택한 자격증·경험을 근거 인용과 함께 요약한다.
- `EvidenceAnalyzer.analyze`: 공고 요구사항과 선택 기록을 비교한다. 기존 백엔드
  `JobAnalyzer.analyze(posting_text, context)` 입력과 비교 DTO 필드에 맞는 dict 목록을 반환한다.
  백엔드는 기존대로 DTO 검증·소유권 확인·버전 재확인을 해야 한다.
- `VertexJSON`: 명시한 프로젝트·리전·Gemini 모델 ID로 JSON 응답을 요청한다.
  사용자 후보 명칭을 실제 모델 ID로 가정하지 않는다. Argon 연결은 구현하지 않았다.

## 로컬 검증

저장소 루트에서:

```sh
PYTHONPATH=backend backend/app/rag/.venv/bin/python -m app.rag.guidance career
PYTHONPATH=backend backend/app/rag/.venv/bin/python -m app.rag.guidance career:recommend
PYTHONPATH=backend backend/app/rag/.venv/bin/python -m unittest backend/app/rag/tests/test_career.py
```

테스트의 공고·개인 자료·모델 응답은 합성 데이터다. 실제 추천 결과가 아니다.
`guidance/examples/career-responses.json`은 프론트 메뉴 계약 예시다.

## 서버 담당자용 연결 예시 (현재 앱에는 연결하지 않음)

```python
import os
from app.rag.career.analyzer import EvidenceAnalyzer
from app.rag.career.contracts import SearchQuery
from app.rag.career.service import CareerService
from app.rag.career.sources import Saramin, Work24, JobKorea
from app.rag.career.transport import Transport
from app.rag.career.vertex import VertexJSON

network = Transport(allow_network=True, timeout=15)
model = VertexJSON(
    os.environ["VERTEX_PROJECT"],
    os.environ["VERTEX_LOCATION"],
    os.environ["VERTEX_MODEL"],
    transport=network,
)
analyzer = EvidenceAnalyzer(model)
service = CareerService(
    [
        Saramin(os.environ.get("SARAMIN_ACCESS_KEY"), transport=network),
        Work24(os.environ.get("WORK24_AUTH_KEY"), transport=network),
        JobKorea(),
    ],
    analyzer,
    analysis_limit=3,
)

# authenticated_context는 서버가 사용자 소유권을 검증하여 조립한 선택 자료다.
# query와 동의 여부는 사용자가 제출한 값을 서버에서 검증한 뒤 전달한다.
# query = SearchQuery(keyword, region_label, region_codes=verified_provider_codes)
# profile = analyzer.analyze_profile(authenticated_context)  # 별도 명시적 분석 요청
# result = service.recommend(query, authenticated_context, allow_personal_analysis=True)
```

Vertex는 선택 의존성 `requirements-vertex.txt`, ADC 인증, API 사용 권한이 필요하다.
키는 환경/서버 비밀 저장소에서 주입하고 로그나 클라이언트에 포함하지 않는다.
모듈이 환경 변수를 자동으로 읽거나 앱의 분석기를 자동 교체하지 않는다.

## 결과의 의미와 한계

- 공고 API는 요약 메타데이터를 제공한다. 상세 직무·우대조건·이미지 본문 전체를 얻었다고
  표시하지 않는다. `analysis_scope=metadata_only`를 함께 보여준다.
- `ranking=source_order`: 수집처 순서로 표시하며 개인 적합도 순위가 아니다.
  총 limit에 먼저 도달하는 수집처가 많을 수 있다. 기본 분석은 최대 3건이다.
- 최상위 status는 **공고 검색 상태**다. 각 item의 `analysis_status`는 별개다.
  분석 성공도 합격·자격증 진위·채용 적격성의 확정 판정이 아니다.
- `partial`은 일부 수집처 실패/미설정, `no_results`는 적어도 한 수집처 검색 성공 후
  표시할 공고가 없음, `not_available`은 성공한 수집처가 없음이다.
- 인용문·기록 ID·버전·문자 위치를 검증한다. 인용이 실제로 존재해도 LLM의 의미 해석이
  맞는지는 별도 QA가 필요하다. 같은 문구가 반복되면 아직 인용하지 않은 위치에 연결하며, 공고에 없는 문구는 거부한다.
- 마감 날짜가 불명확한 공고는 확인 필요로 표시한다. 외부 API 지연/누락도 가능하다.
- 60초 예산은 호출 사이에 확인한다. 개별 HTTP timeout/ADC 인증 시간을 포함한
  전체 실행의 강제 종료를 보장하지 않는다. 공개 서비스에는 서버 작업 취소·동시성·요금 한도가 필요하다.
- 개인 기록을 디스크에 저장하지 않는다. 선택한 원문은 LLM에 전송되므로 UI에서 범위를 확인해야 한다.
  이 라이브러리는 사용자 인증을 수행하지 않으며 외부 입력을 그대로 context로 받는 API를 만들면 안 된다.
- 포트폴리오는 현재 experience/achievement 등 텍스트 기록으로 전달할 수 있다.
  PDF 업로드·GitHub 링크 방문·포트폴리오 자동 추출은 이번 범위에 없다.

## 공식 연동 문서

- [사람인 이용 안내](https://oapi.saramin.co.kr/guide/info),
  [채용 공고 API](https://oapi.saramin.co.kr/guide/job-search)
- [고용24 Open API](https://www.work24.go.kr/cm/e/a/0110/selectOpenApiIntro.do)
- [잡코리아 API 신청](https://www.jobkorea.co.kr/service/api)
- [Vertex 모델 추론 문서](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-reference/inference)

프론트·백엔드 전달 사항은 `../guidance/CAREER_HANDOFF.md` 참고.
