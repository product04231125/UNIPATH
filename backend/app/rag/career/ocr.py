"""Server-side Korean/English OCR. OCR subprocesses receive pixels on stdin."""

import os
import subprocess
from io import BytesIO
from math import isfinite
from threading import BoundedSemaphore, Lock
from time import monotonic

from PIL import Image, ImageOps, UnidentifiedImageError

# PDFium rendering is not thread safe. Limit concurrent OCR memory and CPU separately.
_RENDER = Lock()
_SLOTS = BoundedSemaphore(2)
MAX_PIXELS = 25_000_000
IMAGE_FORMATS = {".png": "PNG", ".jpg": "JPEG", ".jpeg": "JPEG", ".webp": "WEBP"}


class OcrUnavailable(RuntimeError):
    pass


class OcrInputError(ValueError):
    pass


class DocumentOCR:
    def __init__(self):
        self.deadline = None
        self.pages = 0

    def scan(self, load_image):
        if self.deadline is None:
            self.deadline = monotonic() + 45
        self.pages += 1
        if self.pages > 20 or monotonic() >= self.deadline:
            raise OcrInputError("OCR 분량을 초과했습니다. 필요한 페이지만 올려 주세요.")
        if not _SLOTS.acquire(timeout=2):
            raise OcrUnavailable("OCR 서버가 사용 중입니다. 잠시 후 다시 시도해 주세요.")
        try:
            with load_image() as image:
                image.thumbnail((3200, 3200))
                buf = BytesIO()
                image.save(buf, format="PNG")
            remaining = self.deadline - monotonic()
            if remaining <= 0:
                raise OcrInputError("OCR 시간이 초과되었습니다. 필요한 페이지만 올려 주세요.")
            output = subprocess.run(
                ["tesseract", "stdin", "stdout", "-l", "kor+eng", "--psm", "6"],
                input=buf.getvalue(),
                capture_output=True,
                timeout=min(20, remaining),
                env={**os.environ, "OMP_THREAD_LIMIT": "1"},
            )
            if output.returncode or b"Failed loading language" in output.stderr:
                raise OcrUnavailable("서버의 한글·영문 OCR 엔진 설정을 확인해 주세요.")
            return output.stdout.decode("utf-8").strip()
        except UnidentifiedImageError as exc:
            raise OcrInputError("이미지 형식이나 파일 내용을 확인해 주세요.") from exc
        except FileNotFoundError as exc:
            raise OcrUnavailable("서버에 OCR 엔진이 설치되어 있지 않습니다.") from exc
        except subprocess.TimeoutExpired as exc:
            raise OcrInputError("OCR 시간이 초과되었습니다. 필요한 페이지만 올려 주세요.") from exc
        finally:
            _SLOTS.release()


def upload_image(raw, suffix):
    with Image.open(BytesIO(raw), formats=[IMAGE_FORMATS[suffix]]) as image:
        if image.width * image.height > MAX_PIXELS or getattr(image, "n_frames", 1) != 1:
            raise OcrInputError("이미지는 2,500만 화소 이하의 단일 사진으로 올려 주세요.")
        upright = ImageOps.exif_transpose(image).convert("RGBA")
        background = Image.new("RGB", upright.size, "white")
        background.paste(upright, mask=upright.getchannel("A"))
        return background


def pdf_image(page):
    # Bound physical render size BEFORE allocating the bitmap (also for unusual page sizes).
    left, top, right, bottom = map(float, page.mediabox)
    width, height = right - left, bottom - top
    if not all(isfinite(v) and v > 0 for v in (width, height)):
        raise OcrInputError("PDF 페이지 크기를 읽을 수 없습니다.")
    dpi = min(240, 3200 * 72 / max(width, height))
    with _RENDER:
        return page.to_image(resolution=dpi, antialias=True, force_mediabox=True).original
