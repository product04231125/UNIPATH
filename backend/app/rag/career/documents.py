"""Extract text from explicitly selected portfolio files; keep citation locations locally."""

import re
from io import BytesIO
from pathlib import Path
from uuid import uuid4
from xml.etree import ElementTree
from zipfile import ZipFile

from .ocr import IMAGE_FORMATS, DocumentOCR, OcrInputError, pdf_image, upload_image

MAX_BYTES = 8 * 1024 * 1024
WORD = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
# Some PDF fonts map the space glyph to a control character; the model would quote a real space.
CONTROL = re.compile(r"[\x00-\x08\x0e-\x1f\x7f]")


def document_parts(filename, raw, ocr):
    if not 0 < len(raw) <= MAX_BYTES:
        raise ValueError("파일은 1바이트~8MiB여야 합니다.")
    suffix = Path(filename).suffix.lower()
    if suffix == ".pdf":
        import pdfplumber

        with pdfplumber.open(BytesIO(raw)) as pdf:
            if len(pdf.pages) > 100:
                raise ValueError("분석할 PDF를 100쪽 이하로 나누어 주세요.")
            for number, page in enumerate(pdf.pages, 1):
                text = page.extract_text() or ""
                if text.strip():
                    yield f"{number}쪽", text, "text"
                else:
                    yield f"{number}쪽", ocr.scan(lambda page=page: pdf_image(page)), "ocr"
    elif suffix in IMAGE_FORMATS:
        yield "이미지", ocr.scan(lambda: upload_image(raw, suffix)), "ocr"
    elif suffix == ".docx":
        with ZipFile(BytesIO(raw)) as archive:
            info = archive.getinfo("word/document.xml")
            if info.file_size > MAX_BYTES:
                raise ValueError("DOCX 본문이 너무 큽니다.")
            root = ElementTree.fromstring(archive.read(info))
            yield (
                "본문",
                "\n".join(
                    "".join(t.text or "" for t in p.iter(WORD + "t")) for p in root.iter(WORD + "p")
                ),
                "text",
            )
    elif suffix in {".txt", ".md"}:
        yield "본문", raw.decode("utf-8-sig"), "text"
    else:
        raise ValueError(
            "PNG, JPEG, WebP, PDF, DOCX, UTF-8 TXT 또는 Markdown 파일을 선택해 주세요."
        )


def prepare_documents(files, *, names=()):
    from app.services.personalization.redaction import redact_text

    records, locations, warnings = [], {}, []
    if not 1 <= len(files) <= 20:
        raise ValueError("개인 자료를 1~20개 선택해 주세요.")
    ocr = DocumentOCR()
    for filename, raw in files:
        usable = False
        for location, original, method in document_parts(filename, raw, ocr):
            text = redact_text(CONTROL.sub(" ", original).strip(), names=names)
            if not text:
                warnings.append(f"{filename} {location}: 추출 가능한 텍스트 없음")
                continue
            if method == "ocr":
                warnings.append(f"{filename} {location}: OCR 인용은 원본과 대조해 주세요.")
            usable = True
            for offset in range(0, len(text), 8000):
                if len(records) >= 20:
                    raise ValueError(
                        "분석 용량을 초과했습니다. 관련 페이지나 문서를 선택해 주세요."
                    )
                identifier = str(uuid4())
                records.append(
                    dict(
                        kind="experience",
                        record_id=identifier,
                        version=1,
                        text=text[offset : offset + 8000],
                        truncated=False,
                    )
                )
                locations[identifier] = dict(
                    filename=filename, location=location, offset=offset, method=method
                )
        if not usable:
            raise OcrInputError(
                "문자를 읽을 수 없습니다. 선명한 이미지나 텍스트 문서를 올려 주세요."
            )
    return {"records": records}, locations, warnings
