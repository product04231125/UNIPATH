"""Conservative title gate; a workplace or a generic computer skill is not an occupation."""

import re

# A title that teaches or trains the occupation ("프론트엔드 국비과정 전문강사", "웹개발 양성과정
# 교육생 모집") is a different job, unless the student searched for that kind of job.
TEACHING = ("강사", "튜터", "교육생", "수강생", "훈련생", "국비과정", "국비지원", "양성과정")


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
            if any(word in identity for word in TEACHING) and not any(
                word in term for word in TEACHING
            ):
                continue
            return True
    return False


def scope_matches(title, keywords, codes=()):
    """With a chosen Work24 category the category itself scopes postings, not the title words.

    Teaching or training titles stay out unless the student chose an education category (03).
    """
    if not codes:
        return title_matches(title, keywords)
    identity = re.sub(r"\s+", "", title.casefold())
    teaching = any(word in identity for word in TEACHING)
    return not teaching or any(code.startswith("03") for code in codes)


def occupation_matches(posting, keywords, codes=()):
    return scope_matches(posting.title, keywords, codes)
