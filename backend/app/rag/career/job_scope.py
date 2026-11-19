"""Conservative title gate; a workplace or a generic computer skill is not an occupation."""

import re


def title_matches(title, keywords):
    identity = re.sub(r"\s+", "", title.casefold())
    aliases = {
        "프론트엔드": (
            "프론트엔드",
            "프론트앤드",
            "frontend",
            "front-end",
            "웹개발",
            "웹프로그래머",
            "풀스택",
            "fullstack",
            "full-stack",
        ),
        "백엔드": (
            "백엔드",
            "벡엔드",
            "backend",
            "back-end",
            "서버개발",
            "웹개발",
            "웹프로그래머",
            "풀스택",
            "fullstack",
            "full-stack",
        ),
        "전산실": (
            "전산실",
            "전산담당",
            "전산관리",
            "전산직",
            "전산운영",
            "전산직원",
            "정보통신기술자",
            "시스템관리",
            "시스템운영",
            "네트워크관리",
            "네트워크엔지니어",
            "정보시스템",
            "it운영",
            "it관리",
        ),
    }
    for keyword in keywords:
        term = re.sub(r"\s+", "", keyword.casefold())
        if any(word in identity for word in aliases.get(term, (term,))):
            if term == "전산실" and any(
                x in identity
                for x in (
                    "냉난방",
                    "항온항습",
                    "공조",
                    "전기공사",
                    "공사지원",
                    "케이블공사",
                    "약국",
                    "자료입력",
                )
            ):
                continue
            return True
    return False


def occupation_matches(posting, keywords):
    return title_matches(posting.title, keywords)
