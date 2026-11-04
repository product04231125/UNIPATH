"""Explicit refresh tools: crawl KDU calendar or import the six supplied regulation PDFs."""

import argparse
import hashlib
import json
import re
import shutil
from datetime import UTC, date, datetime
from html.parser import HTMLParser
from pathlib import Path
from urllib.request import Request, urlopen

DATA = Path(__file__).with_name("data")
URL = "https://www.kduniv.ac.kr/kor/CMS/ScheduleMgr/YearList.do?mCode=MN096"
DOCS = [
    ("2-0-1", "학칙", "학부"),
    ("2-0-2", "학칙시행세칙", "학부"),
    ("2-0-3", "특수대학원 학칙", "특수대학원"),
    ("2-0-4", "특수대학원 학칙시행세칙", "특수대학원"),
    ("2-0-5", "일반대학원 학칙", "일반대학원"),
    ("2-0-6", "일반대학원 학칙시행세칙", "일반대학원"),
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


class CalendarParser(HTMLParser):
    """Read only explicit month headings and date/title cells; ignore navigation/scripts."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth = 0
        self.capture = None
        self.values = []

    def handle_starttag(self, tag, attrs):
        if tag in {"br", "img", "input", "meta", "link", "hr", "col", "wbr", "source"}:
            if self.capture and tag == "br":
                self.capture[2].append(" ")
            return
        self.depth += 1
        classes = dict(attrs).get("class", "").split()
        for name in ("cal-month", "date-core", "body-core"):
            if name in classes:
                if self.capture:
                    raise ValueError("Nested calendar field")
                self.capture = [name, self.depth, []]

    def handle_endtag(self, tag):
        if tag in {"br", "img", "input", "meta", "link", "hr", "col", "wbr", "source"}:
            return
        if self.capture and self.depth == self.capture[1]:
            self.values.append((self.capture[0], " ".join("".join(self.capture[2]).split())))
            self.capture = None
        self.depth -= 1

    def handle_data(self, data):
        if self.capture:
            self.capture[2].append(data)


def parse_calendar(html, year):
    parser = CalendarParser()
    parser.feed(html)
    month, pending = None, None
    months, events = [], []
    for kind, value in parser.values:
        if kind == "cal-month":
            match = re.fullmatch(r"(\d{4})\.\s*(\d{1,2})\s*월", value)
            if not match or int(match[1]) != year or pending:
                raise ValueError("Unexpected calendar year or layout")
            month = int(match[2])
            months.append(month)
        elif kind == "date-core":
            if month is None or pending is not None:
                raise ValueError("Unpaired calendar date")
            pending = value
        else:
            if not pending or not value:
                raise ValueError("Missing calendar title/date")
            dates = re.findall(r"(\d{1,2})\.\s*(\d{1,2})\s*\([월화수목금토일]\)", pending)
            if len(dates) not in (1, 2):
                raise ValueError("Unsupported date format")
            start = date(year, int(dates[0][0]), int(dates[0][1]))
            end_month, end_day = map(int, dates[-1])
            end = date(year + (end_month < start.month), end_month, end_day)
            if end < start:
                raise ValueError("Reversed calendar range")
            events.append(
                {
                    "id": f"event-{len(events) + 1:04d}",
                    "listed_month": month,
                    "date_text": pending,
                    "title": value,
                    "start_date": start.isoformat(),
                    "end_date": end.isoformat(),
                }
            )
            pending = None
    if months != list(range(1, 13)) or pending or not events:
        raise ValueError("Incomplete calendar: refusing to replace previous snapshot")
    return events


def crawl(year, output=DATA):
    url = URL + f"&calendar_year={year}"
    request = Request(url, headers={"User-Agent": "UNIPATH-AcademicCalendar/1.0"})
    with urlopen(request, timeout=25) as response:
        if response.url != url:
            raise ValueError("Unexpected calendar redirect")
        raw = response.read(4_000_001)
    if len(raw) > 4_000_000:
        raise ValueError("Calendar response too large")
    events = parse_calendar(raw.decode("utf-8"), year)
    fetched = datetime.now(UTC).isoformat()
    sha = digest(raw)
    # Keep source snapshots by hash for reproducibility; publish JSON only after parsing succeeds.
    source_path = output / "sources" / f"calendar-{year}-{sha[:12]}.html"
    source_path.parent.mkdir(parents=True, exist_ok=True)
    source_path.write_bytes(raw)
    result = {
        "year": year,
        "source_url": url,
        "fetched_at": fetched,
        "sha256": sha,
        "source_file": str(source_path.relative_to(output)),
        "events": events,
    }
    write_json(output / f"calendar-{year}.json", result)
    return result


HEADING = re.compile(r"^(?:제\s*\d+\s*장\s*.+|부\s*칙(?:\s.*)?|[\[【]?(?:별표|별지|서식).*)$")
ARTICLE = re.compile(r"^제\s*\d+\s*조(?:의\s*\d+)?(?:\s|[（(]|$)")


def split_pages(pages, code):
    """Preserve every extracted line, including amendments, annexes and page boundaries."""
    sections = [{"id": "s001", "title": "문서 개요·개정 이력", "items": []}]
    item = None
    for page in pages:
        for line in page["text"].splitlines():
            # Ignore the repeated running header only; full page remains in pages[].
            if re.fullmatch(r".*\s" + re.escape(code), line.strip()):
                continue
            if HEADING.match(line):
                sections.append({"id": f"s{len(sections) + 1:03d}", "title": line, "items": []})
                item = None
            if item is None or ARTICLE.match(line):
                match = re.match(r"^(제\s*\d+\s*조(?:의\s*\d+)?\s*[（(][^）)]+[）)])", line)
                title = match[1] if match else line[:70]
                item = {
                    "id": f"i{sum(len(s['items']) for s in sections) + 1:04d}",
                    "title": title,
                    "parts": [],
                }
                sections[-1]["items"].append(item)
            if not item["parts"] or item["parts"][-1]["page"] != page["page"]:
                item["parts"].append({"page": page["page"], "text": ""})
            item["parts"][-1]["text"] += line + "\n"
    return [section for section in sections if section["items"]]


def import_regulations(directory, output=DATA):
    import pdfplumber

    documents = []
    for code, title, scope in DOCS:
        matches = list(directory.glob(code + ".+*.pdf"))
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one {code} PDF")
        path = matches[0]
        raw = path.read_bytes()
        pages = []
        with pdfplumber.open(path) as pdf:
            for index, page in enumerate(pdf.pages, 1):
                text = page.extract_text() or ""
                if not text.strip():
                    raise ValueError(f"{code} page {index} requires OCR/review")
                pages.append({"page": index, "text": text, "tables": page.extract_tables()})
        sha = digest(raw)
        source = output / "sources" / f"{code}-{sha[:12]}.pdf"
        source.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, source)
        documents.append(
            {
                "id": code,
                "title": title,
                "scope": scope,
                "original_filename": path.name,
                "sha256": sha,
                "source_file": str(source.relative_to(output)),
                "page_count": len(pages),
                "pages": pages,
                "sections": split_pages(pages, code),
            }
        )
    result = {"imported_at": datetime.now(UTC).isoformat(), "documents": documents}
    write_json(output / "regulations.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    calendar = sub.add_parser("calendar")
    calendar.add_argument("--year", type=int, required=True)
    regulations = sub.add_parser("regulations")
    regulations.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "calendar":
        if not 2000 <= args.year <= 2100:
            parser.error("year must be 2000..2100")
        result = crawl(args.year)
        print(f"{args.year}: {len(result['events'])} events")
    else:
        result = import_regulations(args.directory)
        print(f"{len(result['documents'])} documents imported")


if __name__ == "__main__":
    main()
