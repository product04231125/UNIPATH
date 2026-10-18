"""Publish validated app ZIPs to GitHub Releases using the existing gh login."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

REPO = "product04231125/UNIPATH"


def gh(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["gh", *args, "--repo", REPO], text=True, capture_output=True, check=check
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets-dir", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument(
        "--allow-web-only", action="store_true", help="Explicitly disclose missing Windows build"
    )
    args = parser.parse_args()
    if not re.fullmatch(r"(?:dev-|v)[A-Za-z0-9._-]+", args.tag):
        parser.error("Use a dev-* or v* release tag")
    archives = sorted(args.assets_dir.glob("*.zip"))
    manifests = []
    assets = []
    for archive in archives:
        manifest_path = archive.with_suffix(".json")
        checksum_path = archive.with_suffix(".zip.sha256")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        with archive.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        if checksum_path.read_text().strip() != f"{digest}  {archive.name}":
            parser.error(f"Checksum mismatch: {archive.name}")
        with zipfile.ZipFile(archive) as zipped:
            if json.loads(zipped.read("build-info.json")) != manifest:
                parser.error(f"Build manifest mismatch: {archive.name}")
        manifests.append(manifest)
        assets.extend([str(archive), str(manifest_path), str(checksum_path)])
    if not manifests:
        parser.error("No packaged app ZIPs were found")
    first = manifests[0]
    for manifest in manifests:
        for key in ("commit", "channel", "version", "build_number", "api_base_url", "preview"):
            if manifest[key] != first[key]:
                parser.error(f"Do not mix different {key} values in one release")
    targets = {manifest["target"] for manifest in manifests}
    if targets != {"web", "windows"} and not (args.allow_web_only and targets == {"web"}):
        parser.error("Both Windows and web ZIPs are required (or explicitly use --allow-web-only)")
    if first["channel"] == "develop" and not args.tag.startswith("dev-"):
        parser.error("Develop builds use dev-* tags")
    if first["channel"] == "product" and not args.tag.startswith("v"):
        parser.error("Product builds use v* tags")
    if first["preview"] and first["channel"] == "product" and "-preview." not in args.tag:
        parser.error("Product preview tags must contain -preview.")
    title = "개발용" if first["channel"] == "develop" else "배포용"
    if first["preview"]:
        title += " 프리뷰"
    notes = (
        f"UniversityPath {title} · {first['version']}\n\n"
        "통합·빌드·릴리스 담당: 이어진\n"
        "프론트엔드: 홍요아 · 백엔드: 이어진 · RAG: 신우철\n\n"
        f"소스 커밋: `{first['commit']}`\n\nAPI 주소: `{first['api_base_url']}`\n\n"
        "다운로드: Windows는 `*-windows.zip` 전체를 압축 해제한 뒤 EXE를 실행합니다. "
        "웹은 `*-web.zip`을 빌드 정보의 API 주소와 같은 HTTPS 출처에 배포합니다. "
        "localhost의 정적 화면 미리보기에서는 원격 API의 세션 로그인을 지원하지 않습니다. "
        "Flutter SDK는 다운로드한 앱을 실행할 때 필요하지 않습니다.\n\n"
        "ZIP에는 실행 안내·빌드 정보가 있고 `.sha256`으로 무결성을 확인합니다.\n\n"
        "로그인·가입·역할은 서버 API/DB를 사용하며 개인 기록은 계정별 기기 로컬 저장입니다. "
        "대상 API 서버에도 같은 버전의 인증 기능과 DB 마이그레이션이 필요합니다. "
        "학교 SSO는 후속입니다. PDF는 검토 대기이며 "
        "LLM 생성기와 공식 졸업감사는 연결하지 않았습니다.\n"
    )
    if first["preview"]:
        notes += "\n이 릴리스는 프리뷰입니다. 실제 운영 서비스 전환을 의미하지 않습니다.\n"
    if targets == {"web"}:
        notes += (
            "\n**현재 웹 ZIP만 제공합니다. "
            "Windows 빌드는 GitHub workflow 권한 복구 후 추가합니다.**\n"
        )
    existing = gh("release", "view", args.tag, "--json", "tagName", check=False)
    if existing.returncode == 0:
        # Refuse to overwrite assets of an unrelated build that happens to use this tag.
        result = subprocess.run(
            ["gh", "api", f"repos/{REPO}/commits/{args.tag}", "--jq", ".sha"],
            text=True,
            capture_output=True,
            check=True,
        )
        if result.stdout.strip() != first["commit"]:
            parser.error("The existing release tag points to another source commit")
    with tempfile.TemporaryDirectory() as temporary:
        notes_path = Path(temporary) / "release-notes.md"
        notes_path.write_text(notes, encoding="utf-8")
        if existing.returncode == 0:
            gh("release", "upload", args.tag, *assets, "--clobber")
            result = gh("release", "edit", args.tag, "--notes-file", str(notes_path))
        else:
            command = [
                "release",
                "create",
                args.tag,
                *assets,
                "--target",
                first["commit"],
                "--title",
                f"UniversityPath {title} · {args.tag}",
                "--notes-file",
                str(notes_path),
                "--latest=false",
            ]
            if first["preview"]:
                command.append("--prerelease")
            result = gh(*command)
        print(result.stdout)


if __name__ == "__main__":
    main()
