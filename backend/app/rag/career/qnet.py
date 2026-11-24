"""Q-Net (한국산업인력공단) public open API: qualification list, exam schedules, fees and info.

The legacy openapi.q-net.or.kr endpoints answer without a service key over plain HTTP; this is a
graduation project, so they are used as they are. Set QNET_SERVICE_KEY to send a key (it is added
as ServiceKey) and QNET_API_BASE to switch to another base such as the data.go.kr gateway.
Responses are small XML documents; parsed values are cached in process.
"""

import html
import json
import os
import re
import threading
import time
from datetime import date, datetime
from pathlib import Path
from urllib.parse import urlencode
from xml.etree import ElementTree

from .contracts import ProviderFailure
from .transport import Transport

DEFAULT_BASE = "http://openapi.q-net.or.kr/api/service/rest"
SCHEDULE_TTL = 6 * 3600
INFO_TTL = 24 * 3600
FAILURE_TTL = 120
DATA = Path(__file__).with_name("data") / "qnet_qualifications.json"
DETAIL_URL = "https://www.q-net.or.kr/crf005.do?id=crf00503&jmCd={jmcd}"
HOME_URL = "https://www.q-net.or.kr"
# Grades with education or career eligibility (기능사 has none).
RESTRICTED_SERIES = {"기술사", "기능장", "기사"}
INFO_LABELS = ("시험과목 및 배점", "취득방법", "응시자격", "출제경향")

_cache = {}
_lock = threading.Lock()


def qualifications():
    """The checked-in list of 613 national qualifications run by 한국산업인력공단."""
    return _load_list()


_list_cache = None


def _load_list():
    global _list_cache
    if _list_cache is None:
        data = json.loads(DATA.read_text(encoding="utf-8"))
        _list_cache = data["qualifications"]
    return _list_cache


def by_jmcd(jmcd):
    return next((q for q in _load_list() if q["jmcd"] == jmcd), None)


class QNet:
    def __init__(self, transport=None, *, base=None, key=None, clock=time.monotonic):
        self.transport = transport or Transport(allow_network=True, timeout=8)
        self.base = (base or os.getenv("QNET_API_BASE") or DEFAULT_BASE).rstrip("/")
        self.key = key if key is not None else os.getenv("QNET_SERVICE_KEY", "").strip()
        self.clock = clock

    def _items(self, path, params, ttl):
        query = dict(params)
        if self.key:
            query["ServiceKey"] = self.key
        cache_key = (self.base, path, tuple(sorted(params.items())))
        now = self.clock()
        with _lock:
            hit = _cache.get(cache_key)
            if hit and hit[0] > now:
                if isinstance(hit[1], ProviderFailure):
                    raise hit[1]
                return hit[1]
        try:
            raw = self.transport.request(f"{self.base}/{path}?{urlencode(query)}")
            items = parse_items(raw)
        except ProviderFailure as error:
            with _lock:
                _cache[cache_key] = (now + FAILURE_TTL, error)
            raise
        with _lock:
            _cache[cache_key] = (now + ttl, items)
        return items

    def technical_schedule(self, jmcd, second="실기"):
        """Rounds of one 국가기술자격 종목 (this exam year only)."""
        rows = self._items("InquiryTestInformationNTQSVC/getJMList", {"jmCd": jmcd}, SCHEDULE_TTL)
        return [technical_round(row, second) for row in rows]

    def professional_schedule(self, series_code):
        """Rounds of one 국가전문자격 계열 (this exam year only)."""
        rows = self._items(
            "InquiryTestDatesNationalProfessionalQualificationSVC/getList",
            {"seriesCd": series_code},
            SCHEDULE_TTL,
        )
        return professional_rounds(rows)

    def fee(self, jmcd):
        rows = self._items("InquiryTestInformationNTQSVC/getFeeList", {"jmCd": jmcd}, INFO_TTL)
        return next((clean(r.get("contents")) for r in rows if r.get("contents")), None)

    def info(self, jmcd):
        """Official texts: 취득방법, 시험과목 및 배점, 응시자격 and 출제경향 (whichever exist)."""
        rows = self._items("InquiryInformationTradeNTQSVC/getList", {"jmCd": jmcd}, INFO_TTL)
        texts = {}
        for row in rows:
            label, text = row.get("infogb"), clean(row.get("contents"))
            if label in INFO_LABELS and text:
                # The first line repeats '<종목> 취득방법'.
                lines = text.split("\n")
                if lines and lines[0].replace(" ", "").endswith(label.replace(" ", "")):
                    lines = lines[1:]
                texts[label] = "\n".join(lines).strip()[:4000]
        return texts


def parse_items(raw):
    try:
        root = ElementTree.fromstring(raw)
    except ElementTree.ParseError:
        raise ProviderFailure("Q-Net response unreadable", "invalid_response") from None
    code = root.findtext("header/resultCode") or root.findtext(".//resultCode")
    if code not in {"00", "0000"}:
        raise ProviderFailure("Q-Net refused the request", "provider_error")
    return [{child.tag: (child.text or "").strip() for child in item} for item in root.iter("item")]


def clean(text):
    if not text:
        return ""
    text = html.unescape(html.unescape(text)).replace("\r", "")
    text = re.sub(r"<[^>]+>", " ", text)
    lines = [" ".join(line.split()) for line in text.split("\n")]
    out = []
    for line in lines:
        if line or (out and out[-1]):
            out.append(line)
    return "\n".join(out).strip()


def day(value):
    if not value or not re.fullmatch(r"\d{8}", value):
        return None
    try:
        return datetime.strptime(value, "%Y%m%d").date().isoformat()
    except ValueError:
        return None


def event(kind, label, start, end=None):
    start, end = day(start), day(end)
    if start is None and end is None:
        return None
    return {"kind": kind, "label": label, "start": start or end, "end": end or start}


def technical_round(row, second="실기"):
    """One 국가기술자격 round with 필기 and 실기 (기술사: 면접) dates."""
    events = [
        event("registration", "필기 접수", row.get("docregstartdt"), row.get("docregenddt")),
        event("exam", "필기 시험", row.get("docexamstartdt"), row.get("docexamenddt")),
        event("result", "필기 합격 발표", row.get("docpassdt")),
        event(
            "document",
            "응시자격 서류 제출",
            row.get("docsubmitstartdt"),
            row.get("docsubmitenddt") or row.get("docsubmitentdt"),
        ),
        event("registration", f"{second} 접수", row.get("pracregstartdt"), row.get("pracregenddt")),
        event("exam", f"{second} 시험", row.get("pracexamstartdt"), row.get("pracexamenddt")),
        event("result", "최종 합격 발표", row.get("pracpassstartdt"), row.get("pracpassenddt")),
    ]
    return {
        "name": row.get("implplannm") or row.get("description") or "회차",
        "events": [e for e in events if e],
    }


def professional_rounds(rows):
    """국가전문자격 rows are one per stage (1차, 2차, 필기, 면접 …); grouped by year and 회."""
    rounds = {}
    for row in rows:
        text = row.get("description") or ""
        match = re.match(r"\s*(\d{4})년도\s*(\d+)회\s*(.*)", text)
        name, stage = (f"{match[1]}년도 {match[2]}회", match[3].strip()) if match else (text, "")
        stage = stage or "시험"
        events = [
            event(
                "registration",
                f"{stage} 접수",
                row.get("examregstartdt"),
                row.get("examregenddt"),
            ),
            event("exam", f"{stage} 시험", row.get("examstartdt"), row.get("examenddt")),
            event("result", f"{stage} 합격 발표", row.get("passstartdt"), row.get("passenddt")),
        ]
        rounds.setdefault(name, []).extend(e for e in events if e)
    return [{"name": name, "events": events} for name, events in rounds.items()]


def upcoming(rounds, today: date):
    """Rounds whose last date is today or later, and the first event still ahead."""
    iso = today.isoformat()
    ahead = [r for r in rounds if any(e["end"] >= iso for e in r["events"])]
    next_event = min(
        (e for r in ahead for e in r["events"] if e["end"] >= iso),
        key=lambda e: e["start"],
        default=None,
    )
    return ahead, next_event
