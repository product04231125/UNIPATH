"""Readable, deterministic PDF paths; hashes continue to identify immutable content."""

import re
import unicodedata


def component(value):
    text = unicodedata.normalize("NFC", str(value))
    text = re.sub(r'[\\/:*?"<>|\x00-\x1f]', "_", text)
    text = re.sub(r"\s+", " ", text).strip(" .")
    return text[:65] or "미분류"


def pdf_path(group, category, title, identifier, sha):
    filename = f"{component(title)}__{component(identifier)}__{sha[:12]}.pdf"
    return f"sources/{component(group)}/{component(category)}/{filename}"
