"""Server-side, editable Word paragraphs/tables. Never execute model markup or load URLs."""

from io import BytesIO

from .contracts import Draft, ExportProfile

MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"


def export_docx(draft, profile, *, document_type, reviewed=False):
    """Render the owner's edited draft without another LLM call.

    The hosting API must authenticate ownership and validate its export request separately.
    No claimed evidence verification is attached to user edits. No tracking/protection/macros.
    """
    if reviewed is not True:
        raise ValueError("Review the draft before export")
    if document_type not in {"cover_letter", "portfolio"}:
        raise ValueError("Unknown document type")
    draft, profile = Draft.model_validate(draft), ExportProfile.model_validate(profile)
    # Optional dependency: normal application startup does not require python-docx.
    from docx import Document
    from docx.enum.table import WD_ALIGN_VERTICAL, WD_TABLE_ALIGNMENT
    from docx.oxml import OxmlElement
    from docx.oxml.ns import qn
    from docx.shared import Inches, Pt, RGBColor

    document = Document()
    page = document.sections[0]
    page.page_width, page.page_height = Inches(8.5), Inches(11)
    page.top_margin = page.bottom_margin = Inches(0.7)
    page.left_margin = page.right_margin = Inches(0.8)
    for name, size in [("Normal", 10.5), ("Title", 24), ("Subtitle", 11), ("Heading 1", 14)]:
        style = document.styles[name]
        style.font.name = "Pretendard"
        style.font.size = Pt(size)
        style.font.color.rgb = RGBColor(0, 0, 0)
        fonts = style.element.get_or_add_rPr().get_or_add_rFonts()
        for key in list(fonts.attrib):
            del fonts.attrib[key]
        for key in ("ascii", "hAnsi", "eastAsia", "cs"):
            fonts.set(qn(f"w:{key}"), "Pretendard")
        style.paragraph_format.space_after = Pt(8)
        style.paragraph_format.line_spacing = 1.3
    document.styles["Heading 1"].paragraph_format.space_before = Pt(16)
    document.styles["Heading 1"].paragraph_format.keep_with_next = True
    for border in document.styles.element.xpath(".//w:pBdr"):
        border.getparent().remove(border)
    title = "자기소개서" if document_type == "cover_letter" else "포트폴리오"
    document.add_paragraph(f"{profile.name} {title}", "Title")
    contacts = [v for v in [profile.email, profile.phone, profile.link] if v]
    if contacts:
        document.add_paragraph("  |  ".join(contacts), "Subtitle")

    def table(rows):
        tbl = document.add_table(rows=1, cols=2)
        tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
        tbl.autofit = False
        tbl.columns[0].width, tbl.columns[1].width = Inches(1.25), Inches(5.65)
        props = tbl._tbl.tblPr
        borders = OxmlElement("w:tblBorders")
        for side in ["top", "left", "bottom", "right", "insideH", "insideV"]:
            edge = OxmlElement(f"w:{side}")
            for key, value in [("val", "single"), ("sz", "4"), ("color", "D9D9D9")]:
                edge.set(qn(f"w:{key}"), value)
            borders.append(edge)
        props.append(borders)
        margins = OxmlElement("w:tblCellMar")
        for side in ["top", "left", "bottom", "right"]:
            edge = OxmlElement(f"w:{side}")
            edge.set(qn("w:w"), "100")
            edge.set(qn("w:type"), "dxa")
            margins.append(edge)
        props.append(margins)
        header = OxmlElement("w:tblHeader")
        tbl.rows[0]._tr.get_or_add_trPr().append(header)
        data = [("항목", "내용"), *[(r.label, r.text) for r in rows]]
        for index, values in enumerate(data):
            cells = tbl.rows[0].cells if index == 0 else tbl.add_row().cells
            cells[0].width, cells[1].width = Inches(1.25), Inches(5.65)
            for cell, value in zip(cells, values, strict=True):
                cell.text = value
                cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
                shade = OxmlElement("w:shd")
                shade.set(qn("w:fill"), "E4EDF5" if index == 0 else "FFFFFF")
                cell._tc.get_or_add_tcPr().append(shade)
                for paragraph in cell.paragraphs:
                    paragraph.paragraph_format.space_after = Pt(4)
                    paragraph.paragraph_format.space_before = Pt(4)
                    if index == 0:
                        for run in paragraph.runs:
                            run.bold = True
        document.add_paragraph().paragraph_format.space_after = Pt(0)

    for section in draft.sections:
        document.add_heading(section.heading, level=1)
        if section.facts:
            table(section.facts)
        for paragraph in section.paragraphs:
            p = document.add_paragraph(paragraph.text)
            p.paragraph_format.widow_control = True
    document.core_properties.author = ""
    document.core_properties.last_modified_by = ""
    document.core_properties.title = title
    document.core_properties.comments = ""
    buffer = BytesIO()
    document.save(buffer)
    return buffer.getvalue()
