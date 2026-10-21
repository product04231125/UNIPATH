# 앱 통합·빌드·다운로드·서버 배포

팀 담당은 **신우철: RAG**, **이어진: 백엔드·팀 변경 통합·빌드·릴리스·서버 배포**,
**홍요아: 프론트엔드·UX**다. 기능 담당자가 자신의 변경과 테스트를 PR로 공유하면
이어진이 팀 브랜치의 변경을 통합하고 공통 검증 후 빌드한다.
`main` 대상 PR과 승격은 이어진의 명시적인 요청이 있을 때만 진행한다. 일반 개발·통합은
`develop`에서 검증하며 개발용 릴리스와 Staging을 갱신한다.

## 채널과 다운로드

| 구분 | 브랜치 | API·웹 주소 | GitHub 릴리스 | 용도 |
|---|---|---|---|---|
| 개발용 | `develop` | `https://staging-unipath.duckdns.org` | `dev-*`, prerelease | 팀 통합·검증 |
| 배포용 프리뷰 | `main` | `https://unipath.duckdns.org` | `v0.1.0-preview.*`, prerelease | 현재 기능 시연 |
| 실제 운영 | 검증한 `main` 커밋 | 검증한 HTTPS 운영 주소 | `v0.1.0` 등 | 인증·API·운영 준비 완료 후 |

`unipath.dcukdns.org`는 DNS가 없으며 실제 등록된 주소는 `unipath.duckdns.org`다.
두 도메인의 A 레코드는 이 서버의 공인 IP `168.138.45.63`을 가리켜야 한다.

[GitHub Releases](https://github.com/product04231125/UNIPATH/releases)에서 필요한
채널의 릴리스를 선택하고 **Assets**에서 ZIP을 받는다. 소스 코드 자동 ZIP과
빌드한 앱 ZIP은 구분한다. 실행 파일이 실제로 첨부됐는지 릴리스 설명을 확인한다.

- Windows: `*-windows.zip` 전체를 압축 해제한 뒤 `university_path_frontend.exe`를
  실행한다. EXE만 복사하지 말고 DLL 및 `data/`를 함께 보관한다. x64 대상이며
  Visual C++ 런타임 DLL도 포함한다. 코드 서명·설치 프로그램은 아직 구성하지 않았다.
- Web: `*-web.zip`을 빌드 정보의 API 주소와 같은 HTTPS 출처에 배포한다.
  웹 서버는 정적 파일과 API 프록시를 제공하고 화면 경로에는 `index.html` SPA fallback을
  설정한다. `python -m http.server 3000`으로 정적 화면을 미리 볼 수 있으나 localhost
  미리보기에서 원격 API의 세션 로그인은 지원하지 않는다. 로컬 인증 개발은 로컬 API와
  허용된 localhost Origin을 함께 사용한다.
- ZIP 내부의 `DOWNLOAD-README.txt`와 `build-info.json`에는 채널, API 주소,
  소스 커밋, SDK 및 버전이 기록된다. 첨부된 `.zip.sha256`으로 무결성을 확인한다.
  GitHub 릴리스 설명의 기능 안내 링크는 해당 빌드의 소스 커밋에 고정한다. 채널마다
  기능과 저장 범위가 다르므로 게시 스크립트에 별도 기능 설명을 중복 작성하지 않는다.

두 채널은 동일한 코드와 잠금 의존성을 **Release 모드**로 빌드한다. 개발용은
Debug 바이너리를 배포한다는 뜻이 아니다. 빌드별 API 주소와 채널·프리뷰 표시로 구분한다.

develop의 인증·역할·학교 전체 범위·학업 프로필·일정은 실제 API/DB다. 개인 기록·구성·지원 문서도 실제 서버 저장이며 기기 원본은 범위를 확인하고 동의 후 별도로 이전한다.
개인 계산 이력도 서버에 저장하며 동의 이전 후에도 기기 원본은 유지한다. 화면·채팅 창 설정은
기기 저장이다. ZIP의 `DOWNLOAD-README.txt`도 이 저장 범위를 안내한다.
개인 서버 저장이 연결된 일부 이전 개발 ZIP에는 기기 로컬 저장이라는 오래된 문구가 남아
있었다. 해당 문구는 실제 서버 저장을 설명하지 못하므로 소스 커밋의 기능 문서와 릴리스의
저장 안내 정정을 확인한다.
main은 명시적 승격 전 이전 프리뷰를 유지한다. 실제 PDF는 검토 대기이며
LLM 생성기는 미연결이다. 학교 검토 자료의 공식 졸업요건 감사는 API·타입까지 제공하며
제출·검토·감사 화면과 실제 학교 자료 등록은 후속이다. 배포 채널과 HTTPS 제공이 운영 기능 완성을
뜻하지 않으므로 초기 앱은 프리뷰로 발행한다. Staging과 Production DB는 분리한다.

## 이어진의 수동 빌드·릴리스

SDK는 `frontend/.flutter-version`의 Flutter 3.47.6으로 고정한다. Windows 빌드는
Windows의 Visual Studio **Desktop development with C++** 워크로드와 Python 3.12
이상이 필요하다. Web만 빌드할 때는 Linux에서도 가능하다. 공식 릴리스 메타데이터
접근이 불가하면 공식 Git 태그 `3.47.6`을 clone하고 `bin/`을 PATH에 넣어 사용한다.

팀 변경을 병합·커밋하고 작업 트리가 깨끗한 상태에서 저장소 루트에서 실행한다.
개인 에이전트 설정·`.env`·DB 데이터·생성 코퍼스는 다운로드 ZIP에 포함하지 않는다.

```powershell
git switch develop
git pull --ff-only
cd frontend
flutter pub get --enforce-lockfile
flutter analyze
flutter test
cd ..
python -m unittest discover -s scripts/tests -v
docker compose --profile test run --build --rm test

python scripts/build_app.py --channel develop --target all --api-base-url https://staging-unipath.duckdns.org
python scripts/build_app.py --channel product --target all --api-base-url https://unipath.duckdns.org --preview
```

배포용은 통합 검증한 `main` 커밋에서 빌드한다. `--target web` 또는 `--target windows`로
한 플랫폼만 빌드할 수도 있다. API URL은 `/api/v1`이 없는 HTTP(S) 원점이어야 하며
토큰·비밀값을 넣지 않는다. 실제 운영 빌드는 `--preview` 없이 빌드하며 HTTPS를 요구한다.
소스·버전·API 설정이 바뀌면 이전 ZIP은 `dist/채널/previous/`에 보존하고 현재 릴리스
파일과 분리한다. 같은 소스·설정의 Windows와 Web은 함께 묶어 게시한다.

```powershell
# GitHub CLI 로그인에는 repo 권한이 필요하다. 태그는 각 빌드 소스 커밋을 가리킨다.
python scripts/publish_app.py --assets-dir dist/develop --tag dev-소스커밋앞8자리
python scripts/publish_app.py --assets-dir dist/product --tag v0.1.0-preview.소스커밋앞8자리
```

게시 스크립트는 기본적으로 Windows·Web이 모두 있어야 실행되며 체크섬과 커밋·설정의
일치를 검증한다. Windows 대기 중 웹만 제공할 때는 `--allow-web-only`를 명시하며
릴리스에 Windows 파일이 없다고 표시한다. 서로 다른 커밋의 파일은 합치지 않는다.

## GitHub Actions 실행

워크플로는 [app-release.yaml](../.github/workflows/app-release.yaml)로 활성화했다.
기본 브랜치 `main`의 **Actions → App downloads → Run workflow**에서 채널을 선택한다.
`develop` 푸시는 개발용, `main` 푸시는 배포용 프리뷰를 검증·빌드·릴리스한다. 수동 실행은
두 채널을 함께 선택할 수도 있고 API URL을 지정할 수도 있다. 앱 다운로드 워크플로가
서버 컨테이너를 자동 배포하지는 않는다.

```bash
# 동일한 소스 커밋에서 두 채널의 Web·Windows를 검증·빌드·릴리스
# 셸에서 사용하는 공개 설정이며 비밀값이 아니다.
gh workflow run app-release.yaml --ref main -f channel=both -f product_preview=true
```

repository variables `DEVELOP_API_BASE_URL`, `PRODUCT_API_BASE_URL`은 각각 위 두
HTTPS 도메인으로 설정했다. 워크플로 기본값도 동일하다. 실제 운영 전환은
`product_preview=false`를 명시한 수동 실행에서만 가능하다. 검증 실패나 한 플랫폼
빌드 실패 시 릴리스를 발행하지 않는다. 출력은 Actions Artifacts와 GitHub Releases에
저장하며 ZIP에는 SDK나 소스 코드·`.env`를 넣지 않는다.

[backend-ci.yaml](../.github/workflows/backend-ci.yaml)은 백엔드 변경 PR 및
`main`/`develop` 푸시에 공통 환경을 검증한다. 워크플로 파일 수정·푸시에는 GitHub
연결의 `workflow` 권한이 필요하다. 개인 에이전트 설정은 계속 Git에서 제외한다.

## 이 서버의 도메인 배포

공통 게이트웨이(`/opt/gateway`)가 80·443을 소유한다. UNIPATH Web 컨테이너는 외부
`pawmaru-edge` 네트워크에 연결하고, API·DB는 환경별 내부 네트워크에 둔다. DB·API의
호스트 포트는 loopback에서만 연다. 다른 프로젝트의 게이트웨이 라우팅은 보존한다.

로컬 전용 `.env.staging`, `.env.production`은 서로 다른 비밀번호를 사용하고 권한을
`600`으로 둔다. 다음 공개 설정을 넣고 `POSTGRES_PASSWORD`는 각각 별도로 생성한다.
실제 `.env` 파일은 커밋하지 않는다.

| 설정 | `.env.staging` | `.env.production` |
|---|---|---|
| `APP_ENV` | `staging` | `production` |
| `APP_CHANNEL` | `develop` | `product` |
| `WEB_NETWORK_ALIAS` | `unipath-staging-web` | `unipath-product-web` |
| `API_PORT` | `8012` | `8013` |
| `POSTGRES_PORT` | `5434` | `5435` |
| `POSTGRES_DB` | `unipath_staging` | `unipath_product` |
| `POSTGRES_USER` | `unipath_staging` | `unipath_product` |

`CORS_ORIGINS`에는 해당 HTTPS 도메인을 넣는다. 원격 API의 Strict 세션 쿠키는
localhost에서의 로그인을 허용하지 않는다. localhost Origin을 추가하는 것만으로
지원되지 않으며 로컬 인증 개발에는 로컬 API를 사용한다. 실제 운영 전환 시 허용 주소를
운영 프론트엔드 원점으로 제한한다. JSONL 파일 코퍼스는
`APP_ENV=local` 전용이므로 이 두 환경에서는 `compose.rag.yaml`을 함께 사용하지 않는다.
현재 공식 승인 코퍼스가 없으므로 학교 질의의 근거 부족 안내가 정상이다.

두 채널 Web 빌드 후 다음 명령으로 분리된 프로젝트·볼륨에서 실행한다.

```bash
docker compose -p unipath-staging --env-file .env.staging -f compose.yaml -f compose.server.yaml up --build --wait
docker compose -p unipath-product --env-file .env.production -f compose.yaml -f compose.server.yaml up --build --wait
```

현재 공통 게이트웨이는 `default.conf`를 파일 단위로 bind mount한다. 기존 내용에
[`unipath-http.conf`](../deploy/gateway/unipath-http.conf) 내용을 추가한 뒤 `nginx -t`
검증과 reload를 수행한다. A 레코드가 올바른 IP로 반영되면 공통 Certbot webroot로
두 도메인을 묶은 인증서를 발급한다.

```bash
docker run --rm \
  -v /opt/gateway/letsencrypt:/etc/letsencrypt \
  -v /opt/gateway/certbot/www:/var/www/certbot \
  certbot/certbot:latest certonly --webroot -w /var/www/certbot \
  --cert-name unipath.duckdns.org \
  -d staging-unipath.duckdns.org -d unipath.duckdns.org \
  --non-interactive --agree-tos --register-unsafely-without-email
```

발급 성공 후 UNIPATH HTTP 블록을
[`unipath-https.conf`](../deploy/gateway/unipath-https.conf)로 교체하고 `nginx -t`와 reload를
수행한다. 기존 Certbot 갱신 타이머가 이 인증서도 갱신한다. DNS·인증서 검증 전에는
HTTPS 개통 완료로 간주하지 않는다. SPA 화면 경로와 API readiness·학교 질의를
두 도메인에서 확인한다. 배포 실패 시 게이트웨이 설정의 작업 전 백업으로 되돌리며
DB 볼륨은 삭제하지 않는다.

스테이징 바깥 게이트웨이의 요청 한도는 2 MiB다. 앱 프록시는 로그인 16 KiB·일반 관리자
64 KiB·개인 자료/문서/규칙 256 KiB·개인 일괄 이전 2 MiB처럼 경로별로 더 작게 제한한다.
바깥 게이트웨이까지 이전의 16 KiB로 두면 큰 요청이 앱 검증에 도달하지 못한다. 스테이징
게이트웨이 또는 앱 프록시의 크기 초과는 공통 JSON 413·request ID·no-store로 응답한다.
프로덕션 템플릿은 별도
승격 전까지 기존 한도/라우팅을 유지한다.

`python3 backend/scripts/smoke_gateway_proxy.py`는 고유 라벨의 임시 네트워크와 합성 HTTP
upstream·앱 Nginx·게이트웨이 Nginx를 생성해 두 단계 프록시를 검증한다. 실제 DB·사용자·
기존 게이트웨이는 사용하지 않는다. TLS 템플릿은 같은 staging server 블록의 인증서/listen만
로컬 HTTP로 바꿔 검사하며 실제 배포 후 HTTPS 검사도 필요하다. 이 검증은 Backend CI와
앱 릴리스 공통 검증에 포함한다. 임시 자원은 소유 라벨 확인 후 종료 시 정리한다.
