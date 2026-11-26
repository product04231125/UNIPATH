"""Collect the requested Computer Engineering page; other departments stay pending."""

from datetime import UTC, datetime

from .collect import DATA, write_json

URL = "https://www.kduniv.ac.kr/kor/CMS/DeptIntro/view.do?mCode=MN299&code=DE0013"
# User-provided directory, intentionally not scraped/enabled for other departments.
CAMPUSES = [
    (
        "metropol",
        "메트로폴캠퍼스(경기도양주)",
        [
            ("DE0016", "MN300", "건설시스템공학과(토목공학과)"),
            ("DE0015", "MN288", "건축공학과"),
            ("DE0017", "MN289", "건축디자인학과"),
            ("DE0009", "MN290", "경영학과"),
            ("DE0007", "MN291", "경찰학과"),
            ("DE0046", "MN292", "국제융합학부"),
            ("DE0047", "MN387", "군사학과"),
            ("DE0018", "MN293", "디자인학과"),
            ("DE0185", "MN386", "보건행정학과"),
            ("DE0029", "MN388", "사회복지학과"),
            ("DE0014", "MN294", "소프트웨어융합보안학과(소프트웨어학과)"),
            ("DE0019", "MN295", "스포츠마케팅학과"),
            ("DE0011", "MN296", "외식사업학과"),
            ("DE0002", "MN297", "유아교육과 *사범계열"),
            ("DE0020", "MN298", "체육학과"),
            ("DE0013", "MN299", "컴퓨터공학과"),
            ("DE0010", "MN301", "항공서비스학과"),
            ("DE0008", "MN302", "행정학과"),
            ("DE0030", "MN389", "호텔관광경영학과"),
            ("DE0012", "MN303", "호텔조리학과"),
        ],
    ),
    (
        "medical",
        "메디컬캠퍼스(원주문막)",
        [
            ("DE0005", "MN304", "간호학과"),
            ("DE0023", "MN306", "물리치료학과"),
            ("DE0026", "MN309", "안경광학과"),
            ("DE0024", "MN310", "응급구조학과"),
            ("DE0025", "MN311", "임상병리학과"),
            ("DE0022", "MN312", "작업치료학과"),
            ("DE0027", "MN313", "치기공학과"),
            ("DE0021", "MN314", "치위생학과"),
        ],
    ),
    ("global", "글로벌캠퍼스(고성)", [("international", None, "국제학부")]),
]


def parse_computer(html):
    from .university import safe_url, soup

    tree = soup(html)
    root = tree.select_one(".dept-info-wrap")
    if root is None or root.select_one(".btit") is None:
        raise ValueError("Department page layout changed")
    if root.select_one(".btit").get_text(strip=True) != "컴퓨터공학과":
        raise ValueError("Unexpected department identity")

    def text(selector):
        node = tree.select_one(selector)
        if node is None or not node.get_text(strip=True):
            raise ValueError(f"Missing department field: {selector}")
        return node.get_text("\n", strip=True)

    homepage = safe_url(root.select_one(".home a")["href"])
    contact = text(".dept-info-wrap .loc") + "\n" + text(".dept-info-wrap .tel")
    sections = [
        {"id": "intro", "title": "학과 소개", "body": text(".dept-info-wrap p.comm")},
        {
            "id": "contact",
            "title": "사무실·위치·홈페이지",
            "body": contact + "\n홈페이지: " + homepage,
            "homepage_url": homepage,
        },
    ]
    features = [node.get_text(" ", strip=True) for node in tree.select(".kconts-wrap .kcont")]
    if not features:
        raise ValueError("Missing department features")
    sections.append({"id": "features", "title": "학과 특성", "body": "\n".join(features)})
    expected = {"교육목표": "goals", "졸업 후 진로": "careers", "취득자격증": "certificates"}
    for node in tree.select(".major-info-wrap > .major-sec"):
        title = node.select_one("h4.title").get_text(strip=True)
        body = node.select_one(".comm").get_text("\n", strip=True)
        if title not in expected or not body:
            raise ValueError("Unexpected department section")
        sections.append({"id": expected[title], "title": title, "body": body})
    if {s["id"] for s in sections} != {"intro", "contact", "features", *expected.values()}:
        raise ValueError("Incomplete department sections")
    return {
        "title": "컴퓨터공학과",
        "tagline": text(".dept-info-wrap p.title"),
        "sections": sections,
    }


def collect(output=DATA):
    from .university import fetch, save_source

    raw = fetch(URL)  # Exactly one enabled department; no crawl of the remaining directory.
    parsed = parse_computer(raw)
    document = {
        "id": "DE0013",
        "source_url": URL,
        **parsed,
        **save_source(raw, ".html", output),
        "fetched_at": datetime.now(UTC).isoformat(),
    }
    directory = []
    for campus_id, title, departments in CAMPUSES:
        items = []
        for code, menu, name in departments:
            url = (
                f"https://www.kduniv.ac.kr/kor/CMS/DeptIntro/view.do?mCode={menu}&code={code}"
                if menu
                else "https://global.kduniv.ac.kr/global/index.php?pCode=1466580676"
            )
            items.append(
                {
                    "id": code,
                    "title": name,
                    "reference_url": url,
                    "availability": "available" if code == "DE0013" else "content_pending",
                }
            )
        directory.append({"id": campus_id, "title": title, "departments": items})
    result = {"directory_origin": "user_provided", "campuses": directory, "computer": document}
    write_json(output / "departments.json", result)
    return result


if __name__ == "__main__":
    result = collect()
    print(f"Collected Computer Engineering: {len(result['computer']['sections'])} sections")
