"""Campus directory with a single active department and explicit future placeholders."""


def add_departments(data, nodes, payloads, paginate):
    nodes["departments"] = ("학부·학과 안내", "home", "menu")
    payloads["departments"] = {
        "message": "캠퍼스와 학과를 선택해 주세요. 현재 컴퓨터공학과 안내를 제공합니다.",
    }
    computer = data["computer"]
    source = {
        "type": "official_website",
        "source_url": computer["source_url"],
        "sha256": computer["sha256"],
        "fetched_at": computer["fetched_at"],
    }
    for campus in data["campuses"]:
        parent = f"departments:{campus['id']}"
        nodes[parent] = (campus["title"], "departments", "menu")
        payloads[parent] = {"message": f"{campus['title']}의 학과를 선택해 주세요."}
        # Put the sole enabled department first, so it is immediately visible in the first group.
        items = sorted(campus["departments"], key=lambda d: d["id"] != "DE0013")
        for department in items:
            key = f"departments:{department['id']}"
            if department["id"] != "DE0013":
                nodes[key] = (department["title"] + " · 추후 추가 예정", parent, "unavailable")
                payloads[key] = {
                    "state": "unavailable",
                    "reason": "department_content_pending",
                    "message": f"{department['title']} 안내는 추후 추가 예정입니다.",
                    "campus": campus["title"],
                    "cards": [],
                    "warnings": [],
                }
                continue
            nodes[key] = (department["title"], parent, "menu")
            warnings = ["학교 소개 페이지의 수집본입니다. 연락처와 안내 내용은 변경될 수 있습니다."]
            intro = next(s for s in computer["sections"] if s["id"] == "intro")
            payloads[key] = {
                "reason": "department_overview",
                "message": computer["tagline"],
                "campus": campus["title"],
                "fetched_at": computer["fetched_at"],
                "warnings": warnings,
                "cards": [
                    {
                        "type": "reference_text",
                        "title": intro["title"],
                        "body": intro["body"],
                        "sources": [source],
                    }
                ],
            }
            for section in computer["sections"]:
                child = f"{key}:{section['id']}"
                nodes[child] = (section["title"], key, "content")
                section_warnings = list(warnings)
                if section["id"] in {"certificates", "careers"}:
                    section_warnings.append(
                        "학과 소개에 기재된 내용이며 현재 자격 운영이나 취업을 보장하지 않습니다."
                    )
                payloads[child] = {
                    "reason": "department_section",
                    "message": section["title"],
                    "campus": campus["title"],
                    "fetched_at": computer["fetched_at"],
                    "warnings": section_warnings,
                    "cards": [
                        {
                            "type": "reference_text",
                            "title": section["title"],
                            "body": section["body"],
                            "sources": [source],
                        }
                    ],
                }
        paginate(nodes, parent)
