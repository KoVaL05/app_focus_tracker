import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/src/models/focus_tracker_config.dart';

void main() {
  group('FocusTrackerConfig', () {
    group('Default Constructor', () {
      test('creates config with default values', () {
        const config = FocusTrackerConfig();

        expect(config.updateIntervalMs, equals(1000));
        expect(config.includeMetadata, isFalse);
        expect(config.includeSystemApps, isFalse);
        expect(config.excludedApps, isEmpty);
        expect(config.includedApps, isEmpty);
        expect(config.enableBatching, isFalse);
        expect(config.maxBatchSize, equals(10));
        expect(config.maxBatchWaitMs, equals(5000));
        // New input tracking defaults
        expect(config.enableInputActivityTracking, isFalse);
        expect(config.inputSamplingIntervalMs, equals(1000));
        expect(config.inputIdleThresholdMs, equals(5000));
        expect(config.normalizeMouseToVirtualDesktop, isTrue);
        expect(config.countKeyRepeat, isTrue);
        expect(config.includeMiddleButtonClicks, isTrue);
      });

      test('creates config with custom values', () {
        final excludedApps = {'com.apple.finder', 'explorer.exe'};
        final includedApps = {'com.test.app1', 'com.test.app2'};

        final config = FocusTrackerConfig(
          updateIntervalMs: 2000,
          includeMetadata: true,
          includeSystemApps: true,
          excludedApps: excludedApps,
          includedApps: includedApps,
          enableBatching: true,
          maxBatchSize: 20,
          maxBatchWaitMs: 3000,
          enableInputActivityTracking: true,
          inputSamplingIntervalMs: 750,
          inputIdleThresholdMs: 4000,
          normalizeMouseToVirtualDesktop: false,
          countKeyRepeat: false,
          includeMiddleButtonClicks: false,
        );

        expect(config.updateIntervalMs, equals(2000));
        expect(config.includeMetadata, isTrue);
        expect(config.includeSystemApps, isTrue);
        expect(config.excludedApps, equals(excludedApps));
        expect(config.includedApps, equals(includedApps));
        expect(config.enableBatching, isTrue);
        expect(config.maxBatchSize, equals(20));
        expect(config.maxBatchWaitMs, equals(3000));
        expect(config.enableInputActivityTracking, isTrue);
        expect(config.inputSamplingIntervalMs, equals(750));
        expect(config.inputIdleThresholdMs, equals(4000));
        expect(config.normalizeMouseToVirtualDesktop, isFalse);
        expect(config.countKeyRepeat, isFalse);
        expect(config.includeMiddleButtonClicks, isFalse);
      });
    });

    group('Factory Constructors', () {
      test('performance() creates optimized config', () {
        final config = FocusTrackerConfig.performance();

        expect(config.updateIntervalMs, equals(2000));
        expect(config.includeMetadata, isFalse);
        expect(config.includeSystemApps, isFalse);
        expect(config.enableBatching, isTrue);
        expect(config.maxBatchSize, equals(20));
        expect(config.maxBatchWaitMs, equals(3000));
      });

      test('detailed() creates comprehensive config', () {
        final config = FocusTrackerConfig.detailed();

        expect(config.updateIntervalMs, equals(500));
        expect(config.includeMetadata, isTrue);
        expect(config.includeSystemApps, isTrue);
        expect(config.enableBatching, isFalse);
      });

      test('privacy() creates privacy-focused config', () {
        final config = FocusTrackerConfig.privacy();

        expect(config.updateIntervalMs, equals(1000));
        expect(config.includeMetadata, isFalse);
        expect(config.includeSystemApps, isFalse);
        expect(config.enableBatching, isTrue);

        // Should exclude common system apps
        expect(config.excludedApps, contains('com.apple.finder'));
        expect(config.excludedApps, contains('com.apple.dock'));
        expect(config.excludedApps, contains('explorer.exe'));
        expect(config.excludedApps, contains('dwm.exe'));
      });
    });

    group('JSON Serialization', () {
      test('converts to JSON correctly', () {
        final excludedApps = {'app1', 'app2'};
        final includedApps = {'app3', 'app4'};

        final config = FocusTrackerConfig(
          updateIntervalMs: 1500,
          includeMetadata: true,
          includeSystemApps: false,
          excludedApps: excludedApps,
          includedApps: includedApps,
          enableBatching: true,
          maxBatchSize: 15,
          maxBatchWaitMs: 4000,
        );

        final json = config.toJson();

        expect(json['updateIntervalMs'], equals(1500));
        expect(json['includeMetadata'], isTrue);
        expect(json['includeSystemApps'], isFalse);
        expect(json['excludedApps'], equals(['app1', 'app2']));
        expect(json['includedApps'], equals(['app3', 'app4']));
        expect(json['enableBatching'], isTrue);
        expect(json['maxBatchSize'], equals(15));
        expect(json['maxBatchWaitMs'], equals(4000));
        expect(json['enableInputActivityTracking'], isFalse);
        expect(json['inputSamplingIntervalMs'], equals(1500));
        expect(json['inputIdleThresholdMs'], equals(5000));
        expect(json['normalizeMouseToVirtualDesktop'], isTrue);
        expect(json['countKeyRepeat'], isTrue);
        expect(json['includeMiddleButtonClicks'], isTrue);
      });

      test('creates from JSON correctly', () {
        final json = {
          'updateIntervalMs': 1500,
          'includeMetadata': true,
          'includeSystemApps': false,
          'excludedApps': ['app1', 'app2'],
          'includedApps': ['app3', 'app4'],
          'enableBatching': true,
          'maxBatchSize': 15,
          'maxBatchWaitMs': 4000,
          'enableInputActivityTracking': true,
          'inputSamplingIntervalMs': 800,
          'inputIdleThresholdMs': 4500,
          'normalizeMouseToVirtualDesktop': false,
          'countKeyRepeat': false,
          'includeMiddleButtonClicks': false,
        };

        final config = FocusTrackerConfig.fromJson(json);

        expect(config.updateIntervalMs, equals(1500));
        expect(config.includeMetadata, isTrue);
        expect(config.includeSystemApps, isFalse);
        expect(config.excludedApps, equals({'app1', 'app2'}));
        expect(config.includedApps, equals({'app3', 'app4'}));
        expect(config.enableBatching, isTrue);
        expect(config.maxBatchSize, equals(15));
        expect(config.maxBatchWaitMs, equals(4000));
        expect(config.enableInputActivityTracking, isTrue);
        expect(config.inputSamplingIntervalMs, equals(800));
        expect(config.inputIdleThresholdMs, equals(4500));
        expect(config.normalizeMouseToVirtualDesktop, isFalse);
        expect(config.countKeyRepeat, isFalse);
        expect(config.includeMiddleButtonClicks, isFalse);
      });

      test('handles missing fields with defaults', () {
        final json = <String, dynamic>{};

        final config = FocusTrackerConfig.fromJson(json);

        expect(config.updateIntervalMs, equals(1000));
        expect(config.includeMetadata, isFalse);
        expect(config.includeSystemApps, isFalse);
        expect(config.excludedApps, isEmpty);
        expect(config.includedApps, isEmpty);
        expect(config.enableBatching, isFalse);
        expect(config.maxBatchSize, equals(10));
        expect(config.maxBatchWaitMs, equals(5000));
      });

      test('handles null app lists', () {
        final json = {
          'excludedApps': null,
          'includedApps': null,
        };

        final config = FocusTrackerConfig.fromJson(json);

        expect(config.excludedApps, isEmpty);
        expect(config.includedApps, isEmpty);
      });

      test('handles empty app lists', () {
        final json = {
          'excludedApps': <String>[],
          'includedApps': <String>[],
        };

        final config = FocusTrackerConfig.fromJson(json);

        expect(config.excludedApps, isEmpty);
        expect(config.includedApps, isEmpty);
      });
    });

    group('Copy With', () {
      test('copyWith creates new config with updated values', () {
        const original = FocusTrackerConfig(
          updateIntervalMs: 1000,
          includeMetadata: false,
          excludedApps: {'app1'},
        );

        final updated = original.copyWith(
          updateIntervalMs: 2000,
          includeMetadata: true,
          includedApps: {'app2'},
        );

        expect(updated.updateIntervalMs, equals(2000));
        expect(updated.includeMetadata, isTrue);
        expect(updated.includeSystemApps, equals(original.includeSystemApps));
        expect(updated.excludedApps, equals(original.excludedApps));
        expect(updated.includedApps, equals({'app2'}));
        expect(updated.enableBatching, equals(original.enableBatching));
        expect(updated.maxBatchSize, equals(original.maxBatchSize));
        expect(updated.maxBatchWaitMs, equals(original.maxBatchWaitMs));
      });

      test('copyWith with no parameters returns identical config', () {
        const original = FocusTrackerConfig(
          updateIntervalMs: 1500,
          includeMetadata: true,
          excludedApps: {'app1', 'app2'},
        );

        final copied = original.copyWith();

        expect(copied, equals(original));
      });

      test('copyWith can clear app lists', () {
        const original = FocusTrackerConfig(
          excludedApps: {'app1', 'app2'},
          includedApps: {'app3', 'app4'},
        );

        final cleared = original.copyWith(
          excludedApps: <String>{},
          includedApps: <String>{},
        );

        expect(cleared.excludedApps, isEmpty);
        expect(cleared.includedApps, isEmpty);
      });
    });

    group('Equality and HashCode', () {
      test('configs with same properties are equal', () {
        final excludedApps = {'app1', 'app2'};
        final includedApps = {'app3'};

        final config1 = FocusTrackerConfig(
          updateIntervalMs: 1500,
          includeMetadata: true,
          includeSystemApps: false,
          excludedApps: excludedApps,
          includedApps: includedApps,
          enableBatching: true,
          maxBatchSize: 15,
          maxBatchWaitMs: 4000,
        );

        final config2 = FocusTrackerConfig(
          updateIntervalMs: 1500,
          includeMetadata: true,
          includeSystemApps: false,
          excludedApps: excludedApps,
          includedApps: includedApps,
          enableBatching: true,
          maxBatchSize: 15,
          maxBatchWaitMs: 4000,
        );

        expect(config1, equals(config2));
        expect(config1.hashCode, equals(config2.hashCode));
      });

      test('configs with different properties are not equal', () {
        const config1 = FocusTrackerConfig(updateIntervalMs: 1000);
        const config2 = FocusTrackerConfig(updateIntervalMs: 2000);

        expect(config1, isNot(equals(config2)));
        expect(config1.hashCode, isNot(equals(config2.hashCode)));
      });

      test('configs with different app sets are not equal', () {
        const config1 = FocusTrackerConfig(excludedApps: {'app1'});
        const config2 = FocusTrackerConfig(excludedApps: {'app2'});

        expect(config1, isNot(equals(config2)));
        expect(config1.hashCode, isNot(equals(config2.hashCode)));
      });
    });

    group('String Representation', () {
      test('toString includes key configuration values', () {
        const config = FocusTrackerConfig(
          updateIntervalMs: 1500,
          includeMetadata: true,
          enableBatching: true,
        );

        final stringRepresentation = config.toString();

        expect(stringRepresentation, contains('1500'));
        expect(stringRepresentation, contains('true'));
        expect(stringRepresentation, contains('FocusTrackerConfig'));
      });
    });

    group('Edge Cases and Validation', () {
      test('handles very small update intervals', () {
        const config = FocusTrackerConfig(updateIntervalMs: 1);
        expect(config.updateIntervalMs, equals(1));
      });

      test('handles very large update intervals', () {
        const config = FocusTrackerConfig(updateIntervalMs: 3600000); // 1 hour
        expect(config.updateIntervalMs, equals(3600000));
      });

      test('handles large batch sizes', () {
        const config = FocusTrackerConfig(maxBatchSize: 1000);
        expect(config.maxBatchSize, equals(1000));
      });

      test('handles large batch wait times', () {
        const config = FocusTrackerConfig(maxBatchWaitMs: 60000); // 1 minute
        expect(config.maxBatchWaitMs, equals(60000));
      });

      test('handles large app sets', () {
        final largeAppSet = List.generate(1000, (i) => 'app$i').toSet();

        final config = FocusTrackerConfig(
          excludedApps: largeAppSet,
          includedApps: largeAppSet,
        );

        expect(config.excludedApps.length, equals(1000));
        expect(config.includedApps.length, equals(1000));
      });

      test('handles special characters in app identifiers', () {
        final specialApps = {
          'com.app-with_special.chars',
          'app with spaces',
          'app.with.dots',
          'app/with/slashes',
          'app:with:colons',
        };

        final config = FocusTrackerConfig(excludedApps: specialApps);

        expect(config.excludedApps, equals(specialApps));

        // Test JSON serialization with special characters
        final json = config.toJson();
        final recreated = FocusTrackerConfig.fromJson(json);

        expect(recreated.excludedApps, equals(specialApps));
      });

      test('handles unicode characters in app identifiers', () {
        final unicodeApps = {
          'com.测试.app',
          'app.with.émojis.🚀',
          'приложение.тест',
        };

        final config = FocusTrackerConfig(excludedApps: unicodeApps);

        expect(config.excludedApps, equals(unicodeApps));

        // Test JSON serialization with unicode
        final json = config.toJson();
        final recreated = FocusTrackerConfig.fromJson(json);

        expect(recreated.excludedApps, equals(unicodeApps));
      });
    });
  });

  group('Browser Tab Tracking Configuration', () {
    test('should have correct default value for enableBrowserTabTracking', () {
      const config = FocusTrackerConfig();
      expect(config.enableBrowserTabTracking, isFalse);
    });

    test('should enable browser tab tracking in detailed configuration', () {
      final config = FocusTrackerConfig.detailed();
      expect(config.enableBrowserTabTracking, isTrue);
    });

    test('should serialize and deserialize enableBrowserTabTracking correctly', () {
      const config = FocusTrackerConfig(
        enableBrowserTabTracking: true,
        includeMetadata: true,
      );

      final json = config.toJson();
      expect(json['enableBrowserTabTracking'], isTrue);

      final deserialized = FocusTrackerConfig.fromJson(json);
      expect(deserialized.enableBrowserTabTracking, isTrue);
    });

    test('should handle missing enableBrowserTabTracking in JSON', () {
      final json = {
        'updateIntervalMs': 1000,
        'includeMetadata': true,
      };

      final config = FocusTrackerConfig.fromJson(json);
      expect(config.enableBrowserTabTracking, isFalse);
    });

    test('should copy with enableBrowserTabTracking correctly', () {
      const original = FocusTrackerConfig(enableBrowserTabTracking: false);
      final copied = original.copyWith(enableBrowserTabTracking: true);

      expect(copied.enableBrowserTabTracking, isTrue);
      expect(original.enableBrowserTabTracking, isFalse);
    });

    test('should include enableBrowserTabTracking in equality comparison', () {
      const config1 = FocusTrackerConfig(enableBrowserTabTracking: true);
      const config2 = FocusTrackerConfig(enableBrowserTabTracking: false);
      const config3 = FocusTrackerConfig(enableBrowserTabTracking: true);

      expect(config1, equals(config3));
      expect(config1, isNot(equals(config2)));
    });

    test('should include enableBrowserTabTracking in hashCode', () {
      const config1 = FocusTrackerConfig(enableBrowserTabTracking: true);
      const config2 = FocusTrackerConfig(enableBrowserTabTracking: false);

      expect(config1.hashCode, isNot(equals(config2.hashCode)));
    });

    test('should include enableBrowserTabTracking in toString', () {
      const config = FocusTrackerConfig(enableBrowserTabTracking: true);
      final string = config.toString();

      expect(string, contains('enableBrowserTabTracking: true'));
    });
  });
}
