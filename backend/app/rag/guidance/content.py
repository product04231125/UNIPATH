"""Local, versioned source content for clickable reference guidance, never eligibility."""

import json
from calendar import monthrange
from datetime import UTC, date, datetime
from functools import lru_cache
from pathlib import Path

from .department_content import add_departments
from .university_content import add_university

DATA = Path(__file__).with_name("data")
PAGE_SIZE = 12
REGULATION_NOTICE = "첨부 문서 기준입니다. 현재 유효성·개인 적용 여부는 별도 확인이 필요합니다."
TABLE_NOTICE = "표·서식은 읽기 순서가 다를 수 있습니다. 페이지별 표를 확인해 주세요."


def _source(doc, page=None):
    return {
        "type": "provided_pdf",
        "document_id": doc["id"],
        "title": doc["title"],
        "page": page,
        "sha256": doc["sha256"],
        "filename": doc["original_filename"],
    }


def _paginate(nodes, parent):
    children = [key for key, value in nodes.items() if value[1] == parent]
    if len(children) <= PAGE_SIZE:
        return
    for start in range(0, len(children), PAGE_SIZE):
        key = f"{parent}:list:{start // PAGE_SIZE + 1}"
        nodes[key] = (f"항목 {start + 1}–{min(start + PAGE_SIZE, len(children))}", parent, "menu")
        for child in children[start : start + PAGE_SIZE]:
            title, _, mode = nodes[child]
            nodes[child] = (title, key, mode)


@lru_cache(maxsize=4)
def _build(signature):
    nodes = {
        "calendar": ("학사일정", "home", "menu"),
        "regulations": ("학사관련규정", "home", "menu"),
    }
    payloads = {
        "calendar": {"message": "조회할 연도와 월을 선택하면 수집된 학사일정을 안내합니다."},
        "regulations": {
            "message": "읽을 규정을 선택해 주세요. 학부·대학원 규정은 구분해 안내합니다."
        },
    }
    for name, _mtime, _size in signature:
        data = json.loads((DATA / name).read_text(encoding="utf-8"))
        if name == "departments.json":
            add_departments(data, nodes, payloads, _paginate)
        elif name == "university.json":
            add_university(data, nodes, payloads, _paginate)
        elif name.startswith("calendar-"):
            year = data["year"]
            year_id = f"calendar:{year}"
            nodes[year_id] = (f"{year}년", "calendar", "menu")
            source = {
                "type": "official_calendar",
                "source_url": data["source_url"],
                "fetched_at": data["fetched_at"],
                "sha256": data["sha256"],
            }
            for month in range(1, 13):
                key = f"{year_id}:{month:02d}"
                nodes[key] = (f"{month}월", year_id, "content")
                first, last = date(year, month, 1), date(year, month, monthrange(year, month)[1])
                rows, seen = [], set()
                for event in data["events"]:
                    if date.fromisoformat(event["start_date"]) > last:
                        continue
                    if date.fromisoformat(event["end_date"]) < first:
                        continue
                    identity = (event["title"], event["start_date"], event["end_date"])
                    if identity in seen:
                        continue
                    seen.add(identity)
                    rows.append(
                        {
                            "type": "calendar_event",
                            "title": event["title"],
                            # Extra explanation only; title and date_text carry the rest.
                            "body": event.get("description", ""),
                            "start_date": event["start_date"],
                            "end_date": event["end_date"],
                            "date_text": event["date_text"],
                            "sources": [source],
                        }
                    )
                rows.sort(key=lambda row: (row["start_date"], row["end_date"], row["title"]))
                payloads[key] = {
                    "reason": "calendar_snapshot",
                    "cards": rows,
                    "message": f"{year}년 {month}월 학사일정 {len(rows)}건입니다."
                    if rows
                    else "수집한 페이지에 해당 월 일정이 없습니다. 일정 미등록일 수 있습니다.",
                    "fetched_at": data["fetched_at"],
                    "warnings": ["수집 시점의 게시 일정이며 이후 변경될 수 있습니다."],
                }
        elif name == "regulations.json":
            for doc in data["documents"]:
                key = f"regulations:{doc['id']}"
                nodes[key] = (doc["title"], "regulations", "menu")
                notice = (
                    f"{doc['scope']} 규정 · 제공된 PDF {doc['page_count']}쪽 기준입니다. "
                    "개인에게 적용되는 시행일·입학연도·예외를 자동 판정하지 않습니다."
                )
                payloads[key] = {
                    "message": notice + " 아래에서 장 또는 항목을 선택해 주세요.",
                    "source": _source(doc),
                    "scope": doc["scope"],
                }
                for section in doc["sections"]:
                    section_id = f"{key}:{section['id']}"
                    nodes[section_id] = (section["title"], key, "menu")
                    payloads[section_id] = {
                        "message": "읽을 조항 또는 세부 항목을 선택해 주세요.",
                        "scope": doc["scope"],
                    }
                    for item in section["items"]:
                        item_id = f"{section_id}:{item['id']}"
                        nodes[item_id] = (item["title"], section_id, "content")
                        payloads[item_id] = {
                            "reason": "regulation_excerpt",
                            "message": notice,
                            "scope": doc["scope"],
                            "warnings": [
                                REGULATION_NOTICE,
                                TABLE_NOTICE,
                            ],
                            "cards": [
                                {
                                    "type": "regulation_excerpt",
                                    "title": item["title"],
                                    "body": part["text"].rstrip(),
                                    "sources": [_source(doc, part["page"])],
                                }
                                for part in item["parts"]
                            ],
                        }
                    _paginate(nodes, section_id)
                page_root = f"{key}:pages"
                nodes[page_root] = ("전체 페이지·별표·서식 보기", key, "menu")
                for page in doc["pages"]:
                    page_id = f"{page_root}:{page['page']}"
                    nodes[page_id] = (f"{page['page']}쪽", page_root, "content")
                    payloads[page_id] = {
                        "reason": "regulation_page",
                        "message": notice,
                        "scope": doc["scope"],
                        "warnings": [
                            "병합 셀은 null일 수 있습니다. 공란을 0이나 면제로 해석하지 마세요."
                        ],
                        "cards": [
                            {
                                "type": "regulation_page",
                                "title": f"{doc['title']} {page['page']}쪽",
                                "body": page["text"],
                                "tables": page["tables"],
                                "sources": [_source(doc, page["page"])],
                            }
                        ],
                    }
                _paginate(nodes, page_root)
                _paginate(nodes, key)
    for root in ("calendar", "regulations"):
        if not any(value[1] == root for value in nodes.values()):
            payloads[root].update(
                state="unavailable",
                reason="source_not_imported",
                message="안내 자료를 아직 수집하지 못했습니다.",
            )
    return nodes, payloads


def bundle():
    files = sorted(
        [
            *DATA.glob("calendar-*.json"),
            *DATA.glob("regulations.json"),
            *DATA.glob("university.json"),
            *DATA.glob("departments.json"),
        ]
    )
    signature = tuple((p.name, p.stat().st_mtime_ns, p.stat().st_size) for p in files)
    return _build(signature)


def payload(node_id):
    from copy import deepcopy

    result = deepcopy(bundle()[1].get(node_id, {}))
    if "fetched_at" in result:
        age = datetime.now(UTC) - datetime.fromisoformat(result["fetched_at"])
        result["snapshot_stale"] = age.days >= 7
        if result["snapshot_stale"]:
            result.setdefault("warnings", []).insert(
                0, "수집 후 7일 이상 지난 자료입니다. 최신 수집이 필요합니다."
            )
    return result
