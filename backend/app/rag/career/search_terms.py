"""Explicit user-selected occupations; no automatic expansion of user intent."""

import re

# Spellings of the same occupation, keyed without spaces. Work24 titles mostly write 프론트엔드 and
# 백엔드, so searching the standard 프런트엔드 or a typo such as 벡엔드 alone would find nothing.
SPELLINGS = {
    "벡엔드": "백엔드",
    "백앤드": "백엔드",
    "벡앤드": "백엔드",
    "백엔드": "백엔드",
    "프런트엔드": "프론트엔드",
    "프런트앤드": "프론트엔드",
    "프론트앤드": "프론트엔드",
    "프론트엔드": "프론트엔드",
}


def search_terms(value):
    terms = []
    for part in re.split(r"[,，\n]+", value):
        term = " ".join(part.split())
        term = SPELLINGS.get(term.replace(" ", ""), term)
        if term and term.casefold() not in {t.casefold() for t in terms}:
            terms.append(term)
    if not 1 <= len(terms) <= 5:
        raise ValueError("검색 직무를 쉼표로 구분하여 1~5개 입력해 주세요.")
    return terms
