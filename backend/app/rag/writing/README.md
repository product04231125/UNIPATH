# 편집 가능한 자기소개서와 포트폴리오

## 구현 범위

이 모듈은 선택한 개인 기록·자료를 이용해 한국어 초안을 생성하고, 사용자 검토 후
실제 Word 문단과 표로 구성한 DOCX bytes를 반환한다. `create`는 새 초안,
`improve`는 기존 본문/파일을 새로운 양식으로 재작성하고 변경 이유를 반환한다.
원본 파일·DB 기록·사용자 편집본은 자동으로 덮어쓰지 않는다.

**기존 앱에 API나 화면을 등록하지 않았다.** AI/RAG 영역만 구현했으며 아래 연결 작업은
서버·프론트 담당자가 적용해야 한다. 포트폴리오 원본의 디자인·사진을 보존하는 변환이나
Word 변경 내용 추적 기능은 아니다. 첫 버전은 본문·표를 새 템플릿으로 재구성한다.

## 구성

| 파일 | 역할 |
| --- | --- |
| `contracts.py` | 입력, 편집 가능한 초안, 수정 이유, 내보내기 프로필 계약 |
| `service.py` | 동의 검사, 문서 추출·가림, LLM 호출, 인용·원문 검증 |
| `docx_export.py` | 실제 문단·표·스타일로 DOCX 생성, 외부 통신 없음 |
| `demo.py` | 가상 데이터로 두 종류 DOCX 생성, 외부 통신 없음 |
| `__main__.py` | 실제 설정으로 생성하거나 편집 JSON을 DOCX로 내보내는 CLI |
| `examples/` | 합성 입력·응답과 JSON Schema |

## 실행과 의존성

서버 기본 잠금 파일/이미지는 변경하지 않았다. 배포 담당자는
`python-docx==1.2.0`을 backend 의존성과 잠금 파일에 추가하고 설치해야 한다.
로컬 독립 테스트는 backend 환경에서 다음 명령으로 실행한다.

```bash
pip install -r app/rag/writing/requirements-documents.txt
python -m pytest app/rag/tests/test_writing.py -q
python -m app.rag.writing.demo --output-dir /tmp/unipath-writing-samples
```

샘플의 모든 이름·활동은 가상이다. demo는 실제 LLM 결과로 표시하지 않는다.
DOCX는 보호 모드·매크로·본문 이미지화를 사용하지 않아 Word 등에서 편집할 수 있다.
Pretendard를 사용하며 서버에서 미리보기 PDF를 만들 때도 해당 글꼴이 필요하다.
기존 `frontend/assets/fonts/pretendard/`의 파일과 LICENSE를 배포 정책에 맞게 사용할 수 있다.
DOCX에 폰트는 포함하지 않으므로 사용자 기기에 없으면 대체 글꼴로 표시될 수 있다.

실제 생성은 기존 Vertex 환경변수와 ADC를 사용한다. 모델 ID를 이 모듈에서 고정하지 않는다.
CLI 입력 `request.external_processing_consent=true`는 실행자가 외부 전송을 허용했을 때만 지정한다.

```bash
python -m app.rag.writing generate \
  --input app/rag/writing/examples/create-input.json \
  --output /tmp/writing-draft.json
# 반환된 draft의 sections 안의 text를 편집한다. questions_for_user와 revisions는 검토용이다.
python -m app.rag.writing export \
  --input /tmp/writing-draft.json \
  --profile app/rag/writing/examples/export-profile.json \
  --reviewed --output /tmp/portfolio.docx
```

원문 파일 개선은 입력의 mode를 improve로 설정하고 `--file /path/original.pdf`를 사용한다.
original_text가 없으면 **파일 1개가 개선 대상 원문**이다. original_text가 있으면
첨부 파일은 보충 자료로 사용한다. `--name`은 가릴 본인 이름이며 여러 번 지정할 수 있다.
CLI는 기존 출력 경로를 덮어쓰지 않고 결과 권한을 0600으로 설정한다.

## 서버 담당자 연결

제안 경로는 `POST /me/writing-drafts`, `POST /me/writing-exports`이며 **아직 존재하는 API가 아니다.**
기존 `/me/job-analyses`를 문서 생성 용도로 변경하지 않는다.

생성 경로에서 수행할 작업:

1. 기존 CurrentIdentity로 인증하고 본인의 선택 record_id/version만 `assemble`로 조회한다.
2. 파일 합계·요청 크기·사용량을 제한하고 동의를 확인한다. 임의의 클라이언트 context를
   신뢰해 다른 사용자의 기록을 가져오지 않는다.
3. 저장 프로필 중 사용자가 선택한 학교·학과 등을 `profile_text`에 넣을 수 있다.
   이름·연락처·GitHub URL은 `ExportProfile`로 분리하고 생성 LLM에 보내지 않는다.
4. 기존 공용 모델(`request.app.state.guidance_model`)과 전역 `gemini.reserve_call`을 사용한다.
   동기 추출/생성은 기존 동기 라우트 또는 워커에서 실행하며 이벤트 루프를 막지 않는다.
5. 생성 완료 후 세션 소유권과 원본 버전을 다시 확인하고 결과를 반환한다.
   오류·시간 초과·429·검증 실패 시 초안 생성 성공으로 응답하지 않는다.

핵심 호출 예시(인증/예외 처리를 갖춘 라우트 안에서 사용):

```python
from app.rag.writing.service import generate_draft

preview = generate_draft(
    writing_request,  # WritingRequest 또는 dict
    authorized_context,  # assemble 결과, 사용자가 선택한 본인 기록
    request.app.state.guidance_model,
    files=selected_files,  # [(filename, bytes)], 저장/업로드 자동 처리 없음
    names=(identity.user.display_name,),
    profile_text=selected_profile_text,
)
```

내보내기는 사용자 수정 JSON을 Draft로 검증하고, 명시적 검토 완료 후 호출한다.
재생성/재분석 없이 실행하며 `reviewed`는 의미적 사실 검증이나 관리자 승인을 뜻하지 않는다.

```python
from fastapi import Response
from app.rag.writing.docx_export import MIME, export_docx

raw = export_docx(edited_draft, export_profile, document_type="portfolio", reviewed=True)
return Response(
    raw,
    media_type=MIME,
    headers={
        "Content-Disposition": 'attachment; filename="portfolio.docx"',
        "Cache-Control": "no-store",
    },
)
```

요청 본문 최대 크기와 예외 응답은 호스팅 API에서 설정한다. 파일명은 서버의 안전한 고정값
또는 검증된 값으로 만들고 입력값을 헤더에 그대로 삽입하지 않는다.
생성 파일을 영구 저장하려면 별도 저장 정책·소유권·삭제·만료 계약이 필요하다.
기본 구현은 메모리 bytes만 반환하고 개인 결과를 서버 로그에 기록하지 않는다.

기존 ApplicationDocument.body는 문자열이고 sources는 achievement/experience로 제한된다.
새 Draft JSON이나 파일 chunk ID를 기존 sources에 그대로 저장하면 안 된다.
우선 확정 본문을 기존 초안에 저장하는 연결과, 구조화된 초안 버전 저장을 구분해 합의한다.

## 프론트 담당자 연결

- 기존 지원 문서/포트폴리오 화면에 생성·개선 진입 버튼을 연결한다.
- 문서 종류, 목표 직무·지원처, 선택 문항, 사용할 기록·자료를 명시적으로 선택받는다.
- 초안 `sections[].paragraphs[].text`, `sections[].facts[].label/text`를 직접 수정하게 한다.
  순서를 바꾸거나 내용을 수정한 뒤 재생성 시 기존 편집본을 별도로 보존한다.
- `questions_for_user`는 문서 본문 밖에 표시하고 답변은 사용자가 확인한 새 기록이나
  수정 원문으로 반영한다. 이 질문들은 DOCX에 자동 삽입되지 않는다.
- improve의 `revisions`는 원문 인용·새 섹션(section_index)·변경 이유로 표시한다.
  전체 문자 단위 diff 또는 Word 추적 변경을 의미하지 않는다.
- 인용은 검토용 접기 영역에 제공한다. 원문과 인용의 일치는 사실 승인과 다르다.
- 사용자 편집 후의 인용은 자동으로 재검증됐다고 표시하지 않는다.
- 검토 완료 후 다운로드 API의 bytes를 DOCX로 저장한다. 기존 PDF 저장 기능의
  Web/desktop 분기를 재사용하되 MIME/확장자는 DOCX로 변경한다.
- 현재 내 자료의 보관 UI는 PDF 중심이므로 DOCX 입력 확장은 별도 UI 작업이다.

## 한도와 검증

최대 5개 파일/합계 8MiB, 추출 chunk 한도는 기존 모듈의 20개다. 기존 서버 OCR을 재사용한다.
생성 context는 기존 기록 종류 5종을 지원한다. 전체 자료는 40000자 이하이며 넘치면
조용히 생략하지 않고 다시 선택하도록 거절한다. 개선 원문은 20000자 이하,
선택 프로필은 2000자 이하이다. 초안은 최대 8개 섹션/총 본문 18000자이다.
문서 길이에 따라 페이지 수는 달라지며 1페이지 고정을 보장하지 않는다.

모든 본문/표 항목의 인용 ID·버전·원문을 검증한다. 인용을 만들지 못한 결과는 실패로
처리해 사용자 자료처럼 내보내지 않는다. 인용 검증은 의미적 함의까지 보증하지 않으므로
사용자 검토 단계가 필요하다. OCR 오인식과 원본 기록 오류도 자동으로 사실이 되지 않는다.

QA는 가상 자료로 정상 생성, 동의 없음, 인용 오류, 자료 한도, 원문 개선,
Word 재편집/재저장, 한글·표 렌더링, 긴 문서 페이지 나눔을 확인한다.
서버 모델 오류는 기존 재시도/시간 제한을 따르며 문서 생성 실패를 가짜 성공으로 바꾸지 않는다.

### 2026년 11월 23일 구현 검증

실제 Vertex `gemini-3.5-flash` / `global` / 50초 설정으로 `demo.py`의 가상 도서 대출
실습 기록을 사용했다. 자기소개서 생성 9.5초, 포트폴리오 생성 12.4초,
기존 짧은 문서 개선 17.0초로 모두 스키마·인용 검증을 통과했다. 실제 사용자 자료나
로그인/API/UI를 사용한 E2E 결과는 아니다. 운영 모델은 서버 설정을 따른다.
긴 자료·다른 직무·모델 부하에서도 같은 시간과 품질을 보장하지 않는다.

세 결과를 DOCX로 출력한 뒤 렌더링해 한글·표·줄바꿈을 확인했다. 실제 Word 설치 앱에서의
수동 편집 시험은 별도이며, 자동 테스트에서는 DOCX를 다시 읽고 문단 수정 후 재저장했다.
사용자에게 제시할 샘플도 모두 가상 자료다. 생성본과 QA 렌더링은 git 제외 경로인
`output/career-documents/`에 두었으며 소스 저장소에는 샘플 생성 코드와 JSON만 남긴다.

로컬 렌더링에서 폰트 누락이 생기면 Pretendard 경로를 포함한 fontconfig를 명시한다.
이 작업에서는 번들 LibreOffice와 외부 임시 fontconfig로 검증했다. 앱의 프론트 코드나
사용자 시스템 글꼴 설정을 변경하지 않았다.
