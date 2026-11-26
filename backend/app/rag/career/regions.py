"""Work regions a student can pick, with each source's own region code.

Work24 codes come from its job search filter (2026-11): one search takes several codes joined by
commas, so postings are searched in the chosen regions instead of being filtered afterwards.
A source without a code for the chosen regions is skipped and reported, never searched nationwide.
"""

from typing import Literal

# Display name -> Work24 region code, in the order the app shows them.
WORK24 = {
    "서울": "11000",
    "경기": "41000",
    "인천": "28000",
    "부산": "26000",
    "대구": "27000",
    "광주·전남": "12000",
    "대전": "30000",
    "울산": "31000",
    "세종": "36110",
    "강원": "51000",
    "충북": "43000",
    "충남": "44000",
    "전북": "52000",
    "경북": "47000",
    "경남": "48000",
    "제주": "50000",
}
RegionName = Literal[
    "서울",
    "경기",
    "인천",
    "부산",
    "대구",
    "광주·전남",
    "대전",
    "울산",
    "세종",
    "강원",
    "충북",
    "충남",
    "전북",
    "경북",
    "경남",
    "제주",
]


def label(names) -> str:
    return "·".join(names)


def provider_codes(names) -> dict[str, str]:
    """Codes per source for the chosen regions; sources missing any region are left out."""
    return {"work24": ",".join(WORK24[name] for name in names)}
