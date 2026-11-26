"""Server-side A4 PDF of the owner's edited draft. Same content as the Word export, no model call.

Korean text needs an embedded TrueType font; the backend image installs Nanum Gothic
(`fonts-nanum`, SIL Open Font License). Pretendard ships as CFF OpenType, which ReportLab cannot
embed. Model or user text is escaped and never interpreted as markup.
"""

from io import BytesIO
from pathlib import Path
from xml.sax.saxutils import escape

from .contracts import EditedDocument, ExportProfile

MIME = "application/pdf"
FONT_DIRS = (Path("/usr/share/fonts/truetype/nanum"),)
REGULAR, BOLD = "NanumGothic", "NanumGothicBold"


class FontUnavailable(RuntimeError):
    pass


def font_files():
    for directory in FONT_DIRS:
        regular, bold = directory / f"{REGULAR}.ttf", directory / f"{BOLD}.ttf"
        if regular.is_file() and bold.is_file():
            return regular, bold
    raise FontUnavailable("Korean PDF font is not installed")


def _register():
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    if REGULAR in pdfmetrics.getRegisteredFontNames():
        return
    regular, bold = font_files()
    pdfmetrics.registerFont(TTFont(REGULAR, str(regular)))
    pdfmetrics.registerFont(TTFont(BOLD, str(bold)))
    pdfmetrics.registerFontFamily(REGULAR, normal=REGULAR, bold=BOLD)


def _text(value):
    # Escape markup, keep the owner's line breaks.
    return escape(value).replace("\n", "<br/>")


def export_pdf(draft, profile, *, document_type, reviewed=False):
    """Render the reviewed draft. The hosting API authenticates ownership separately."""
    if reviewed is not True:
        raise ValueError("Review the draft before export")
    if document_type not in {"cover_letter", "portfolio"}:
        raise ValueError("Unknown document type")
    draft = EditedDocument.model_validate(draft)
    profile = ExportProfile.model_validate(profile)
    _register()
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.platypus import (
        KeepTogether,
        Paragraph,
        SimpleDocTemplate,
        Spacer,
        Table,
        TableStyle,
    )

    title = "자기소개서" if document_type == "cover_letter" else "포트폴리오"
    body = ParagraphStyle("body", fontName=REGULAR, fontSize=10.5, leading=17, spaceAfter=7)
    styles = {
        "title": ParagraphStyle("title", fontName=BOLD, fontSize=20, leading=26, spaceAfter=4),
        "contact": ParagraphStyle(
            "contact",
            fontName=REGULAR,
            fontSize=9,
            leading=13,
            textColor=colors.HexColor("#555555"),
        ),
        "heading": ParagraphStyle(
            "heading", fontName=BOLD, fontSize=13, leading=18, spaceBefore=12, spaceAfter=6
        ),
        "cell": ParagraphStyle("cell", fontName=REGULAR, fontSize=9.5, leading=14),
        "head": ParagraphStyle("head", fontName=BOLD, fontSize=9.5, leading=14),
    }
    story = [Paragraph(_text(f"{profile.name} {title}"), styles["title"])]
    contacts = [v for v in (profile.email, profile.phone, profile.link) if v]
    if contacts:
        story.append(Paragraph(_text("  |  ".join(contacts)), styles["contact"]))
    story.append(Spacer(1, 6 * mm))
    width = A4[0] - 40 * mm
    for section in draft.sections:
        parts = [Paragraph(_text(section.heading), styles["heading"])]
        if section.facts:
            rows = [[Paragraph("항목", styles["head"]), Paragraph("내용", styles["head"])]] + [
                [
                    Paragraph(_text(f.label), styles["cell"]),
                    Paragraph(_text(f.text), styles["cell"]),
                ]
                for f in section.facts
            ]
            table = Table(rows, colWidths=[32 * mm, width - 32 * mm], repeatRows=1)
            table.setStyle(
                TableStyle(
                    [
                        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#D9D9D9")),
                        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E4EDF5")),
                        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                        ("TOPPADDING", (0, 0), (-1, -1), 4),
                        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                    ]
                )
            )
            parts += [table, Spacer(1, 3 * mm)]
        paragraphs = [Paragraph(_text(p.text), body) for p in section.paragraphs]
        # Keep a heading with its first block so it never ends a page alone.
        story.append(KeepTogether(parts + paragraphs[:1]))
        story.extend(paragraphs[1:])
    buffer = BytesIO()
    SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=20 * mm,
        rightMargin=20 * mm,
        topMargin=18 * mm,
        bottomMargin=18 * mm,
        title=title,
        author="",
        creator="",
        producer="",
    ).build(story)
    return buffer.getvalue()
