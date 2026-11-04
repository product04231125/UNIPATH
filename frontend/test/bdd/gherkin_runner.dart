import 'dart:io';

import 'package:cucumber_gherkin/cucumber_gherkin.dart';
import 'package:cucumber_messages/cucumber_messages.dart';
import 'package:flutter_test/flutter_test.dart';

typedef BddStep<T> = Future<void> Function(WidgetTester tester, T world);

/// Loads a Korean Gherkin feature and runs each pickle as `testWidgets`.
void runKoreanFeature<T>({
  required String featurePath,
  required T Function() createWorld,
  required Map<String, BddStep<T>> steps,
  Future<void> Function()? setUpEach,
  Future<void> Function()? tearDownEach,
}) {
  final file = _featureFile(featurePath);
  final source = file.readAsStringSync();
  final envelopes = generateMessages(source, featurePath);
  final errors = envelopes
      .map((envelope) => envelope.parseError)
      .whereType<ParseError>()
      .toList();
  if (errors.isNotEmpty) {
    final first = errors.first;
    fail(
      '${first.source.uri ?? featurePath}:${first.source.location?.line ?? '?'} '
      'Gherkin 파싱 실패: ${first.message}',
    );
  }
  final document = envelopes
      .map((envelope) => envelope.gherkinDocument)
      .whereType<GherkinDocument>()
      .firstOrNull;
  final lines = _stepLines(document);
  final pickles = envelopes
      .map((envelope) => envelope.pickle)
      .whereType<Pickle>()
      .toList();
  if (pickles.isEmpty) {
    fail('$featurePath 에서 실행할 시나리오가 없습니다.');
  }

  for (final pickle in pickles) {
    testWidgets(pickle.name, (tester) async {
      await setUpEach?.call();
      addTearDown(() async => tearDownEach?.call());
      final world = createWorld();
      for (final step in pickle.steps) {
        final text = step.text.trim();
        final handler = steps[text];
        if (handler == null) {
          final line = _lineFor(step, lines);
          fail('$featurePath:$line 미등록 스텝: $text');
        }
        await handler(tester, world);
      }
    });
  }
}

File _featureFile(String featurePath) {
  for (final candidate in [
    featurePath,
    '../$featurePath',
    '../../$featurePath',
  ]) {
    final file = File(candidate);
    if (file.existsSync()) return file;
  }
  throw StateError('feature 파일을 찾지 못했습니다: $featurePath');
}

Map<String, int> _stepLines(GherkinDocument? document) {
  final lines = <String, int>{};
  void addSteps(List<Step> steps) {
    for (final step in steps) {
      lines[step.id] = step.location.line;
    }
  }

  final feature = document?.feature;
  if (feature == null) return lines;
  for (final child in feature.children) {
    if (child.background != null) addSteps(child.background!.steps);
    if (child.scenario != null) addSteps(child.scenario!.steps);
    final rule = child.rule;
    if (rule != null) {
      for (final nested in rule.children) {
        if (nested.background != null) addSteps(nested.background!.steps);
        if (nested.scenario != null) addSteps(nested.scenario!.steps);
      }
    }
  }
  return lines;
}

int _lineFor(PickleStep step, Map<String, int> lines) {
  for (final id in step.astNodeIds) {
    final line = lines[id];
    if (line != null) return line;
  }
  return 0;
}
