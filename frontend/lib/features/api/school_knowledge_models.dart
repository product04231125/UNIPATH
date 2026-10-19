// GENERATED from Pydantic; run scripts/export_knowledge_contracts.py.
// UUIDs/calendar dates are strings; instants are DateTime. No UI or storage effects.

abstract interface class SchoolKnowledgePayload {
  Map<String, Object?> toJson();
}

class SchoolKnowledgeChunkPart implements SchoolKnowledgePayload {
  const SchoolKnowledgeChunkPart({
    required this.content,
    this.admissionYears,
    this.tracks,
    this.warnings = const [],
  });
  final String content;
  final List<int>? admissionYears;
  final List<String>? tracks;
  final List<String> warnings;
  factory SchoolKnowledgeChunkPart.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgeChunkPart(
        content: value['content'] as String,
        admissionYears: value['admission_years'] == null
            ? null
            : List.unmodifiable(
                (value['admission_years'] as List).map((v) => v as int),
              ),
        tracks: value['tracks'] == null
            ? null
            : List.unmodifiable(
                (value['tracks'] as List).map((v) => v as String),
              ),
        warnings: value['warnings'] == null
            ? const []
            : List.unmodifiable(
                (value['warnings'] as List).map((v) => v as String),
              ),
      );

  @override
  Map<String, Object?> toJson() => {
    'content': content,
    'admission_years': admissionYears?.map((v) => v).toList(),
    'tracks': tracks?.map((v) => v).toList(),
    'warnings': warnings.map((v) => v).toList(),
  };
}

class SchoolKnowledgeChunkView implements SchoolKnowledgePayload {
  const SchoolKnowledgeChunkView({
    required this.content,
    this.admissionYears,
    this.tracks,
    this.warnings = const [],
    required this.id,
    required this.partIndex,
    required this.partCount,
    required this.characterStart,
    required this.characterEnd,
    required this.contentHash,
  });
  final String content;
  final List<int>? admissionYears;
  final List<String>? tracks;
  final List<String> warnings;
  final String id;
  final int partIndex;
  final int partCount;
  final int characterStart;
  final int characterEnd;
  final String contentHash;
  factory SchoolKnowledgeChunkView.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgeChunkView(
        content: value['content'] as String,
        admissionYears: value['admission_years'] == null
            ? null
            : List.unmodifiable(
                (value['admission_years'] as List).map((v) => v as int),
              ),
        tracks: value['tracks'] == null
            ? null
            : List.unmodifiable(
                (value['tracks'] as List).map((v) => v as String),
              ),
        warnings: value['warnings'] == null
            ? const []
            : List.unmodifiable(
                (value['warnings'] as List).map((v) => v as String),
              ),
        id: value['id'] as String,
        partIndex: value['part_index'] as int,
        partCount: value['part_count'] as int,
        characterStart: value['character_start'] as int,
        characterEnd: value['character_end'] as int,
        contentHash: value['content_hash'] as String,
      );

  @override
  Map<String, Object?> toJson() => {
    'content': content,
    'admission_years': admissionYears?.map((v) => v).toList(),
    'tracks': tracks?.map((v) => v).toList(),
    'warnings': warnings.map((v) => v).toList(),
    'id': id,
    'part_index': partIndex,
    'part_count': partCount,
    'character_start': characterStart,
    'character_end': characterEnd,
    'content_hash': contentHash,
  };
}

class SchoolKnowledgeCreate implements SchoolKnowledgePayload {
  const SchoolKnowledgeCreate({
    required this.sourceDocumentId,
    required this.expectedSourceVersion,
    required this.documentHash,
    required this.pageCount,
    required this.extractorVersion,
    required this.sourceCheckedOn,
  });
  final String sourceDocumentId;
  final int expectedSourceVersion;
  final String documentHash;
  final int pageCount;
  final String extractorVersion;
  final String sourceCheckedOn;
  factory SchoolKnowledgeCreate.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgeCreate(
        sourceDocumentId: value['source_document_id'] as String,
        expectedSourceVersion: value['expected_source_version'] as int,
        documentHash: value['document_hash'] as String,
        pageCount: value['page_count'] as int,
        extractorVersion: value['extractor_version'] as String,
        sourceCheckedOn: value['source_checked_on'] as String,
      );

  @override
  Map<String, Object?> toJson() => {
    'source_document_id': sourceDocumentId,
    'expected_source_version': expectedSourceVersion,
    'document_hash': documentHash,
    'page_count': pageCount,
    'extractor_version': extractorVersion,
    'source_checked_on': sourceCheckedOn,
  };
}

class SchoolKnowledgePageReplace implements SchoolKnowledgePayload {
  const SchoolKnowledgePageReplace({
    required this.expectedVersion,
    this.isBlank = false,
    required this.parts,
  });
  final int expectedVersion;
  final bool isBlank;
  final List<SchoolKnowledgeChunkPart> parts;
  factory SchoolKnowledgePageReplace.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgePageReplace(
        expectedVersion: value['expected_version'] as int,
        isBlank: value['is_blank'] == null ? false : value['is_blank'] as bool,
        parts: List.unmodifiable(
          (value['parts'] as List).map(
            (v) => SchoolKnowledgeChunkPart.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
      );

  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'is_blank': isBlank,
    'parts': parts.map((v) => v.toJson()).toList(),
  };
}

class SchoolKnowledgeApprove implements SchoolKnowledgePayload {
  const SchoolKnowledgeApprove({
    required this.expectedVersion,
    required this.reviewedDocumentHash,
    required this.sourceVerified,
    required this.applicabilityVerified,
    required this.extractionVerified,
    required this.completeDocumentVerified,
    required this.reviewNote,
  });
  final int expectedVersion;
  final String reviewedDocumentHash;
  final bool sourceVerified;
  final bool applicabilityVerified;
  final bool extractionVerified;
  final bool completeDocumentVerified;
  final String reviewNote;
  factory SchoolKnowledgeApprove.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgeApprove(
        expectedVersion: value['expected_version'] as int,
        reviewedDocumentHash: value['reviewed_document_hash'] as String,
        sourceVerified: value['source_verified'] as bool,
        applicabilityVerified: value['applicability_verified'] as bool,
        extractionVerified: value['extraction_verified'] as bool,
        completeDocumentVerified: value['complete_document_verified'] as bool,
        reviewNote: value['review_note'] as String,
      );

  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'reviewed_document_hash': reviewedDocumentHash,
    'source_verified': sourceVerified,
    'applicability_verified': applicabilityVerified,
    'extraction_verified': extractionVerified,
    'complete_document_verified': completeDocumentVerified,
    'review_note': reviewNote,
  };
}

class SchoolKnowledgeRevoke implements SchoolKnowledgePayload {
  const SchoolKnowledgeRevoke({
    required this.expectedVersion,
    required this.reason,
  });
  final int expectedVersion;
  final String reason;
  factory SchoolKnowledgeRevoke.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgeRevoke(
        expectedVersion: value['expected_version'] as int,
        reason: value['reason'] as String,
      );

  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'reason': reason,
  };
}

class SchoolKnowledgeView implements SchoolKnowledgePayload {
  const SchoolKnowledgeView({
    required this.id,
    required this.institutionId,
    required this.departmentId,
    required this.curriculumId,
    required this.name,
    required this.sourceDocumentId,
    required this.sourceDocumentVersion,
    required this.version,
    required this.status,
    required this.documentHash,
    required this.pageCount,
    required this.extractorVersion,
    required this.sourceCheckedOn,
    required this.createdAt,
    required this.updatedAt,
    required this.approvedBy,
    required this.approvedAt,
    required this.reviewNote,
    required this.revokedBy,
    required this.revokedAt,
    required this.revocationReason,
  });
  final String id;
  final String institutionId;
  final String? departmentId;
  final String? curriculumId;
  final String name;
  final String sourceDocumentId;
  final int sourceDocumentVersion;
  final int version;
  final String status;
  final String documentHash;
  final int pageCount;
  final String extractorVersion;
  final String sourceCheckedOn;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String reviewNote;
  final String? revokedBy;
  final DateTime? revokedAt;
  final String revocationReason;
  factory SchoolKnowledgeView.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgeView(
        id: value['id'] as String,
        institutionId: value['institution_id'] as String,
        departmentId: value['department_id'] == null
            ? null
            : value['department_id'] as String,
        curriculumId: value['curriculum_id'] == null
            ? null
            : value['curriculum_id'] as String,
        name: value['name'] as String,
        sourceDocumentId: value['source_document_id'] as String,
        sourceDocumentVersion: value['source_document_version'] as int,
        version: value['version'] as int,
        status: value['status'] as String,
        documentHash: value['document_hash'] as String,
        pageCount: value['page_count'] as int,
        extractorVersion: value['extractor_version'] as String,
        sourceCheckedOn: value['source_checked_on'] as String,
        createdAt: DateTime.parse(value['created_at'] as String),
        updatedAt: DateTime.parse(value['updated_at'] as String),
        approvedBy: value['approved_by'] == null
            ? null
            : value['approved_by'] as String,
        approvedAt: value['approved_at'] == null
            ? null
            : DateTime.parse(value['approved_at'] as String),
        reviewNote: value['review_note'] as String,
        revokedBy: value['revoked_by'] == null
            ? null
            : value['revoked_by'] as String,
        revokedAt: value['revoked_at'] == null
            ? null
            : DateTime.parse(value['revoked_at'] as String),
        revocationReason: value['revocation_reason'] as String,
      );

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'name': name,
    'source_document_id': sourceDocumentId,
    'source_document_version': sourceDocumentVersion,
    'version': version,
    'status': status,
    'document_hash': documentHash,
    'page_count': pageCount,
    'extractor_version': extractorVersion,
    'source_checked_on': sourceCheckedOn,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'approved_by': approvedBy,
    'approved_at': approvedAt?.toUtc().toIso8601String(),
    'review_note': reviewNote,
    'revoked_by': revokedBy,
    'revoked_at': revokedAt?.toUtc().toIso8601String(),
    'revocation_reason': revocationReason,
  };
}

class SchoolKnowledgeList implements SchoolKnowledgePayload {
  const SchoolKnowledgeList({required this.items, this.nextCursor});
  final List<SchoolKnowledgeView> items;
  final String? nextCursor;
  factory SchoolKnowledgeList.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgeList(
        items: List.unmodifiable(
          (value['items'] as List).map(
            (v) => SchoolKnowledgeView.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
        nextCursor: value['next_cursor'] == null
            ? null
            : value['next_cursor'] as String,
      );

  @override
  Map<String, Object?> toJson() => {
    'items': items.map((v) => v.toJson()).toList(),
    'next_cursor': nextCursor,
  };
}

class SchoolKnowledgePageView implements SchoolKnowledgePayload {
  const SchoolKnowledgePageView({
    required this.knowledgeDocumentId,
    required this.version,
    required this.page,
    required this.pageHash,
    required this.isBlank,
    required this.parts,
  });
  final String knowledgeDocumentId;
  final int version;
  final int page;
  final String pageHash;
  final bool isBlank;
  final List<SchoolKnowledgeChunkView> parts;
  factory SchoolKnowledgePageView.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgePageView(
        knowledgeDocumentId: value['knowledge_document_id'] as String,
        version: value['version'] as int,
        page: value['page'] as int,
        pageHash: value['page_hash'] as String,
        isBlank: value['is_blank'] as bool,
        parts: List.unmodifiable(
          (value['parts'] as List).map(
            (v) => SchoolKnowledgeChunkView.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
      );

  @override
  Map<String, Object?> toJson() => {
    'knowledge_document_id': knowledgeDocumentId,
    'version': version,
    'page': page,
    'page_hash': pageHash,
    'is_blank': isBlank,
    'parts': parts.map((v) => v.toJson()).toList(),
  };
}

class SchoolKnowledgePageSummary implements SchoolKnowledgePayload {
  const SchoolKnowledgePageSummary({
    required this.page,
    required this.partCount,
    required this.characterCount,
    required this.pageHash,
    required this.isBlank,
  });
  final int page;
  final int partCount;
  final int characterCount;
  final String pageHash;
  final bool isBlank;
  factory SchoolKnowledgePageSummary.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgePageSummary(
        page: value['page'] as int,
        partCount: value['part_count'] as int,
        characterCount: value['character_count'] as int,
        pageHash: value['page_hash'] as String,
        isBlank: value['is_blank'] as bool,
      );

  @override
  Map<String, Object?> toJson() => {
    'page': page,
    'part_count': partCount,
    'character_count': characterCount,
    'page_hash': pageHash,
    'is_blank': isBlank,
  };
}

class SchoolKnowledgePageList implements SchoolKnowledgePayload {
  const SchoolKnowledgePageList({required this.items, this.nextCursor});
  final List<SchoolKnowledgePageSummary> items;
  final int? nextCursor;
  factory SchoolKnowledgePageList.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgePageList(
        items: List.unmodifiable(
          (value['items'] as List).map(
            (v) => SchoolKnowledgePageSummary.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
        nextCursor: value['next_cursor'] == null
            ? null
            : value['next_cursor'] as int,
      );

  @override
  Map<String, Object?> toJson() => {
    'items': items.map((v) => v.toJson()).toList(),
    'next_cursor': nextCursor,
  };
}

class SchoolKnowledgeContext implements SchoolKnowledgePayload {
  const SchoolKnowledgeContext({
    required this.institutionId,
    required this.departmentId,
    this.curriculumId,
    this.admissionYear,
    this.track,
  });
  final String institutionId;
  final String departmentId;
  final String? curriculumId;
  final int? admissionYear;
  final String? track;
  factory SchoolKnowledgeContext.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgeContext(
        institutionId: value['institution_id'] as String,
        departmentId: value['department_id'] as String,
        curriculumId: value['curriculum_id'] == null
            ? null
            : value['curriculum_id'] as String,
        admissionYear: value['admission_year'] == null
            ? null
            : value['admission_year'] as int,
        track: value['track'] == null ? null : value['track'] as String,
      );

  @override
  Map<String, Object?> toJson() => {
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'admission_year': admissionYear,
    'track': track,
  };
}

class SchoolKnowledgeQuery implements SchoolKnowledgePayload {
  const SchoolKnowledgeQuery({required this.question, required this.context});
  final String question;
  final SchoolKnowledgeContext context;
  factory SchoolKnowledgeQuery.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgeQuery(
        question: value['question'] as String,
        context: SchoolKnowledgeContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
      );

  @override
  Map<String, Object?> toJson() => {
    'question': question,
    'context': context.toJson(),
  };
}

class SchoolKnowledgeSearch implements SchoolKnowledgePayload {
  const SchoolKnowledgeSearch({
    required this.question,
    required this.context,
    this.limit = 3,
  });
  final String question;
  final SchoolKnowledgeContext context;
  final int limit;
  factory SchoolKnowledgeSearch.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgeSearch(
        question: value['question'] as String,
        context: SchoolKnowledgeContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        limit: value['limit'] == null ? 3 : value['limit'] as int,
      );

  @override
  Map<String, Object?> toJson() => {
    'question': question,
    'context': context.toJson(),
    'limit': limit,
  };
}

class SchoolKnowledgeCitation implements SchoolKnowledgePayload {
  const SchoolKnowledgeCitation({
    required this.chunkId,
    required this.documentId,
    required this.title,
    required this.sourceUrl,
    required this.page,
    required this.excerpt,
  });
  final String chunkId;
  final String documentId;
  final String title;
  final String sourceUrl;
  final int page;
  final String excerpt;
  factory SchoolKnowledgeCitation.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgeCitation(
        chunkId: value['chunk_id'] as String,
        documentId: value['document_id'] as String,
        title: value['title'] as String,
        sourceUrl: value['source_url'] as String,
        page: value['page'] as int,
        excerpt: value['excerpt'] as String,
      );

  @override
  Map<String, Object?> toJson() => {
    'chunk_id': chunkId,
    'document_id': documentId,
    'title': title,
    'source_url': sourceUrl,
    'page': page,
    'excerpt': excerpt,
  };
}

class SchoolKnowledgeSearchResponse implements SchoolKnowledgePayload {
  const SchoolKnowledgeSearchResponse({
    required this.queryId,
    required this.status,
    required this.reason,
    this.sources = const [],
    this.missingFields = const [],
  });
  final String queryId;
  final String status;
  final String reason;
  final List<SchoolKnowledgeCitation> sources;
  final List<String> missingFields;
  factory SchoolKnowledgeSearchResponse.fromJson(Map<String, dynamic> value) =>
      SchoolKnowledgeSearchResponse(
        queryId: value['query_id'] as String,
        status: value['status'] as String,
        reason: value['reason'] as String,
        sources: value['sources'] == null
            ? const []
            : List.unmodifiable(
                (value['sources'] as List).map(
                  (v) => SchoolKnowledgeCitation.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        missingFields: value['missing_fields'] == null
            ? const []
            : List.unmodifiable(
                (value['missing_fields'] as List).map((v) => v as String),
              ),
      );

  @override
  Map<String, Object?> toJson() => {
    'query_id': queryId,
    'status': status,
    'reason': reason,
    'sources': sources.map((v) => v.toJson()).toList(),
    'missing_fields': missingFields.map((v) => v).toList(),
  };
}
