"""Bounded public Work24 HTML collection; no login, hidden endpoints or personal records."""

import re
from collections import Counter, OrderedDict
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from html.parser import HTMLParser
from threading import Lock
from time import monotonic
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.robotparser import RobotFileParser
from zoneinfo import ZoneInfo

from .contracts import Posting, ProviderFailure, failure_reason
from .job_scope import title_matches

BASE = "https://www.work24.go.kr"
LIST = "/wk/a/b/1200/retriveDtlEmpSrchList.do"
DETAIL = "/wk/a/b/1500/empDetailAuthView.do"
AGENT = "UNIPATH-JobCollector/1.0"
_CACHE = OrderedDict()
_LOCK = Lock()
_FETCH_LOCK = Lock()
_FIELDS = {
    "경력",
    "학력",
    "자격 면허",
    "모집 직종",
    "관련 직종",
    "고용 형태",
    "임금 조건",
    "근무 예정지",
    "전공",
    "컴퓨터 활용 능력",
    "외국어 능력",
    "기타 우대사항",
}


class Node:
    def __init__(self, tag="", attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []

    def nodes(self, tag=None):
        for child in self.children:
            if isinstance(child, Node):
                if tag is None or child.tag == tag:
                    yield child
                yield from child.nodes(tag)

    def text(self):
        if self.tag in {"script", "style", "button"}:
            return ""
        return " ".join(c.text() if isinstance(c, Node) else c for c in self.children)

    def clean(self):
        return re.sub(r"\s+", " ", self.text()).strip()

    def has(self, cls):
        return cls in self.attrs.get("class", "").split()


class Tree(HTMLParser):
    def __init__(self, raw):
        super().__init__()
        self.root = Node()
        self.stack = [self.root]
        self.feed(raw.decode("utf-8"))
        self.close()

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in {"br", "hr", "img", "input", "meta", "link", "area", "col", "source", "wbr"}:
            self.stack.append(node)

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def detail_links(raw, keyword=None, *, native_only=True):
    root = Tree(raw).root
    links = []
    for anchor in root.nodes("a"):
        url = urlsplit(anchor.attrs.get("href", ""))
        params = parse_qs(url.query)
        if (
            url.path != DETAIL
            or url.netloc not in {"", "www.work24.go.kr"}
            or (native_only and params.get("infoTypeCd") != ["VALIDATION"])
        ):
            continue
        if keyword is not None and not title_matches(anchor.clean(), [keyword]):
            continue
        identifier = params.get("wantedAuthNo", [""])[0]
        if re.fullmatch(r"[A-Z0-9]{8,30}", identifier) and identifier not in links:
            links.append(identifier)
    if (
        not links
        and not any("data-emp-detail" in n.attrs for n in root.nodes("a"))
        and not any(x in root.clean() for x in ("검색 결과가 없습니다", "검색결과가 없습니다"))
    ):
        raise ProviderFailure("Work24 search markup unavailable", "crawl_markup_changed")
    return links[:10]


def detail_url(identifier):
    return (
        BASE
        + DETAIL
        + "?"
        + urlencode(
            dict(
                wantedAuthNo=identifier, infoTypeCd="VALIDATION", infoTypeGroup="tb_workinfoworknet"
            )
        )
    )


def parse_detail(raw, identifier):
    root = Tree(raw).root
    title = next((n.clean() for n in root.nodes("strong") if n.has("title")), "")
    company = next((n.clean() for n in root.nodes("p") if n.has("corp_info")), "")
    duties = next(
        (
            n.clean()
            for n in root.nodes("div")
            if n.has("fold") and n.clean().startswith("직무내용")
        ),
        "",
    )
    fields = {}
    for row in root.nodes("tr"):
        cells = [c for c in row.children if isinstance(c, Node) and c.tag in {"th", "td"}]
        for left, right in zip(cells, cells[1:], strict=False):
            if left.tag == "th" and right.tag == "td" and left.clean() in _FIELDS:
                fields[left.clean()] = right.clean()
    closing = "확인 필요"
    for node in root.nodes("div"):
        direct = [c for c in node.children if isinstance(c, Node)]
        if any(n.tag == "strong" and n.clean() == "접수 마감일" for n in direct):
            closing = next((n.clean() for n in direct if n.tag == "p"), closing)
    expires = None
    date = re.search(r"(20\d{2})[.\-/](\d{2})[.\-/](\d{2})", closing)
    if date:
        expires = datetime(
            *map(int, date.groups()), 23, 59, 59, tzinfo=ZoneInfo("Asia/Seoul")
        ).isoformat()
    if not title or not company or not duties or not fields.get("근무 예정지"):
        raise ProviderFailure("Work24 detail markup unavailable", "crawl_detail_incomplete")
    body = "\n".join([duties] + [f"{k}: {v}" for k, v in fields.items()])
    return Posting(
        "work24",
        identifier,
        title,
        company,
        fields["근무 예정지"],
        detail_url(identifier),
        body[:20000],
        datetime.now(UTC).isoformat(),
        closing,
        expires,
        False if "마감된" in root.clean() else None,
        "excerpt" if len(body) > 20000 else "full_text",
    )


class CrawlBatch(list):
    """Per-search diagnostics travel with cached rows, never on shared source state."""

    def __init__(self, rows=(), *, detail_failures=None):
        super().__init__(rows)
        self.detail_failures = dict(detail_failures or {})


class Work24Crawler:
    name = "work24"
    collection_method = "crawl"

    def __init__(self, transport):
        self.transport = transport

    def search(self, query):
        key = query.keyword.strip().casefold()
        with _LOCK:
            cached = _CACHE.get(key)
        if cached and monotonic() - cached[0] < 300:
            rows = cached[1]
        else:
            if not _FETCH_LOCK.acquire(timeout=2):
                raise ProviderFailure("Collector busy; retry shortly", "crawl_busy")
            try:
                with _LOCK:
                    cached = _CACHE.get(key)
                if cached and monotonic() - cached[0] < 300:
                    rows = cached[1]
                else:
                    rows = self.collect(query.keyword.strip())
                    with _LOCK:
                        _CACHE[key] = (monotonic(), rows)
                        _CACHE.move_to_end(key)
                        while len(_CACHE) > 32:
                            _CACHE.popitem(last=False)
            finally:
                _FETCH_LOCK.release()
        region = query.region_label.strip()
        alias = {"서울": "서울", "경기": "경기", "부산": "부산"}.get(region, region)
        now = datetime.now(UTC)
        filtered = [
            p
            for p in rows
            if p.active is not False
            and (p.expires_at is None or datetime.fromisoformat(p.expires_at) > now)
            and (query.nationwide or alias in p.location)
        ][: query.limit]
        return CrawlBatch(filtered, detail_failures=getattr(rows, "detail_failures", {}))

    def collect(self, keyword):
        def fetch(url):
            return self.transport.request(url, headers={"User-Agent": AGENT})

        robots = RobotFileParser()
        robots.parse(fetch(BASE + "/robots.txt").decode("utf-8").splitlines())
        url = BASE + LIST + "?" + urlencode({"srcKeyword": keyword})
        if not robots.can_fetch(AGENT, url) or not robots.can_fetch(AGENT, BASE + DETAIL):
            raise ProviderFailure("Public collection disallowed", "crawl_disallowed")
        identifiers = []
        for page in range(1, 4):
            page_url = (
                BASE
                + LIST
                + "?"
                + urlencode(
                    {
                        "srcKeyword": keyword,
                        "siteClcd": "WORK",
                        "keywordWantedTitle": "Y",
                        "currentPageNo": page,
                        "pageIndex": page,
                        "recordCountPerPage": 10,
                    }
                )
            )
            raw = fetch(page_url)
            all_links = detail_links(raw, native_only=False)
            found = detail_links(raw, keyword)
            fresh = [identifier for identifier in found if identifier not in identifiers]
            identifiers.extend(fresh)
            if len(identifiers) >= 10 or not all_links:
                break
        identifiers = identifiers[:10]

        def load(identifier):
            try:
                return parse_detail(fetch(detail_url(identifier)), identifier), None
            except (ProviderFailure, ValueError, UnicodeError) as error:
                # Keep other details; report only bounded error codes, never raw HTML.
                return None, failure_reason(error)

        with ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(load, identifiers))
        return CrawlBatch(
            [posting for posting, reason in outcomes if posting is not None],
            detail_failures=Counter(reason for posting, reason in outcomes if reason),
        )
