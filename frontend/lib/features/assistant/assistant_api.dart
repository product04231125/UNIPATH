import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_base_url.dart';
import '../api/school_knowledge_models.dart';
import '../auth/auth_api.dart';

enum AssistantStatus { grounded, insufficientEvidence, needsUserInput, failed }

class SchoolQueryContext {
  const SchoolQueryContext({
    this.institution,
    this.department,
    this.admissionYear,
    this.track,
    this.institutionId,
    this.departmentId,
    this.curriculumId,
  });
  final String? institution;
  final String? department;
  final int? admissionYear;
  final String? track;
  final String? institutionId, departmentId, curriculumId;
  bool get hasRegisteredSchool => institutionId != null && departmentId != null;
  Map<String, Object?> catalogJson() => {
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'admission_year': admissionYear,
    'track': track,
  };
  Map<String, Object?> toJson() => {
    'institution': institution,
    'department': department,
    'admission_year': admissionYear,
    'track': track,
  };
}

/// Authenticated UUID contract; the gateway is captured for one account/session.
class RegisteredAssistantApi implements AssistantGateway {
  const RegisteredAssistantApi(this.api);
  final ApiGateway api;
  @override
  Future<AssistantResult> query(
    String question,
    SchoolQueryContext context,
  ) async {
    if (!context.hasRegisteredSchool) {
      throw const AssistantApiException(
        '설정에서 등록된 학교·학과를 선택해 주세요. 개인 설정은 학교 질문을 지원하지 않습니다.',
      );
    }
    try {
      return AssistantResult.fromJson(
        (await api.request('POST', 'me/school-queries', {
          'question': question,
          'context': context.catalogJson(),
        }))!,
      );
    } on AuthFailure catch (e) {
      throw AssistantApiException(
        e.message,
        fields: e.fields,
        requestId: e.requestId,
      );
    }
  }

  @override
  void close() {} // Shared authenticated gateway belongs to the workspace.
}

class AssistantCitation {
  AssistantCitation.fromJson(Map<String, dynamic> json)
    : chunkId = json['chunk_id'] as String,
      documentId = json['document_id'] as String,
      title = json['title'] as String,
      source = Uri.parse(json['source_url'] as String),
      page = json['page'] as int,
      excerpt = json['excerpt'] as String,
      applicability = json['applicability'] == null
          ? null
          : SchoolKnowledgeCitationApplicability.fromJson(
              Map<String, dynamic>.from(json['applicability'] as Map),
            ) {
    if (!['http', 'https'].contains(source.scheme) ||
        source.host.isEmpty ||
        page < 1) {
      throw const FormatException('Invalid citation');
    }
  }
  final String chunkId;
  final String documentId;
  final String title;
  final Uri source;
  final int page;
  final String excerpt;
  final SchoolKnowledgeCitationApplicability? applicability;
}

class AssistantResult {
  AssistantResult.fromJson(Map<String, dynamic> json)
    : queryId = json['query_id'] as String,
      status = switch (json['status']) {
        'grounded' => AssistantStatus.grounded,
        'insufficient_evidence' => AssistantStatus.insufficientEvidence,
        'needs_user_input' => AssistantStatus.needsUserInput,
        'failed' => AssistantStatus.failed,
        _ => throw const FormatException('Unknown assistant status'),
      },
      reason = json['reason'] as String,
      answer = json['answer'] as String?,
      citations = (json['citations'] as List)
          .map(
            (value) => AssistantCitation.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
      missingFields = List<String>.from(json['missing_fields'] as List) {
    if (status == AssistantStatus.grounded) {
      if (answer == null || answer!.trim().isEmpty || citations.isEmpty) {
        throw const FormatException('Missing grounding');
      }
    } else if (answer != null || citations.isNotEmpty) {
      throw const FormatException('Unexpected answer');
    }
  }
  final String queryId;
  final AssistantStatus status;
  final String reason;
  final String? answer;
  final List<AssistantCitation> citations;
  final List<String> missingFields;

  Map<String, dynamic> toJson() => {
    'query_id': queryId,
    'status': switch (status) {
      AssistantStatus.grounded => 'grounded',
      AssistantStatus.insufficientEvidence => 'insufficient_evidence',
      AssistantStatus.needsUserInput => 'needs_user_input',
      AssistantStatus.failed => 'failed',
    },
    'reason': reason,
    'answer': answer,
    'missing_fields': missingFields,
    'citations': [
      for (final c in citations)
        {
          'chunk_id': c.chunkId,
          'document_id': c.documentId,
          'title': c.title,
          'source_url': c.source.toString(),
          'page': c.page,
          'excerpt': c.excerpt,
          'applicability': c.applicability?.toJson(),
        },
    ],
  };

  String get label => switch (reason) {
    'no_approved_matching_evidence' => '학교 자료 검색 결과 없음',
    'document_context_not_approved_or_incomplete' => '학교 자료 검토 필요',
    'answer_generator_not_configured' => '외부 AI 연결 설정 필요',
    'rag_processing_failed' => '학교 자료 검색 처리 실패',
    _ => switch (status) {
      AssistantStatus.grounded => '공식 문서 근거',
      AssistantStatus.insufficientEvidence => '공식 근거 부족',
      AssistantStatus.needsUserInput => '추가 확인 필요',
      AssistantStatus.failed => '질의 처리 실패',
    },
  };
  String get message {
    if (status == AssistantStatus.grounded) return answer!;
    if (reason == 'rule_engine_required') {
      return '졸업 가능 여부는 별도 졸업감사 결과로 확인해야 합니다. 졸업 요건 화면에서 확인해 주세요.';
    }
    if (reason == 'conflicting_admission_year') {
      return '질문 속 입학연도와 질의 정보가 다릅니다. 입학연도를 확인한 뒤 다시 질문해 주세요.';
    }
    final diagnostic = schoolQueryDiagnostic(reason);
    if (diagnostic != null) return diagnostic;
    return switch (status) {
      AssistantStatus.insufficientEvidence =>
        '현재 적용 가능한 승인 문서 근거가 부족합니다. 학교의 공식 안내를 확인해 주세요.',
      AssistantStatus.needsUserInput => '질의 정보를 보완한 뒤 다시 질문해 주세요.',
      AssistantStatus.failed when reason == 'answer_generator_not_configured' =>
        '답변 생성 기능이 준비 중입니다. 잠시 후 다시 확인해 주세요.',
      _ => '질의를 처리하지 못했습니다. 다시 시도해 주세요.',
    };
  }
}

/// Explain only the server's reported stage; missing evidence does not prove a bad UUID.
String? schoolQueryDiagnostic(String reason) => switch (reason) {
  'no_approved_matching_evidence' => '학교 자료 검색 API는 응답했지만, 이 질문과 학업 정보에 맞는 승인 문서가 조회되지 않았습니다. 관리자에서 학교·학과 연결과 문서 등록·승인·적용 범위를 확인해야 합니다. 자료가 등록돼 있다면 질문에 해당하는 내용이 포함됐는지도 확인해 주세요.',
  'document_context_not_approved_or_incomplete' => '검색된 학교 문서의 승인 또는 적용 범위가 확인되지 않았습니다. 관리자에서 문서의 검토 상태와 학생의 입학연도·이수경로에 적용되는지 확인해야 합니다.',
  'answer_generator_not_configured' =>
    '학교 자료는 검색됐지만 외부 AI 답변 생성기가 설정되지 않았습니다. 백엔드의 Vertex AI 연결 설정이 필요합니다.',
  'rag_processing_failed' =>
    '학교 자료 조회·검색 처리에 실패했습니다. 서버의 자료 연결과 검색 처리 상태를 확인해야 합니다.',
  'generator_reported_insufficient_evidence' =>
    '외부 AI가 조회된 자료만으로는 답변할 수 없다고 응답했습니다. 질문을 구체화하거나 관련 학교 자료를 확인해 주세요.',
  'invalid_generator_output' || 'invalid_generator_citations' => '외부 AI 응답 또는 인용을 검증하지 못해 답변을 표시하지 않았습니다. 다시 시도하고 문제가 계속되면 서버의 AI 응답 처리를 확인해야 합니다.',
  _ => null,
};

class AssistantApiException implements Exception {
  const AssistantApiException(
    this.message, {
    this.requestId,
    this.fields = const [],
  });
  final String message;
  final String? requestId;
  final List<String> fields;
}

abstract interface class AssistantGateway {
  Future<AssistantResult> query(String question, SchoolQueryContext context);
  void close();
}

class AssistantApi implements AssistantGateway {
  AssistantApi({
    http.Client? client,
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _baseUrl = resolveApiBaseUrl(baseUrl ?? configuredApiBaseUrl());
  final http.Client _client;
  final Uri _baseUrl;
  final Duration timeout;

  @override
  Future<AssistantResult> query(
    String question,
    SchoolQueryContext context,
  ) async {
    try {
      final response = await _client
          .post(
            _baseUrl.resolve('/api/v1/assistant/queries'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'question': question,
              'context': context.toJson(),
            }),
          )
          .timeout(timeout);
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final error = body['error'] as Map<String, dynamic>;
        throw AssistantApiException(
          response.statusCode == 422
              ? '입력값을 확인한 뒤 다시 질문해 주세요.'
              : '서버에서 질의를 처리하지 못했습니다. 다시 시도해 주세요.',
          requestId: error['request_id'] as String?,
          fields: (error['field_errors'] as List)
              .map((field) => (field as Map)['field'] as String)
              .toList(),
        );
      }
      return AssistantResult.fromJson(body);
    } on AssistantApiException {
      rethrow;
    } on TimeoutException {
      throw const AssistantApiException('응답 시간이 초과되었습니다. 다시 시도해 주세요.');
    } on http.ClientException {
      throw const AssistantApiException(
        '서버에 연결할 수 없습니다. 연결 상태를 확인하고 다시 시도해 주세요.',
      );
    } catch (_) {
      throw const AssistantApiException('서버 응답을 확인할 수 없습니다. 다시 시도해 주세요.');
    }
  }

  @override
  void close() => _client.close();
}
