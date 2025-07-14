import 'package:flutter_test/flutter_test.dart';

import 'package:app_focus_tracker/src/models/app_info.dart';
import 'package:app_focus_tracker/src/models/browser_tab_info.dart';

void main() {
  group('AppInfo Browser Extensions', () {
    test('isBrowser returns true when metadata flag is set', () {
      const info = AppInfo(
        name: 'Google Chrome',
        identifier: 'com.google.Chrome',
        metadata: {
          'isBrowser': true,
        },
      );

      expect(info.isBrowser, isTrue);
    });

    test('isBrowser returns false when flag missing or false', () {
      const info1 = AppInfo(
        name: 'Finder',
        identifier: 'com.apple.finder',
      );
      const info2 = AppInfo(
        name: 'Edge',
        identifier: 'com.microsoft.edgemac',
        metadata: {'isBrowser': false},
      );

      expect(info1.isBrowser, isFalse);
      expect(info2.isBrowser, isFalse);
    });

    test('browserTab parses tab metadata into BrowserTabInfo', () {
      const metadata = {
        'isBrowser': true,
        'browserTab': {
          'domain': 'example.com',
          'url': 'https://example.com',
          'title': 'Example Domain',
          'browserType': 'chrome',
        }
      };

      const info = AppInfo(
        name: 'Google Chrome - Example Domain',
        identifier: 'com.google.Chrome',
        metadata: metadata,
      );

      final BrowserTabInfo? tab = info.browserTab;
      expect(tab, isNotNull);
      expect(tab!.domain, equals('example.com'));
      expect(tab.url, equals('https://example.com'));
      expect(tab.title, equals('Example Domain'));
      expect(tab.browserType, equals('chrome'));
    });

    test('browserTab returns null when metadata absent', () {
      const info = AppInfo(
        name: 'Not a browser',
        identifier: 'com.test.app',
      );

      expect(info.browserTab, isNull);
    });
  });
}
