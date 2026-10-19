# UniversityPath 프론트엔드

Flutter Web/Windows 팀 작업에 학교 질의 API 연동을 추가했다. 기능 경계와 실행 상태는
[프론트엔드 문서](../docs/frontend/README.md)를 따른다. 인증·관리자 학사 화면은 실제 서버와
연결했다. 개인 화면은 계정별 로컬 저장이며 채팅은 질문과 확인한 학교 문맥만 전송한다.
개인 자료·카탈로그·[개인 계산](../docs/api/personal-evaluations.md)의 typed 전송 adapter는
준비됐으며 개인 화면의 서버 저장·계산 버튼 연결은 후속이다. 공식 졸업감사는 미연결이다.
학교 문서 검토·UUID 문맥 검색에도 Pydantic 생성 DTO와 `school_knowledge_api.dart`를
제공한다. [계약](../docs/api/school-knowledge.md)을 따르며 새 검토/검색 화면 연결은 후속이다.
공식 실행 규칙·자격증 마스터의 타입과 전송 adapter는 `rule_program_models.dart`·
`rule_program_api.dart`에 있다. 조건은 닫힌 타입으로 구분하며 규칙 선택을 졸업 판정으로
표시하지 않는다. [실행 규칙 계약](../docs/api/rule-programs.md)의 화면 연결은 후속이다.

## 로컬 실행

프로젝트의 Dart 요구 버전은 `^3.13.4`다. 이 변경은 Flutter 3.47.6 / Dart 3.13.5로 검증했다.
백엔드 학교 질의 구현을 함께 포함한다. 저장소 루트에서 `.env.example`을 참고해 `.env`와
로컬 DB 비밀번호를 설정하고 API를 8010에서 실행한다. 기본 Compose와 PDF 추출을 포함하는
Compose 모두 학교 질의를 지원한다. [백엔드 실행 문서](../backend/README.md)를 따른다.

```bash
docker compose -f compose.yaml -f compose.rag.yaml up --build -d
```

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-port 3000 --dart-define=API_BASE_URL=http://127.0.0.1:8010
```

Windows에서도 같은 설정을 사용한다.

```powershell
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8010
```

`API_BASE_URL`은 API의 HTTP(S) 원점 주소다. 기본값은 `http://127.0.0.1:8010`이며
실행/빌드 때 주입한다. `.env`를 브라우저에 복사하거나 토큰·API 키를 여기에 넣지 않는다.
다른 PC에서는 `127.0.0.1`이 그 PC를 가리키므로 접근 가능한 API 주소와 백엔드 바인딩을
설정해야 한다. Web 주소 `http://localhost:3000`은 기본 CORS 허용 주소에 포함되어 있다.
다른 원점은 백엔드 `CORS_ORIGINS`에 추가한다.

AI 도우미를 열고 `학교 질의 정보 입력`을 확인한 뒤 질문한다. 현재 실제 PDF는 검토 대기이며
LLM 생성기가 없으므로 `공식 근거 부족` 안내가 정상이다. 학교·학과 누락은 추가 입력을,
졸업 가능 여부는 별도 졸업감사가 필요함을 안내한다. 대화는 현재 창에서만 유지한다.

## 검증

```bash
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:8010
dart run tool/smoke_assistant_api.dart
```

마지막 명령은 실제 로컬 API가 실행 중이어야 한다. API 주소를 바꾸면
`dart -DAPI_BASE_URL=http://서버주소:포트 run tool/smoke_assistant_api.dart`로 실행한다.
테스트의 승인 문서·답변은 합성 자료이며 실제 PDF 승인을 의미하지 않는다.
Windows 네이티브 창/빌드는 Windows 개발 환경에서 별도로 확인한다.

## 개발용·배포용 다운로드

팀 변경 통합과 앱 빌드·릴리스는 **이어진**이 담당한다. Flutter 화면·UX 담당은
**홍요아**, RAG 담당은 **신우철**이다. [Releases](https://github.com/product04231125/UNIPATH/releases)와
[빌드·배포 절차](../docs/releases.md)를 따른다. `frontend/.flutter-version`으로 SDK를 고정한다.

```powershell
# 저장소 루트에서 실행. Windows에는 Python 3.12와 Visual Studio C++ 도구가 필요하다.
python scripts/build_app.py --channel develop --target all --api-base-url https://staging-unipath.duckdns.org
python scripts/build_app.py --channel product --target all --api-base-url https://unipath.duckdns.org --preview
```

출력은 `dist/develop/`, `dist/product/`다. 두 채널 모두 Release 모드로 빌드한다.
`develop`은 개발·통합용, `product --preview`는 현재 기능으로 시연하는 배포용 프리뷰다.
운영 전환 시 인증·API·데이터 검증을 마친 뒤 `--preview`를 제거한다.
