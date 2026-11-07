"""Remove direct identifiers before selected records leave this service.

This is a pattern filter, not proof of anonymity: other people's names and free-form
descriptions can still identify someone, so the student's explicit consent stays required.
"""

import re

from app.schemas.personalization import PersonalizationContext

MAX_TEXT = 8000
PATTERNS = (
    (re.compile(r"(?i)\b(?:https?://|www\.)[^\s<>\"']+"), "[링크]"),
    (re.compile(r"(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}"), "[이메일]"),
    (re.compile(r"(?<!\d)\d{6}[-\s]?[1-4]\d{6}(?!\d)"), "[주민등록번호]"),
    (
        re.compile(r"(?<!\d)(?:\+?82[-.\s]?)?0?1[016789][-.\s]?\d{3,4}[-.\s]?\d{4}(?!\d)"),
        "[연락처]",
    ),
    (re.compile(r"(?<!\d)0\d{1,2}[-.\s]\d{3,4}[-.\s]\d{4}(?!\d)"), "[연락처]"),
    (
        re.compile(r"(?i)(학번|student\s*(?:id|no\.?|number))(\s*[:：]?\s*)[a-z0-9-]{4,}"),
        r"\1\2[학번]",
    ),
)


def redact_text(text: str, *, names: tuple[str, ...] = ()) -> str:
    result = text
    for pattern, replacement in PATTERNS:
        result = pattern.sub(replacement, result)
    # A one-character name would also erase ordinary words.
    for name in sorted({value.strip() for value in names}, key=len, reverse=True):
        if len(name) >= 2:
            result = result.replace(name, "[이름]")
    return result


def redact_context(context: PersonalizationContext, identity) -> PersonalizationContext:
    names = (identity.user.display_name,)
    records = []
    for record in context.records:
        text = redact_text(record.text, names=names)
        records.append(
            record.model_copy(
                update={
                    "title": redact_text(record.title, names=names),
                    "text": text[:MAX_TEXT],
                    "truncated": record.truncated or len(text) > MAX_TEXT,
                }
            )
        )
    return context.model_copy(update={"records": records})
