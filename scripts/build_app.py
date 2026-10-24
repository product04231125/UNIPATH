"""Build and package the shared Flutter app without publishing secrets or sources."""

from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
FRONTEND = ROOT / "frontend"


def validate_api_url(value: str, channel: str, preview: bool) -> str:
    parsed = urlsplit(value)
    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("API URL must be an HTTP(S) origin, without credentials or a path")
    # Also reject malformed port numbers before starting a lengthy build.
    _ = parsed.port
    try:
        ipaddress.ip_address(parsed.hostname)
    except ValueError:
        if not re.fullmatch(r"[a-zA-Z0-9.-]+", parsed.hostname):
            raise ValueError("API hostname must be an IP address or a DNS name") from None
    if channel == "product" and not preview:
        if parsed.scheme != "https":
            raise ValueError("A production build requires HTTPS; use --preview for an IP demo")
        local = parsed.hostname.lower() == "localhost"
        try:
            address = ipaddress.ip_address(parsed.hostname)
            local = local or address.is_loopback or address.is_unspecified
        except ValueError:
            pass
        if local:
            raise ValueError("A production build cannot connect to a loopback API")
    return value.rstrip("/")


def run(args: list[str], cwd: Path = FRONTEND) -> str:
    if sys.platform == "win32" and Path(args[0]).suffix.lower() in {".bat", ".cmd"}:
        args = [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", *args]
    result = subprocess.run(args, cwd=cwd, check=True, text=True, stdout=subprocess.PIPE)
    print(result.stdout, end="", flush=True)
    return result.stdout


def copy_windows_runtime(bundle: Path) -> None:
    """Include app-local MSVC runtime DLLs, as recommended by Flutter's Windows guide."""
    required = {"msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"}
    if all((bundle / name).is_file() for name in required):
        return
    vswhere = Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / (
        "Microsoft Visual Studio/Installer/vswhere.exe"
    )
    installation = run(
        [str(vswhere), "-latest", "-products", "*", "-property", "installationPath"]
    ).strip()
    crt_dirs = sorted(
        (Path(installation) / "VC/Redist/MSVC").glob("*/x64/Microsoft.VC*.CRT"),
        reverse=True,
    )
    for directory in crt_dirs:
        if all((directory / name).is_file() for name in required):
            for dll in directory.glob("*.dll"):
                shutil.copy2(dll, bundle / dll.name)
            return
    raise RuntimeError("Install the Visual Studio C++ x64 redistributable build tools")


def package_bundle(bundle: Path, archive: Path) -> None:
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as output:
        for file in sorted(bundle.rglob("*")):
            if file.is_file():
                output.write(file, file.relative_to(bundle).as_posix())


def archive_previous_builds(output: Path, signature: dict) -> None:
    """Keep prior downloads, while ensuring the current release contains one source/config."""
    manifests = list(output.glob("unipath-*.json"))
    for manifest in manifests:
        try:
            previous = json.loads(manifest.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            previous = {}
        if any(previous.get(key) != value for key, value in signature.items()):
            history = output / "previous" / datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
            history.mkdir(parents=True)
            for file in output.glob("unipath-*"):
                if file.is_file() and file.name.endswith((".zip", ".zip.sha256", ".json")):
                    shutil.move(file, history / file.name)
            print(f"Preserved previous release files in {history}", flush=True)
            return


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--channel", choices=["develop", "product"], required=True)
    parser.add_argument("--target", choices=["windows", "web", "all"], required=True)
    parser.add_argument("--api-base-url", required=True)
    parser.add_argument("--preview", action="store_true", help="Product demo, not live production")
    parser.add_argument("--version", default="0.1.0")
    parser.add_argument("--build-number", type=int, default=1)
    parser.add_argument("--flutter", default="flutter")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version) or args.build_number < 1:
        parser.error("Use a three-part version and a positive build number")
    if args.preview and args.channel != "product":
        parser.error("--preview is for product; develop is always a preview channel")
    try:
        api_url = validate_api_url(args.api_base_url, args.channel, args.preview)
    except ValueError as error:
        parser.error(str(error))
    targets = ["windows", "web"] if args.target == "all" else [args.target]
    if "windows" in targets and sys.platform != "win32":
        parser.error(
            "Windows binaries must be built on Windows with the Visual Studio C++ workload"
        )
    flutter = shutil.which(args.flutter)
    if not flutter:
        parser.error("Flutter was not found; install the version in frontend/.flutter-version")
    if run(["git", "status", "--porcelain", "--untracked-files=normal"], ROOT).strip():
        parser.error("Commit project changes before building so downloads identify an exact commit")
    commit = run(["git", "rev-parse", "HEAD"], ROOT).strip()
    sdk = json.loads(run([flutter, "--version", "--machine"]))
    expected_sdk = (FRONTEND / ".flutter-version").read_text().strip()
    if sdk["frameworkVersion"] != expected_sdk:
        parser.error(f"Use Flutter {expected_sdk}; found {sdk['frameworkVersion']}")
    run([flutter, "pub", "get", "--enforce-lockfile"])
    output = ROOT / "dist" / args.channel
    output.mkdir(parents=True, exist_ok=True)
    signature = {
        "channel": args.channel,
        "preview": args.preview or args.channel == "develop",
        "version": args.version,
        "build_number": args.build_number,
        "commit": commit,
        "flutter_version": expected_sdk,
        "api_base_url": api_url,
        "build_mode": "release",
    }
    archive_previous_builds(output, signature)
    for target in targets:
        command = [flutter, "build", target, "--release", "--no-pub"]
        if target == "web":
            command.append("--no-wasm-dry-run")
        command.extend(
            [
                f"--build-name={args.version}",
                f"--build-number={args.build_number}",
                f"--dart-define=API_BASE_URL={api_url}",
            ]
        )
        run(command)
        built = FRONTEND / "build" / ("web" if target == "web" else "windows/x64/runner/Release")
        if target == "windows" and not (built / "university_path_frontend.exe").is_file():
            raise RuntimeError("The Windows x64 executable is missing from the build output")
        if target == "web" and not (built / "index.html").is_file():
            raise RuntimeError("The web entry point is missing from the build output")
        bundle = output / target
        if bundle.exists():
            shutil.rmtree(bundle)
        shutil.copytree(built, bundle)
        if target == "windows":
            copy_windows_runtime(bundle)
        manifest = {**signature, "target": target}
        (bundle / "build-info.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        instructions = (
            "ZIP 전체를 압축 해제한 뒤 university_path_frontend.exe를 실행하세요.\n"
            "data 폴더와 DLL을 함께 보관하세요. Flutter SDK 설치는 필요하지 않습니다.\n"
            if target == "windows"
            else "웹 인증은 빌드 정보의 API 주소와 같은 HTTPS 출처에 배포해 사용하세요.\n"
            "배포 서버에는 화면 경로를 index.html로 돌려주는 SPA 설정이 필요합니다.\n"
            "정적 화면만 미리 볼 때는 python -m http.server 3000으로 실행하고\n"
            "http://localhost:3000을 여세요. 원격 API의 세션 로그인은 "
            "이 미리보기에서 지원하지 않습니다.\n"
        )
        (bundle / "DOWNLOAD-README.txt").write_text(
            f"UniversityPath · {args.channel} · {args.version}\n"
            f"소스 커밋: {commit}\nAPI 주소: {api_url}\n\n{instructions}\n"
            "로그인·가입·역할은 서버 API/DB를 사용합니다.\n"
            "실제 계정의 학업 프로필·일정·개인 기록·구성·지원 문서·"
            "개인 계산 이력은 서버에 저장합니다.\n"
            "기존 기기 자료는 자동 업로드·삭제하지 않으며 별도 동의 후 서버로 이전합니다.\n"
            "동의 이전 뒤에도 기기 원본은 유지하고, 화면·채팅 창 설정은 기기에 저장합니다.\n"
            "대상 API 서버에도 같은 버전의 인증 기능과 DB 마이그레이션이 필요합니다.\n"
            "학교 자료는 관리자 검토·등록이 필요하며 LLM은 미연결입니다.\n"
            "공식 졸업요건 감사 API를 제공하고 제출·검토·감사 화면 연결은 후속입니다.\n"
            + (
                "이 파일은 프리뷰이며 실제 운영 서비스 배포를 의미하지 않습니다.\n"
                if manifest["preview"]
                else ""
            ),
            encoding="utf-8",
        )
        preview_label = "-preview" if args.channel == "product" and args.preview else ""
        name = f"unipath-{args.channel}{preview_label}-{args.version}-{commit[:8]}-{target}"
        archive = output / f"{name}.zip"
        package_bundle(bundle, archive)
        with archive.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        (output / f"{name}.zip.sha256").write_text(f"{digest}  {archive.name}\n", encoding="ascii")
        (output / f"{name}.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"Packaged: {archive}", flush=True)


if __name__ == "__main__":
    main()
