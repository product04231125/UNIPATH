"""Work24's own occupation classification (1차·2차), used as the job category a student picks.

The table is a checked-in copy of the public 상세검색 직종 tree (see data/work24_occupations.json:
source, checked_on). Work24 filters postings by these codes itself, so a category keeps unrelated
jobs out even when the detail keyword is a generic word or spelled differently from the titles.
"""

import json
import re
from functools import cache
from pathlib import Path

DATA = Path(__file__).with_name("data") / "work24_occupations.json"
CODE = re.compile(r"[0-9]{2}[0-9A-Z]?")
MAX_CODES = 10  # Work24's own picker allows up to 10 occupations.


@cache
def table():
    return json.loads(DATA.read_text(encoding="utf-8"))


@cache
def names():
    result = {}
    for top in table()["categories"]:
        result[top["code"]] = top["name"]
        for child in top["children"]:
            result[child["code"]] = child["name"]
    return result


def validate_codes(codes):
    """Return the codes as a tuple; only known 1차/2차 codes, at most 10, no duplicates."""
    values = tuple(codes)
    if len(values) > MAX_CODES or len(set(values)) != len(values):
        raise ValueError("직종은 중복 없이 최대 10개까지 고를 수 있습니다.")
    for code in values:
        if not isinstance(code, str) or not CODE.fullmatch(code) or code not in names():
            raise ValueError("목록에 있는 직종을 골라 주세요.")
    return values


def label(codes):
    return " · ".join(names()[code] for code in codes)
