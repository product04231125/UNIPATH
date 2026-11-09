# Windows 시연 설치 묶음

현재 기능 브랜치의 화면과 로컬 학교 기준·선택 학생의 수강/OX를 별도 시연 계정으로
복사하는 전달 도구다. 개발 PC의 `unipath` 컨테이너·DB는 읽기만 하고, 받는 PC에는
`unipath-demo` Compose 프로젝트와 전용 볼륨을 만든다. 기본 앱 주소는
`http://localhost:38100`이다. 외부 AI 자격 증명·로그인 세션·원 계정 암호는 포함하지 않는다.

## 받는 사람

사용자 승인으로 현재 시연 EXE와 체크섬·사용방법은 이 브랜치의
`output/windows-demo/`에 포함돼 있다. EXE는 Git LFS로 저장한다. 다른 PC의 Git Bash:

```bash
git lfs install
git pull --ff-only
git lfs pull
./output/windows-demo/UniversityPath-Demo-Setup.exe
```

Git LFS가 없는 환경에서는 먼저 Git LFS를 설치해야 한다. 소스 ZIP 다운로드는 LFS
실제 파일을 포함한다고 가정하지 않는다. EXE 크기는 약354MiB이며 체크섬으로 확인한다.

1. `UniversityPath-Demo-Setup.exe`와 별도 SHA-256 체크섬을 전달받아 확인한다.
2. EXE의 **설치 / 실행**을 누른다. Windows x64·가상화·RAM을 확인하고 Docker/WSL이
   없으면 공식 Docker 설치 프로그램과 Windows WSL 기능을 준비한다.
3. Windows 권한 승인·Docker 설치/약관 창은 직접 처리한다. 재부팅을 요청하면 재부팅 후
   같은 EXE를 다시 실행한다. 스크립트는 자동 재부팅하거나 BIOS를 바꾸지 않는다.
4. 준비가 끝나면 브라우저가 열린다. **시연 계정 보기**에서 이 PC에서 새로 생성된
   학생·관리자 암호를 확인한다. 원래 계정으로 로그인하는 구성이 아니다.
5. **시연 종료**는 컨테이너만 멈춘다. 재실행은 수정된 시연 데이터를 보존한다.

처음 Docker/WSL 설치에는 인터넷이 필요하다. 이후 앱·API·DB 이미지는 EXE에 들어 있어
레지스트리 다운로드 없이 실행한다. AI 등 외부 연동은 별도 연결/설정이 필요하다.
8GB RAM·하드웨어 가상화가 필요하며 ARM64/Windows Server는 이 x64 묶음의 대상이 아니다.
Docker 최초 설치와 재부팅 경로는 실제 대상 PC에서 확인해야 한다.

## 만드는 사람

Windows의 Docker Linux 엔진·Flutter SDK·Git·.NET Framework C# 컴파일러가 필요하다.
제품 루트에서 다음을 실행한다. 기본 소스 컨테이너는 `unipath-api-1`이며, 수강 기록의
소유자가 여러 명이면 exporter의 `--owner`로 대상을 명시해야 한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-WindowsDemo.ps1 -Flutter D:/Project/flutter-3.47.5/bin/flutter.bat
```

출력은 `output/windows-demo/`다. 다른 출력 경로는 `-OutputDirectory`로 지정한다.
기존 출력 디렉터리를 덮어쓰지 않는다. 빌더는 읽기 전용 반복 읽기 트랜잭션으로
허용 목록의 학교 테이블과 한 학생의 수강·프로필·학업 기준·응답만 JSON으로 내보낸다.
기존 학교/과목/요건 ID와 학생 기록 ID는 유지하고 사용자 참조는 시연 계정으로 바꾼다.
계정·세션·감사/재시도 영수증·다른 개인 기록은 내보내지 않는다. 예전 요건 기록 연결은
복사하지 않는다. 기기 자료 메뉴의 PDF/설명은 별도 저장소이므로 포함하지 않는다.

수신 PC의 `%LOCALAPPDATA%/UniversityPathDemo/state`에 랜덤 DB/계정 암호를 처음 만든다.
암호는 배포 EXE와 Git에 넣지 않는다. 데이터 복원은 빈 DB에서만 한 트랜잭션으로 실행하고,
이미 같은 두 시연 계정이 있는 DB에는 다시 복원하지 않는다. 다른 계정이나 기존 자료가
있는 DB는 거절한다. 종료/재실행에는 볼륨 삭제·초기화 명령을 사용하지 않는다.

EXE는 자체 서명하지 않는다. 코드 서명이 없으므로 Windows 경고가 나올 수 있다.
체크섬은 파일 손상 확인용이며 발행자 인증을 대체하지 않는다. 이 묶음에는 선택한
학생 기록이 포함된다. 2026-11-09 사용자가 현재 EXE 그대로 공개 푸시를 명시적으로
승인했다. 원 계정 암호·세션·AI 인증 정보는 포함하지 않는다. 이후 다른 학생 데이터나
새 묶음의 공개 범위를 이 승인에서 자동 확대하지 않는다.

## 검증 범위

`backend/tests/test_demo_bundle.py`는 원본 유지·인증 데이터 제외·계정 교체·OX/소수 학점
복원·반복 실행 보존·기존 DB 거절을 격리 PostgreSQL에서 검증한다. PowerShell 파싱,
실제 데이터 선별 내보내기와 별도 시연 프로젝트 시작/로그인/재실행을 검증한다.
EXE의 `--verify-bundle`은 UI나 설치를 실행하지 않고 포함 파일을 끝까지 읽어 확인한다.
Docker가 없는 실제 새 PC에서의 UAC/WSL/재부팅·약관 UI는 개발 PC 검증과 구분한다.

2026-11-09 검증: Windows PowerShell 5.1 파싱·격리 DB 왕복 테스트·Ruff·Web release 빌드와
C# x64 컴파일을 통과했다. 실제 선별 데이터가 포함된 EXE 자원 확인, 이미지 save/load 태그,
준비 스크립트의 첫 실행, 학생/관리자 로그인, 수강·응답·학점 API, 종료/재실행 뒤 데이터 지문
보존을 확인했다. 기존 개발 API는 정상 유지됐다. 잘못된 파일 해시는 Docker 준비 전에,
원격 Docker 선택은 초기화 전에 거절됐다. 외부 이미지/DB 환경변수를 주입해도 묶음 설정을
사용하고, 다음 정상 환경의 재실행에서도 연결됐다. 검증용 프로젝트와 볼륨은 정리했다.

설치 방식의 기준은 [Docker Windows 설치 문서](https://docs.docker.com/desktop/setup/install/windows-install/)와
[Microsoft WSL 설치 문서](https://learn.microsoft.com/en-us/windows/wsl/install)다.
