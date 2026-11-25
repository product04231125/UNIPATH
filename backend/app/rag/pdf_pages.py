"""Page images of a saved PDF for the in-app viewer. Nothing is extracted, stored or sent on.

PDFium (pypdfium2, installed with pdfplumber) is not thread safe, so every render in this
process, including OCR, takes PDFIUM_LOCK. Rendered pages are kept briefly in memory, keyed by
the file's SHA-256, so scrolling back and forth does not render the same page again.
"""

from collections import OrderedDict
from io import BytesIO
from math import isfinite
from threading import Lock

PDFIUM_LOCK = Lock()
# Wide enough to read body text at QHD; the viewer scales down for smaller windows.
PAGE_WIDTH = 1400
MAX_PIXELS = 6_000_000
# WebP cannot encode a side over 16,383 px; very long pages (receipts, web captures) stay readable.
MAX_SIDE = 8000
MAX_PAGES = 300
MEDIA_TYPE = "image/webp"

_CACHE_LOCK = Lock()
_IMAGES: OrderedDict = OrderedDict()
_SIZES: OrderedDict = OrderedDict()
IMAGE_CACHE = 48
SIZE_CACHE = 64


class PdfUnreadable(ValueError):
    """Encrypted, damaged or empty: the viewer cannot show it."""


def _cached(store, key):
    with _CACHE_LOCK:
        if key in store:
            store.move_to_end(key)
            return store[key]
    return None


def _remember(store, key, value, limit):
    with _CACHE_LOCK:
        store[key] = value
        store.move_to_end(key)
        while len(store) > limit:
            store.popitem(last=False)
    return value


def _open(data):
    import pypdfium2 as pdfium

    try:
        document = pdfium.PdfDocument(data)
    except pdfium.PdfiumError as error:
        raise PdfUnreadable("PDF를 열 수 없습니다.") from error
    if len(document) == 0:
        document.close()
        raise PdfUnreadable("쪽이 없는 PDF입니다.")
    return document


def _size(page):
    # Already turned by the page's /Rotate, matching the rendered image.
    width, height = page.get_size()
    if not all(isfinite(v) and v > 0 for v in (width, height)):
        raise PdfUnreadable("PDF 쪽 크기를 읽을 수 없습니다.")
    return width, height


def page_sizes(digest: str, load) -> tuple[int, list[tuple[float, float]]]:
    """(page count, [(width, height) in points] for the first MAX_PAGES pages)."""
    if (found := _cached(_SIZES, digest)) is not None:
        return found
    data = load()  # Read before taking the lock: no database wait while holding it.
    with PDFIUM_LOCK:
        document = _open(data)
        try:
            sizes = []
            for index in range(min(len(document), MAX_PAGES)):
                page = document[index]
                try:
                    width, height = _size(page)
                finally:
                    page.close()
                sizes.append((round(width, 1), round(height, 1)))
            result = (len(document), sizes)
        finally:
            document.close()
    return _remember(_SIZES, digest, result, SIZE_CACHE)


def page_image(digest: str, number: int, load) -> bytes:
    """Page [number] (1-based) as WebP, PAGE_WIDTH wide unless that exceeds MAX_PIXELS or MAX_SIDE.

    Raises IndexError for a page past the end (or past MAX_PAGES).
    """
    key = (digest, number)
    if (found := _cached(_IMAGES, key)) is not None:
        return found
    data = load()
    with PDFIUM_LOCK:
        document = _open(data)
        try:
            if not 1 <= number <= min(len(document), MAX_PAGES):
                raise IndexError(number)
            page = document[number - 1]
            try:
                width, height = _size(page)
                scale = min(
                    PAGE_WIDTH / width,
                    (MAX_PIXELS / (width * height)) ** 0.5,
                    MAX_SIDE / max(width, height),
                )
                bitmap = page.render(scale=scale)
                out = BytesIO()
                # Encode while the bitmap is alive: the PIL image shares its buffer.
                bitmap.to_pil().convert("RGB").save(out, "WEBP", quality=80, method=4)
            finally:
                page.close()
        finally:
            document.close()
    return _remember(_IMAGES, key, out.getvalue(), IMAGE_CACHE)
