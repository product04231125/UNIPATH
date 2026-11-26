"""Explicit user-selected occupations; no automatic expansion of user intent."""

import re


def search_terms(value):
    terms = []
    for part in re.split(r"[,，\n]+", value):
        term = " ".join(part.split())
        term = {"벡엔드": "백엔드"}.get(term, term)
        if term and term.casefold() not in {t.casefold() for t in terms}:
            terms.append(term)
    if not 1 <= len(terms) <= 5:
        raise ValueError("검색 직무를 쉼표로 구분하여 1~5개 입력해 주세요.")
    return terms
