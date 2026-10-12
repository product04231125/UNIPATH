import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum AssistantStatus { grounded, insufficientEvidence, needsUserInput, failed }

class SchoolQueryContext {
  const SchoolQueryContext({
    this.institution,
    this.department,
    this.admissionYear,
    this.track,
  });
  final String? institution;
  final String? department;
  final int? admissionYear;
  final String? track;
  Map<String, Object?> toJson() => {
    'institution': institution,
    'department': department,
    'admission_year': admissionYear,
    'track': track,
  };
}

class AssistantCitation {
  AssistantCitation.fromJson(Map<String, dynamic> json)
    : chunkId = json['chunk_id'] as String,
      documentId = json['document_id'] as String,
      title = json['title'] as String,
      source = Uri.parse(json['source_url'] as String),
      page = json['page'] as int,
      excerpt = json['excerpt'] as String {
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
        },
    ],
  };

  String get label => switch (status) {
    AssistantStatus.grounded => '공식 문서 근거',
    AssistantStatus.insufficientEvidence => '공식 근거 부족',
    AssistantStatus.needsUserInput => '추가 확인 필요',
    AssistantStatus.failed => '질의 처리 실패',
  };
  String get message {
    if (status == AssistantStatus.grounded) return answer!;
    if (reason == 'rule_engine_required') {
      return '졸업 가능 여부는 별도 졸업감사로 확인해야 합니다. 현재 졸업감사 기능은 준비 중입니다.';
    }
    if (reason == 'conflicting_admission_year') {
      return '질문 속 입학연도와 질의 정보가 다릅니다. 입학연도를 확인한 뒤 다시 질문해 주세요.';
    }
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
       _baseUrl =
           baseUrl ??
           Uri.parse(
             const String.fromEnvironment(
               'API_BASE_URL',
               defaultValue: 'http://127.0.0.1:8010',
             ),
           );
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
