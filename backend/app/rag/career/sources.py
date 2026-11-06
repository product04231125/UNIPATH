"""Official search APIs. Result metadata is explicitly not a complete job description."""

import json
import xml.etree.ElementTree as ET
from datetime import UTC, datetime
from urllib.parse import urlencode

from .contracts import NotConfigured, Posting
from .transport import Transport


class Saramin:
    name = "saramin"

    def __init__(self, access_key=None, *, transport=None):
        self.key = access_key
        self.transport = transport or Transport()

    def search(self, query):
        if not self.key:
            raise NotConfigured("Saramin access key required")
        region = query.region(self.name)
        params = {
            "access-key": self.key,
            "keywords": query.keyword,
            "count": query.limit,
            "start": 0,
            "sort": "pd",
        }
        if region:
            params["loc_cd"] = region
        raw = self.transport.request(
            "https://oapi.saramin.co.kr/job-search?" + urlencode(params),
            headers={"Accept": "application/json"},
        )
        return parse_saramin(json.loads(raw))[: query.limit]


def parse_saramin(data):
    jobs = data["jobs"]["job"]
    if not isinstance(jobs, list):
        raise ValueError("Invalid Saramin response")
    stamp = datetime.now(UTC).isoformat()
    result = []
    for job in jobs:
        position = job["position"]

        def name(key, position=position):
            return str(position.get(key, {}).get("name", "미제공"))

        company = job["company"]["detail"]["name"]
        text = "\n".join(
            [
                f"공고: {position['title']}",
                f"회사: {company}",
                f"지역: {name('location')}",
                f"경력: {name('experience-level')}",
                f"학력: {name('required-education-level')}",
                f"근무형태: {name('job-type')}",
                f"키워드: {job.get('keyword', '미제공')}",
            ]
        )
        close = job.get("close-type", {})
        expires = None
        if str(close.get("code")) == "1" and job.get("expiration-timestamp"):
            expires = datetime.fromtimestamp(int(job["expiration-timestamp"]), UTC).isoformat()
        result.append(
            Posting(
                "saramin",
                str(job["id"]),
                position["title"],
                company,
                name("location"),
                job["url"],
                text,
                stamp,
                close.get("name", "확인 필요"),
                expires,
                str(job.get("active")) == "1",
            )
        )
    return result


class Work24:
    name = "work24"

    def __init__(self, auth_key=None, *, transport=None):
        self.key = auth_key
        self.transport = transport or Transport()

    def search(self, query):
        if not self.key:
            raise NotConfigured("Work24 auth key required")
        region = query.region(self.name)
        params = {
            "authKey": self.key,
            "callTp": "L",
            "returnType": "XML",
            "startPage": 1,
            "display": query.limit,
            "keyword": query.keyword,
        }
        if region:
            params["region"] = region
        raw = self.transport.request(
            "https://www.work24.go.kr/cm/openApi/call/wk/callOpenApiSvcInfo210L01.do?"
            + urlencode(params)
        )
        return parse_work24(raw)[: query.limit]


def parse_work24(raw):
    from zoneinfo import ZoneInfo

    if b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
        raise ValueError("XML entities are not accepted")
    root = ET.fromstring(raw)
    if root.tag != "wantedRoot" or root.find("total") is None:
        raise ValueError("Invalid Work24 response")
    stamp = datetime.now(UTC).isoformat()
    result = []
    for row in root.findall("wanted"):

        def get(key, row=row):
            return (row.findtext(key) or "").strip()

        text = "\n".join(
            f"{label}: {get(key) or '미제공'}"
            for key, label in [
                ("title", "공고"),
                ("company", "회사"),
                ("region", "지역"),
                ("career", "경력"),
                ("minEdubg", "학력"),
                ("sal", "급여"),
            ]
        )
        expires = None
        close = get("closeDt")
        for pattern in ("%Y-%m-%d", "%y-%m-%d", "%Y.%m.%d", "%y.%m.%d"):
            try:
                expires = (
                    datetime.strptime(close, pattern)
                    .replace(hour=23, minute=59, second=59, tzinfo=ZoneInfo("Asia/Seoul"))
                    .isoformat()
                )
                break
            except ValueError:
                continue
        result.append(
            Posting(
                "work24",
                get("wantedAuthNo"),
                get("title"),
                get("company"),
                get("region"),
                get("wantedInfoUrl"),
                text,
                stamp,
                close or "확인 필요",
                expires,
            )
        )
    return result


class JobKorea:
    name = "jobkorea"

    def search(self, query):
        raise NotConfigured("JobKorea approval, dedicated endpoint and response guide required")
