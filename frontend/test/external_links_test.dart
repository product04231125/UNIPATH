import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:university_path_frontend/shared/external_links.dart';
import 'package:university_path_frontend/shared/widgets/external_link_button.dart';
import 'package:university_path_frontend/features/records/activity/activity_page.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_page.dart';
import 'package:university_path_frontend/features/records/personal_record_fields.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

Finder openButton() => find.widgetWithText(FilledButton, '외부 사이트 열기');

class TestLauncher extends UrlLauncherPlatform {
  @override
  LinkDelegate? get linkDelegate => null;
  String? url;
  LaunchOptions? options;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    this.url = url;
    this.options = options;
    return true;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'default browser adapter requests external application and a new tab',
    () async {
      final previous = UrlLauncherPlatform.instance;
      final launcher = TestLauncher();
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      expect(
        await openBrowserLink(Uri.parse('https://example.com/synthetic')),
        isTrue,
      );
      expect(launcher.url, 'https://example.com/synthetic');
      expect(launcher.options!.mode, PreferredLaunchMode.externalApplication);
      expect(launcher.options!.webOnlyWindowName, '_blank');
    },
  );

  test(
    'browser links and record inputs reject non-browser or credential URLs',
    () {
      for (final raw in [
        'javascript:alert(1)',
        'file:///C:/test',
        'mailto:mock@example.com',
        'https://user:password@example.com',
        'https://',
        'https://example.com/a b',
        'https://example.com/\nfoo',
        'https://example.com\\foo',
      ]) {
        expect(browserLink(raw), isNull, reason: raw);
        expect(
          const PersonalRecordField(
            'url',
            '링크',
            type: PersonalFieldType.url,
          ).validate(raw),
          isNotNull,
        );
      }
      expect(
        browserLink(' https://example.com/자료?q=1#section ')?.host,
        'example.com',
      );
    },
  );

  for (final outcome in ['success', 'false', 'exception']) {
    testWidgets('external link requires confirmation and handles $outcome', (
      tester,
    ) async {
      final calls = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExternalLinkButton(
              url: 'https://example.com/evidence',
              label: '합성 링크',
              opener: (uri) async {
                calls.add(uri);
                if (outcome == 'exception') throw StateError('synthetic');
                return outcome == 'success';
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('합성 링크 · 외부 열기'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('합성 링크 · 외부 열기'));
      await tester.pumpAndSettle();
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      expect(calls.single.toString(), 'https://example.com/evidence');
      if (outcome == 'success') {
        expect(find.byType(AlertDialog), findsNothing);
      } else {
        expect(find.textContaining('열지 못했습니다.'), findsOneWidget);
        expect(openButton().hitTestable(), findsOneWidget);
        expect(find.text('링크 복사').hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid stored links cannot be opened or copied', (
    tester,
  ) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExternalLinkButton(
            url: 'javascript:alert(1)',
            label: '잘못된 링크',
            opener: (_) async {
              called = true;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('잘못된 링크 · 외부 열기'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(openButton()).onPressed, isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '링크 복사'))
          .onPressed,
      isNull,
    );
    expect(called, isFalse);
  });

  testWidgets('copy fallback copies only the displayed validated URL', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExternalLinkButton(
            url: 'https://example.com/synthetic',
            label: '복사할 링크',
          ),
        ),
      ),
    );
    await tester.tap(find.text('복사할 링크 · 외부 열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('링크 복사'));
    await tester.pumpAndSettle();
    expect(copied, 'https://example.com/synthetic');
    expect(find.text('링크를 복사했습니다.'), findsOneWidget);
  });

  testWidgets(
    '1365 link is available without fixtures and does not change personal records',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = PersonalRecordRepository(PersonalRecordKind.activity);
      await repository.load();
      await repository.save(
        PersonalRecord(
          id: 'synthetic-activity',
          values: {
            'title': '합성 봉사',
            'reportedHours': '4',
            'approval': 'pending',
          },
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ActivityPage(showMockData: false)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1365 봉사 찾기 · 외부 열기'));
      await tester.pumpAndSettle();
      expect(find.text('https://www.1365.go.kr/'), findsOneWidget);
      expect(find.textContaining('자동 변경하지 않습니다.'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      final reloaded = PersonalRecordRepository(PersonalRecordKind.activity);
      await reloaded.load();
      expect(reloaded.records.single.values, repository.records.single.values);
    },
  );

  testWidgets(
    'personal portfolio links open a confirmation without uploading or editing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = PersonalRecordRepository(PersonalRecordKind.portfolio);
      await repository.load();
      await repository.save(
        PersonalRecord(
          id: 'synthetic-work',
          values: {
            'title': '합성 성과',
            'evidenceUrl': 'https://example.com/synthetic-work',
          },
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PortfolioPage(showMockData: false)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('공개 가능한 링크 · 외부 열기'));
      await tester.pumpAndSettle();
      expect(find.text('https://example.com/synthetic-work'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.text('합성 성과'), findsOneWidget);
    },
  );

  testWidgets('long link dialog fits a narrow enlarged window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ExternalLinkButton(
            url: 'https://example.com/${'a' * 200}',
            label: '긴 링크',
          ),
        ),
      ),
    );
    await tester.tap(find.text('긴 링크 · 외부 열기'));
    await tester.pumpAndSettle();
    expect(openButton().hitTestable(), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
