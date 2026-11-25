"""PDF page images for the 내 자료 viewer; synthetic PDFs only."""

from io import BytesIO

import pypdfium2 as pdfium
import pytest
from PIL import Image

from app.rag import pdf_pages


def synthetic_pdf(*sizes, rotate_last=False):
    document = pdfium.PdfDocument.new()
    for width, height in sizes:
        page = document.new_page(width, height)
    if rotate_last:
        page.set_rotation(90)
    out = BytesIO()
    document.save(out)
    return out.getvalue()


@pytest.fixture(autouse=True)
def empty_cache():
    pdf_pages._IMAGES.clear()
    pdf_pages._SIZES.clear()


def test_sizes_follow_rotation_and_pages_render_at_viewer_width():
    data = synthetic_pdf((595, 842), (842, 595), rotate_last=True)
    count, sizes = pdf_pages.page_sizes("a", lambda: data)
    assert count == 2 and sizes == [(595.0, 842.0), (595.0, 842.0)]
    image = Image.open(BytesIO(pdf_pages.page_image("a", 2, lambda: data)))
    assert image.format == "WEBP"
    assert image.width == pdf_pages.PAGE_WIDTH and abs(image.height - 1981) <= 1
    with pytest.raises(IndexError):
        pdf_pages.page_image("a", 3, lambda: data)


def test_huge_pages_stay_under_the_pixel_cap_and_repeats_use_the_cache():
    data = synthetic_pdf((200, 14000))
    loads = []

    def load():
        loads.append(1)
        return data

    image = Image.open(BytesIO(pdf_pages.page_image("tall", 1, load)))
    assert image.width * image.height <= pdf_pages.MAX_PIXELS
    assert max(image.size) <= pdf_pages.MAX_SIDE
    pdf_pages.page_image("tall", 1, load)
    assert len(loads) == 1


@pytest.mark.parametrize("data", [b"%PDF-1.4\n% synthetic\n", b"not a pdf"])
def test_unreadable_pdfs_are_reported(data):
    with pytest.raises(pdf_pages.PdfUnreadable):
        pdf_pages.page_sizes("bad", lambda: data)
    with pytest.raises(pdf_pages.PdfUnreadable):
        pdf_pages.page_image("bad", 1, lambda: data)
