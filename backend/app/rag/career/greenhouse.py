"""Published Greenhouse postings from an explicitly chosen employer board."""

import json
import re
from datetime import UTC, datetime
from html import unescape
from html.parser import HTMLParser

from .contracts import Posting


class BodyText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)

    def handle_starttag(self, tag, attrs):
        if tag in {"br", "p", "li", "div", "h2", "h3"}:
            self.parts.append("\n")


class Greenhouse:
    name = "greenhouse"
    # Few postings; filtered by location names instead of region codes.
    filters_region_by_label = True

    def __init__(self, board, transport):
        if not re.fullmatch(r"[a-zA-Z0-9_-]{1,80}", board):
            raise ValueError("Invalid Greenhouse board token")
        self.board = board
        self.transport = transport

    def search(self, query):
        url = f"https://boards-api.greenhouse.io/v1/boards/{self.board}/jobs"
        rows = json.loads(self.transport.request(url))["jobs"]
        results = []
        names = [part.strip().casefold() for part in query.region_label.split("·") if part.strip()]
        aliases = {"서울": ("서울", "seoul"), "경기": ("경기", "gyeonggi")}
        wanted = [word for name in names for word in aliases.get(name, (name,))]
        for row in rows:
            location = row["location"]["name"]
            if (
                not row.get("internal_job_id")
                or query.keyword.strip().casefold() not in row["title"].casefold()
            ):
                continue
            if query.nationwide:
                if not any(word in location.casefold() for word in ("korea", "대한민국", "한국")):
                    continue
            elif not any(word in location.casefold() for word in wanted):
                continue
            job_id = int(row["id"])
            job = json.loads(self.transport.request(f"{url}/{job_id}"))
            parser = BodyText()
            parser.feed(unescape(job["content"]))
            body = "".join(parser.parts).strip()
            if not body:
                continue
            results.append(
                Posting(
                    self.name,
                    f"{self.board}/{job_id}",
                    row["title"],
                    job.get("company_name") or self.board,
                    location,
                    job["absolute_url"],
                    body[:20000],
                    datetime.now(UTC).isoformat(),
                    expires_at=job.get("application_deadline"),
                    text_scope="full_text" if len(body) <= 20000 else "excerpt",
                )
            )
            if len(results) >= query.limit:
                break
        return results
