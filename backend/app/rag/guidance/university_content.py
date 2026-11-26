"""Build source-reading menus for collected university regulations and scholarships."""


def add_university(data, nodes, payloads, paginate):
    root = "university"
    nodes[root] = ("대학규정", "home", "menu")
    stamp = data["fetched_at"]
    base_source = {
        "type": "official_website",
        "source_url": data["source_url"],
        "fetched_at": stamp,
        "sha256": data["list_source"]["sha256"],
    }
    payloads[root] = {
        "message": "분류와 규정을 선택하면 첨부 문서 본문을 안내합니다.",
        "coverage": data["coverage"],
        "fetched_at": stamp,
    }
    for category in data["categories"]:
        if category["leaf"]:
            continue
        key = f"{root}:{category['id']}"
        parent = f"{root}:{category['parent_id']}" if category["parent_id"] else root
        nodes[key] = (category["title"], parent, "menu")
    for record in data["regulations"]:
        key = f"{root}:{record['id']}"
        parent = f"{root}:{record['parent_id']}" if record["parent_id"] else root
        nodes[key] = (record["title"], parent, "menu")
        warnings = [
            "게시 문서 기준 안내입니다. 개인 적용 여부는 시행일과 경과조치를 확인해야 합니다."
        ]
        if record["listing_status"] != "listed":
            warnings.insert(0, "사이트에 폐지 또는 이동된 규정으로 표시되어 있습니다.")
        if record["parent_id"] is None:
            warnings.append("전체 목록에는 있으나 사이트 분류 트리에 없는 항목입니다.")
        payloads[key] = {
            "reason": "university_regulation",
            "fetched_at": stamp,
            "message": f"{record['title']} · 게시 제·개정일: {record['revision_date']}",
            "warnings": warnings,
            "listing_status": record["listing_status"],
            "cards": [
                {
                    "type": "regulation_metadata",
                    "title": record["title"],
                    "body": record["category_path"],
                    "sources": [base_source],
                }
            ],
        }
        if not record["attachments"]:
            payloads[key]["message"] += "\n현재 목록에 내려받을 첨부파일이 없습니다."
            payloads[key]["attachment_state"] = "not_listed"
        for index, attachment in enumerate(record["attachments"]):
            attachment_id = f"{key}:attachment:{index + 1}"
            nodes[attachment_id] = (
                f"첨부 {index + 1} · 본문 {attachment['page_count']}쪽",
                key,
                "menu",
            )
            source = {
                "type": "official_pdf",
                "source_url": attachment["url"],
                "sha256": attachment["sha256"],
                "title": record["title"],
                "fetched_at": stamp,
                "asset_id": attachment["sha256"],
            }
            payloads[attachment_id] = {
                "message": "본문 페이지를 선택해 주세요.",
                "source": source,
                "warnings": warnings,
                "fetched_at": stamp,
            }
            for page in attachment["pages"]:
                page_id = f"{attachment_id}:page:{page['page']}"
                nodes[page_id] = (f"{page['page']}쪽", attachment_id, "content")
                card = {
                    "type": "regulation_page",
                    "title": f"{record['title']} {page['page']}쪽",
                    "body": page["text"],
                    "tables": page["tables"],
                    "extraction_status": page["extraction_status"],
                    "sources": [{**source, "page": page["page"]}],
                }
                page_warnings = list(warnings)
                if page.get("image"):
                    card["image_asset_id"] = page["image"]["sha256"]
                    card["preferred_view"] = "image"
                if page["extraction_status"] == "ocr_unreviewed":
                    page_warnings.append(
                        "스캔 문서 OCR 결과입니다. 숫자·조건은 원본 이미지와 대조해 주세요."
                    )
                if not page["text"].strip():
                    card["body"] = (
                        "이 페이지는 텍스트 추출이 되지 않았습니다. 첨부 원본 확인이 필요합니다."
                    )
                payloads[page_id] = {
                    "message": record["title"],
                    "reason": "university_pdf_page",
                    "warnings": page_warnings + ["표·서식의 추출 순서는 원문과 다를 수 있습니다."],
                    "fetched_at": stamp,
                    "cards": [card],
                }
            paginate(nodes, attachment_id)
    # Preserve scholarship's existing root ID.
    nodes["scholarship"] = ("장학금·학자금 융자", "home", "menu")
    payloads["scholarship"] = {"message": "안내 항목을 선택해 주세요.", "fetched_at": stamp}
    for page in data["scholarships"]:
        key = f"scholarship:{page['id']}"
        nodes[key] = (page["title"], "scholarship", "menu")
        source = {
            "type": "official_website",
            "source_url": page["url"],
            "sha256": page["sha256"],
            "fetched_at": stamp,
        }
        warnings = [
            "학교 게시 페이지의 수집본입니다. 현재 신청 기간·조건·금액은 별도 확인이 필요합니다."
        ]
        payloads[key] = {
            "reason": "scholarship_overview",
            "message": page["title"],
            "cards": [
                {
                    "type": "reference_text",
                    "title": page["title"],
                    "body": page["body"],
                    "sources": [source],
                }
            ],
            "warnings": warnings,
            "fetched_at": stamp,
        }
        related = []
        for link in page["links"]:
            if "#CDE_" in link["url"]:
                code = link["url"].split("#", 1)[1].split("-", 1)[0]
                target = f"university:{code}"
                if target in nodes and target not in related:
                    related.append(target)
        payloads[key]["related_node_ids"] = related
        for index, section in enumerate(page["sections"], 1):
            section_id = f"{key}:section:{index}"
            nodes[section_id] = (section["title"], key, "content")
            payloads[section_id] = {
                "message": section["title"],
                "reason": "scholarship_section",
                "cards": [
                    {
                        "type": "reference_text",
                        "title": section["title"],
                        "body": section["body"],
                        "sources": [source],
                    }
                ],
                "warnings": warnings,
                "fetched_at": stamp,
            }
        for index, table in enumerate(page["tables"], 1):
            table_id = f"{key}:table:{index}"
            nodes[table_id] = (table["caption"] or f"표 {index}", key, "menu")
            payloads[table_id] = {
                "message": "표 전체와 항목별 내용을 확인할 수 있습니다.",
                "reason": "scholarship_table",
                "fetched_at": stamp,
                "warnings": warnings,
                "cards": [
                    {
                        "type": "reference_table",
                        "title": table["caption"],
                        "body": "\n".join(" | ".join(row) for row in table["grid"]),
                        "table": table,
                        "sources": [source],
                    }
                ],
            }
            # Each row retains inherited row/column labels from the source's merged cells.
            for row_index, row in enumerate(table["grid"][1:], 1):
                row_id = f"{table_id}:row:{row_index}"
                label = " · ".join(
                    dict.fromkeys(cell for cell in row[: (1 if len(row) == 3 else 3)] if cell)
                )[:100]
                nodes[row_id] = (label or f"항목 {row_index}", table_id, "content")
                headers = table["grid"][0]
                body = "\n".join(f"{headers[i] or '내용'}: {cell}" for i, cell in enumerate(row))
                payloads[row_id] = {
                    "message": label,
                    "reason": "scholarship_table_row",
                    "fetched_at": stamp,
                    "warnings": warnings,
                    "cards": [
                        {
                            "type": "reference_text",
                            "title": label,
                            "body": body,
                            "sources": [source],
                        }
                    ],
                }
            paginate(nodes, table_id)
        for index, attachment in enumerate(page["attachments"], 1):
            attachment_id = f"{key}:attachment:{index}"
            nodes[attachment_id] = (attachment["title"], key, "content")
            payloads[attachment_id] = {
                "message": attachment["title"],
                "fetched_at": stamp,
                "cards": [
                    {
                        "type": "regulation_page",
                        "title": attachment["title"],
                        "body": p["text"],
                        "tables": p["tables"],
                        "sources": [
                            {
                                **source,
                                "source_url": attachment["url"],
                                "sha256": attachment["sha256"],
                                "page": p["page"],
                            }
                        ],
                    }
                    for p in attachment["pages"]
                ],
            }
        paginate(nodes, key)
    # Pagination keeps all items reachable; does not remove withdrawn or unclassified rows.
    for parent in [root, *(f"{root}:{c['id']}" for c in data["categories"] if not c["leaf"])]:
        paginate(nodes, parent)
