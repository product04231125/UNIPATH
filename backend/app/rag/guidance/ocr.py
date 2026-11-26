"""Optional local macOS OCR for image-only pages in a collected university snapshot."""

import json
import re
import subprocess
import tempfile
from pathlib import Path

from .collect import DATA, write_json
from .university import save_source


def enrich(output=DATA):
    import pdfplumber

    path = output / "university.json"
    data = json.loads(path.read_text())
    targets = []
    for record in data["regulations"]:
        for attachment in record["attachments"]:
            missing = [
                p
                for p in attachment["pages"]
                if p["extraction_status"] != "ocr_unreviewed" and len(p["text"].strip()) < 150
            ]
            if not missing:
                continue
            with pdfplumber.open(output / attachment["source_file"]) as pdf:
                for page in missing:
                    original = pdf.pages[page["page"] - 1]
                    image_area = sum(im["width"] * im["height"] for im in original.images)
                    if (
                        re.search(r"[가-힣]", page["text"])
                        and image_area < original.width * original.height * 0.15
                    ):
                        continue
                    page["extracted_text"] = page["text"]
                    image = original.to_image(resolution=300).original
                    import io

                    buffer = io.BytesIO()
                    image.convert("RGB").save(buffer, format="JPEG", quality=90)
                    asset = save_source(buffer.getvalue(), ".jpg", output)
                    page["image"] = asset
                    targets.append((str((output / asset["source_file"]).resolve()), page))
    if not targets:
        print("No image-only pages require OCR")
        return
    with tempfile.TemporaryDirectory(prefix="unipath-ocr-") as temporary:
        temp = Path(temporary)
        write_json(temp / "input.json", [t[0] for t in targets])
        subprocess.run(
            ["swiftc", str(Path(__file__).with_suffix(".swift")), "-o", str(temp / "ocr")],
            check=True,
            timeout=120,
        )
        subprocess.run(
            [str(temp / "ocr"), str(temp / "input.json"), str(temp / "result.json")],
            check=True,
            timeout=300,
        )
        results = json.loads((temp / "result.json").read_text())
    for (_, page), result in zip(targets, results, strict=True):
        page["ocr_lines"] = result["lines"]
        page["text"] = "\n".join(line["text"] for line in result["lines"])
        page["extraction_status"] = "ocr_unreviewed" if page["text"] else "needs_visual_review"
        page["tables"] = []  # Do not pretend OCR line ordering reconstructs a table.
    data["coverage"]["ocr_pages"] = sum(
        p["extraction_status"] == "ocr_unreviewed"
        for r in data["regulations"]
        for a in r["attachments"]
        for p in a["pages"]
    )
    write_json(path, data)
    print(f"OCR processed {len(targets)} pages")


if __name__ == "__main__":
    enrich()
