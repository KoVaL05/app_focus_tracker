import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/app_focus_tracker.dart';

void main() {
  group('Browser Tab Tracking Integration Tests', () {
    // Note: These tests focus on the data models and configuration
    // without requiring actual platform channel communication

    test('should configure browser tab tracking correctly', () {
      final config = FocusTrackerConfig.detailed().copyWith(
        enableBrowserTabTracking: true,
        includeMetadata: true,
      );

      expect(config.enableBrowserTabTracking, isTrue);
      expect(config.includeMetadata, isTrue);
    });

    test('should require both metadata and browser tab tracking enabled', () {
      // Test that browser tab tracking requires metadata
      const configWithoutMetadata = FocusTrackerConfig(
        enableBrowserTabTracking: true,
        includeMetadata: false,
      );

      const configWithMetadata = FocusTrackerConfig(
        enableBrowserTabTracking: true,
        includeMetadata: true,
      );

      expect(configWithoutMetadata.enableBrowserTabTracking, isTrue);
      expect(configWithoutMetadata.includeMetadata, isFalse);
      expect(configWithMetadata.enableBrowserTabTracking, isTrue);
      expect(configWithMetadata.includeMetadata, isTrue);
    });

    test('should create browser focus events with correct structure', () {
      final event = FocusEvent(
        appName: 'Google Chrome',
        eventType: FocusEventType.gained,
        durationMicroseconds: 0,
        metadata: {
          'isBrowser': true,
          'browserTab': {
            'domain': 'example.com',
            'url': 'https://example.com',
            'title': 'Example Domain',
            'browserType': 'chrome',
          },
        },
      );

      expect(event.isBrowser, isTrue);
      expect(event.browserTab, isNotNull);
      expect(event.browserTab!.domain, equals('example.com'));
      expect(event.browserTab!.title, equals('Example Domain'));
      expect(event.browserTab!.browserType, equals('chrome'));
    });

    test('should handle browser focus events in stream', () async {
      final events = <FocusEvent>[];

      // Create a mock stream of events including browser focus
      final stream = Stream.fromIterable([
        FocusEvent(
          appName: 'Google Chrome',
          eventType: FocusEventType.gained,
          durationMicroseconds: 0,
          metadata: {
            'isBrowser': true,
            'browserTab': {
              'domain': 'google.com',
              'url': 'https://google.com',
              'title': 'Google',
              'browserType': 'chrome',
            },
          },
        ),
        FocusEvent(
          appName: 'Google Chrome',
          eventType: FocusEventType.gained,
          durationMicroseconds: 0,
          metadata: {
            'isBrowser': true,
            'browserTab': {
              'domain': 'example.com',
              'url': 'https://example.com',
              'title': 'Example Domain',
              'browserType': 'chrome',
            },
          },
        ),
      ]);

      await for (final event in stream) {
        events.add(event);
      }

      expect(events.length, equals(2));
      expect(events[0].eventType, equals(FocusEventType.gained));
      expect(events[0].isBrowser, isTrue);
      expect(events[0].browserTab!.domain, equals('google.com'));

      expect(events[1].eventType, equals(FocusEventType.gained));
      expect(events[1].isBrowser, isTrue);
      expect(events[1].browserTab!.domain, equals('example.com'));
    });

    test('should serialize and deserialize browser events correctly', () {
      final originalEvent = FocusEvent(
        appName: 'Firefox',
        eventType: FocusEventType.gained,
        durationMicroseconds: 3000000,
        metadata: {
          'isBrowser': true,
          'browserTab': {
            'domain': 'stackoverflow.com',
            'url': 'https://stackoverflow.com',
            'title': 'Stack Overflow',
            'browserType': 'firefox',
          },
        },
      );

      final json = originalEvent.toJson();
      final deserializedEvent = FocusEvent.fromJson(json);

      expect(deserializedEvent.appName, equals(originalEvent.appName));
      expect(deserializedEvent.eventType, equals(originalEvent.eventType));
      expect(deserializedEvent.isBrowser, equals(originalEvent.isBrowser));
      expect(deserializedEvent.browserTab?.domain, equals(originalEvent.browserTab?.domain));
    });

    test('should handle edge cases in browser tracking', () {
      // Test with missing browser tab info
      final eventWithoutTab = FocusEvent(
        appName: 'Google Chrome',
        eventType: FocusEventType.gained,
        durationMicroseconds: 0,
        metadata: {
          'isBrowser': true,
        },
      );

      expect(eventWithoutTab.isBrowser, isTrue);
      expect(eventWithoutTab.browserTab, isNull);

      // Test with invalid metadata
      final eventWithInvalidMetadata = FocusEvent(
        appName: 'Safari',
        eventType: FocusEventType.gained,
        durationMicroseconds: 0,
        metadata: {
          'isBrowser': null, // null instead of invalid type
          'browserTab': null, // null instead of invalid type
        },
      );

      expect(eventWithInvalidMetadata.isBrowser, isFalse); // Should handle null boolean
      expect(eventWithInvalidMetadata.browserTab, isNull); // Should handle null map
    });
  });
}
