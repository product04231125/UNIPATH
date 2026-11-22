import '../auth/auth_api.dart';
import 'job_analysis_models.dart';

class JobAnalysisApi {
  const JobAnalysisApi(this.api);
  final ApiGateway api;

  Future<JobAnalysisResponse> analyze(JobAnalysisRequest request) async {
    final result = JobAnalysisResponse.fromJson(
      (await api.request('POST', 'me/job-analyses', request.toJson()))!,
    );
    if ((result.status == 'completed') != result.comparisons.isNotEmpty) {
      throw const FormatException('Inconsistent job analysis result');
    }
    final selected = {
      for (final row in request.records)
        '${row.kind}/${row.recordId}/${row.expectedVersion}',
      // Files picked from 내 자료 become request-scoped records the server reports as sources.
      if (request.documents.isNotEmpty)
        for (final source in result.documentSources)
          'experience/${source.recordId}/1',
    };
    if (request.documents.isEmpty && result.documentSources.isNotEmpty) {
      throw const FormatException('Unexpected document sources');
    }
    final points = request.postingText.runes.toList();
    final ids = <String>{};
    for (final row in result.comparisons) {
      final source = row.postingEvidence;
      if (!ids.add(row.requirementId) ||
          source.start < 0 ||
          source.end <= source.start ||
          source.end > points.length ||
          String.fromCharCodes(points.sublist(source.start, source.end)) !=
              source.excerpt ||
          (row.status != 'insufficient_evidence' &&
              row.personalEvidence.isEmpty)) {
        throw const FormatException('Invalid job analysis evidence');
      }
      for (final evidence in row.personalEvidence) {
        if (!selected.contains(
          '${evidence.kind}/${evidence.recordId}/${evidence.version}',
        )) {
          throw const FormatException('Unexpected personal evidence');
        }
      }
    }
    return result;
  }
}
