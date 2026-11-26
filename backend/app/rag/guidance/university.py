"""Collect all publicly listed KDU regulations and the three scholarship pages.

Explicit offline-refresh command; never crawls during a student's menu selection.
"""

import argparse
import hashlib
import json
import re
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

from .collect import DATA, split_pages, write_json

BASE = "https://www.kduniv.ac.kr"
REGULATIONS = BASE + "/kor/CMS/RegulationBookMgr/list.do?mCode=MN191"
LIST = BASE + "/kor/ajx_json/RegulationBookMgr/ajaxRegulationList.do?mCode=MN191"
PAGES = {"MN149": "장학금 안내", "MN150": "장학금 종류", "MN151": "학자금 융자"}


def soup(html):
    from bs4 import BeautifulSoup

    return BeautifulSoup(html, "html.parser")


def norm(value):
    return re.sub(r"\s+", "", re.sub(r"<[^>]*>", "", value)).replace("‧", "·")


def safe_url(url):
    url = urljoin(BASE, url.strip())
    parsed = urlsplit(url)
    if (
        parsed.scheme not in ("http", "https")
        or parsed.hostname not in {"www.kduniv.ac.kr", "kduniv.ac.kr"}
        or parsed.username
        or parsed.password
        or parsed.port not in (None, 80, 443)
    ):
        raise ValueError("Only public KDU source URLs are collected")
    return url.replace("http://", "https://", 1)


def fetch(url, limit=40_000_000):
    request = Request(safe_url(url), headers={"User-Agent": "UNIPATH-ReferenceCollector/1.0"})
    with urlopen(request, timeout=45) as response:
        safe_url(response.url)
        raw = response.read(limit + 1)
    if len(raw) > limit:
        raise ValueError("Source exceeds download limit")
    return raw


def save_source(raw, suffix, output, *, pdf_metadata=None):
    sha = hashlib.sha256(raw).hexdigest()
    relative = f"sources/university/{sha}{suffix}"
    if suffix == ".pdf" and pdf_metadata:
        from .filenames import pdf_path

        relative = pdf_path(*pdf_metadata, sha)
    target = output / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        target.write_bytes(raw)
    return {"sha256": sha, "source_file": relative}


def parse_index(html):
    tree = soup(html)
    result, stack = [], {}
    for tag in tree.select("#CateGroupDataList [rel-data]"):
        code, level, label = tag["rel-data"].split("-", 2)
        level = int(level)
        title = tag.select_one(".is-nm").get_text(" ", strip=True)
        count = int(re.search(r"\d+", tag.select_one(".is-cnt").get_text())[0])
        parent = stack.get(level - 1)
        if level > 1 and parent is None:
            raise ValueError("Invalid regulation category hierarchy")
        result.append(
            {
                "id": code,
                "parent_id": parent,
                "title": title,
                "path": label,
                "expected_count": count,
            }
        )
        stack[level] = code
    if not result:
        raise ValueError("Regulation index layout changed")
    parents = {row["parent_id"] for row in result}
    for row in result:
        row["leaf"] = row["id"] not in parents
    return result


def parse_rules(html, categories):
    leaves = {norm(row["title"]): row for row in categories if row["leaf"]}
    if len(leaves) != sum(row["leaf"] for row in categories):
        raise ValueError("Ambiguous category titles")
    records = []
    for tr in soup(html).select("table.board-list-table tbody tr"):
        cells = tr.find_all("td", recursive=False)
        if len(cells) != 5:
            raise ValueError("Unexpected regulation row")
        title = cells[1].get_text(" ", strip=True)
        category = leaves.get(norm(title))
        if category is None:
            # The site's full listing can contain a regulation absent from its category tree.
            # Keep it visible rather than dropping it or guessing a classification.
            category = {
                "id": "unclassified-" + hashlib.sha256(title.encode()).hexdigest()[:12],
                "parent_id": None,
                "path": "전체 목록 / 분류 정보 미표시",
            }
        attachments = [
            {
                "url": safe_url(a["href"]),
                "label": a.get("title", title),
                "format_hint": a.img.get("alt", "") if a.img else "",
            }
            for a in cells[3].select("a[href]")
        ]
        records.append(
            {
                "id": category["id"],
                "title": title,
                "parent_id": category["parent_id"],
                "category_path": category["path"],
                "revision_date": cells[2].get_text(" ", strip=True),
                "listing_status": "withdrawn"
                if "폐지" in title
                else "moved"
                if "이동" in title
                else "listed",
                "attachments": attachments,
            }
        )
    ids = {row["id"] for row in records}
    if len(ids) != len(records) or not {row["id"] for row in leaves.values()} <= ids:
        raise ValueError("Missing/duplicate regulation rows; refusing partial publication")
    expected = sum(row["expected_count"] for row in categories if row["parent_id"] is None)
    if len(records) != expected:
        raise ValueError("Root category counts do not match collected rows")
    return records


def extract_pdf(path):
    import pdfplumber

    pages = []
    with pdfplumber.open(path) as pdf:
        for number, page in enumerate(pdf.pages, 1):
            text = page.extract_text() or ""
            pages.append(
                {
                    "page": number,
                    "text": text,
                    "tables": page.extract_tables(),
                    "extraction_status": "text_extracted"
                    if text.strip()
                    else "needs_visual_review",
                }
            )
            page.close()
    return pages


def parse_table(table):
    """Keep source cells + spans, and an expanded grid for accessible text cards."""
    rows, occupied, grid = [], {}, []
    for r, tr in enumerate(table.find_all("tr")):
        cells, c = [], 0
        for cell in tr.find_all(["td", "th"], recursive=False):
            while (r, c) in occupied:
                c += 1
            rs, cs = int(cell.get("rowspan", 1)), int(cell.get("colspan", 1))
            if not 1 <= rs <= 100 or not 1 <= cs <= 50:
                raise ValueError("Unsupported table span")
            text = cell.get_text(" ", strip=True)
            cells.append({"text": text, "rowspan": rs, "colspan": cs, "header": cell.name == "th"})
            for rr in range(r, r + rs):
                for cc in range(c, c + cs):
                    if (rr, cc) in occupied:
                        raise ValueError("Overlapping table cells")
                    occupied[rr, cc] = text
            c += cs
        rows.append(cells)
    width = max((c for r, c in occupied), default=-1) + 1
    for r in range(len(rows)):
        grid.append([occupied.get((r, c), "") for c in range(width)])
    return {
        "caption": table.caption.get_text(" ", strip=True) if table.caption else "",
        "rows": rows,
        "grid": grid,
    }


def parse_page(html, title):
    root = soup(html).select_one(".contents_view_wrap")
    if root is None:
        raise ValueError("Scholarship content selector changed")
    for tag in root.select("script,style"):
        tag.decompose()
    text = root.get_text("\n", strip=True)
    if not text:
        raise ValueError("Empty scholarship content")
    tables = [parse_table(table) for table in root.select("table")]
    # Preserve the full body; section cards are additional navigation, never replacements.
    sections = []
    lists = root.select(".contlist-type4 > .list")
    if lists:
        sections = [
            {
                "title": node.select_one(".title").get_text(" ", strip=True),
                "body": node.get_text("\n", strip=True),
            }
            for node in lists
        ]
    else:
        # Main h3 sections own following siblings up to the next h3 (including all nested lists).
        for heading in root.find_all("h3", recursive=False):
            parts = [heading.get_text("\n", strip=True)]
            for sibling in heading.next_siblings:
                if getattr(sibling, "name", None) == "h3":
                    break
                if getattr(sibling, "name", None):
                    parts.append(sibling.get_text("\n", strip=True))
            sections.append(
                {
                    "title": heading.get_text(" ", strip=True),
                    "body": "\n".join(p for p in parts if p),
                }
            )
    links = [
        {"title": a.get_text(" ", strip=True), "url": urljoin(BASE, a["href"])}
        for a in root.select("a[href]")
    ]
    attachments = [
        a
        for a in links
        if "downloadRun.do" in a["url"]
        or re.search(r"\.(pdf|hwp|hwpx|docx?|xlsx?|zip)(?:$|\?)", a["url"], re.I)
    ]
    return {
        "title": title,
        "body": text,
        "tables": tables,
        "sections": sections,
        "links": links,
        "attachments": attachments,
    }


def collect(output=DATA):
    stamp = datetime.now(UTC).isoformat()
    index_raw, list_raw = fetch(REGULATIONS), fetch(LIST)
    categories = parse_index(index_raw)
    records = parse_rules(list_raw, categories)
    print(f"Indexed {len(records)} regulations", flush=True)
    jobs = [
        (record["id"], i, attachment)
        for record in records
        for i, attachment in enumerate(record["attachments"])
    ]
    cache_dir = output / ".collection-cache"
    cache_dir.mkdir(parents=True, exist_ok=True)

    records_by_id = {record["id"]: record for record in records}

    def download(job):
        record_id, i, attachment = job
        cache_key = hashlib.sha256(attachment["url"].encode()).hexdigest()
        cached = cache_dir / (cache_key + ".pdf")
        # Cache belongs only to this run/retry. --fresh clears it before a new refresh.
        raw = cached.read_bytes() if cached.exists() else fetch(attachment["url"])
        if not raw.startswith(b"%PDF-"):
            raise ValueError(f"Unexpected attachment format: {record_id}")
        if not cached.exists():
            cached.write_bytes(raw)
        record = records_by_id[record_id]
        meta = save_source(
            raw,
            ".pdf",
            output,
            pdf_metadata=(
                "대학규정",
                record["category_path"].split(" > ")[0],
                record["title"],
                f"{record_id}-{i + 1:02d}",
            ),
        )
        extracted = cache_dir / (meta["sha256"] + ".json")
        pages = json.loads(extracted.read_text()) if extracted.exists() else extract_pdf(cached)
        if not extracted.exists():
            write_json(extracted, pages)
        return (
            record_id,
            i,
            {
                **attachment,
                **meta,
                "page_count": len(pages),
                "downloaded_at": datetime.fromtimestamp(cached.stat().st_mtime, UTC).isoformat(),
                "pages": pages,
                "sections": split_pages(pages, record_id),
            },
        )

    completed = {}
    with ThreadPoolExecutor(max_workers=3) as pool:
        for index, (record_id, i, result) in enumerate(pool.map(download, jobs), 1):
            completed[record_id, i] = result
            if index % 10 == 0:
                print(f"Extracted {index}/{len(jobs)} attachments", flush=True)
    for record in records:
        record["attachments"] = [
            completed[record["id"], i] for i in range(len(record["attachments"]))
        ]
    scholarships = []
    for code, title in PAGES.items():
        url = BASE + "/kor/CMS/Contents/Contents.do?mCode=" + code
        raw = fetch(url)
        page = parse_page(raw, title)
        for attachment in page["attachments"]:
            blob = fetch(attachment["url"])
            if not blob.startswith(b"%PDF-"):
                raise ValueError("New scholarship attachment needs a format adapter")
            attachment.update(
                save_source(
                    blob,
                    ".pdf",
                    output,
                    pdf_metadata=("장학금", title, attachment["title"], code),
                )
            )
            attachment["pages"] = extract_pdf(output / attachment["source_file"])
        scholarships.append({"id": code, "url": url, **save_source(raw, ".html", output), **page})
    result = {
        "schema_version": 1,
        "fetched_at": stamp,
        "source_url": REGULATIONS,
        "index_source": save_source(index_raw, ".html", output),
        "list_source": save_source(list_raw, ".html", output),
        "categories": categories,
        "regulations": records,
        "scholarships": scholarships,
        "coverage": {
            "listed": len(records),
            "attachments": len(jobs),
            "without_attachments": sum(not r["attachments"] for r in records),
        },
    }
    write_json(output / "university.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--resume", action="store_true", help="Reuse download cache after interruption"
    )
    args = parser.parse_args()
    if not args.resume:
        import shutil

        shutil.rmtree(DATA / ".collection-cache", ignore_errors=True)
    result = collect()
    print(json.dumps(result["coverage"], ensure_ascii=False))


if __name__ == "__main__":
    main()
