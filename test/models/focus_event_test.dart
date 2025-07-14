import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/src/models/focus_event.dart';

void main() {
  group('FocusEvent', () {
    group('Constructor', () {
      test('creates FocusEvent with required parameters', () {
        final event = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 5000000,
        );

        expect(event.appName, equals('Test App'));
        expect(event.durationMicroseconds, equals(5000000));
        expect(event.eventType, equals(FocusEventType.gained));
        expect(event.timestamp, isA<DateTime>());
        expect(event.eventId, isNotEmpty);
      });

      test('creates FocusEvent with all parameters', () {
        final timestamp = DateTime.now();
        final metadata = {'version': '1.0.0', 'platform': 'test'};

        final event = FocusEvent(
          appName: 'Test App',
          appIdentifier: 'com.test.app',
          timestamp: timestamp,
          durationMicroseconds: 5000000,
          processId: 1234,
          eventType: FocusEventType.lost,
          eventId: 'test_event_id',
          sessionId: 'test_session',
          metadata: metadata,
        );

        expect(event.appName, equals('Test App'));
        expect(event.appIdentifier, equals('com.test.app'));
        expect(event.timestamp, equals(timestamp));
        expect(event.durationMicroseconds, equals(5000000));
        expect(event.processId, equals(1234));
        expect(event.eventType, equals(FocusEventType.lost));
        expect(event.eventId, equals('test_event_id'));
        expect(event.sessionId, equals('test_session'));
        expect(event.metadata, equals(metadata));
      });
    });

    group('JSON Serialization', () {
      test('converts to JSON correctly', () {
        final timestamp = DateTime.fromMicrosecondsSinceEpoch(1234567890000000);
        final event = FocusEvent(
          appName: 'Test App',
          appIdentifier: 'com.test.app',
          timestamp: timestamp,
          durationMicroseconds: 5000000,
          processId: 1234,
          eventType: FocusEventType.durationUpdate,
          eventId: 'test_event_id',
          sessionId: 'test_session',
          metadata: {'version': '1.0.0'},
        );

        final json = event.toJson();

        expect(json['appName'], equals('Test App'));
        expect(json['appIdentifier'], equals('com.test.app'));
        expect(json['timestamp'], equals(1234567890000000));
        expect(json['durationMicroseconds'], equals(5000000));
        expect(json['processId'], equals(1234));
        expect(json['eventType'], equals('durationUpdate'));
        expect(json['eventId'], equals('test_event_id'));
        expect(json['sessionId'], equals('test_session'));
        expect(json['metadata'], equals({'version': '1.0.0'}));
      });

      test('creates from JSON correctly', () {
        final json = {
          'appName': 'Test App',
          'appIdentifier': 'com.test.app',
          'timestamp': 1234567890000000,
          'durationMicroseconds': 5000000,
          'processId': 1234,
          'eventType': 'lost',
          'eventId': 'test_event_id',
          'sessionId': 'test_session',
          'metadata': {'version': '1.0.0'},
        };

        final event = FocusEvent.fromJson(json);

        expect(event.appName, equals('Test App'));
        expect(event.appIdentifier, equals('com.test.app'));
        expect(event.timestamp.microsecondsSinceEpoch, equals(1234567890000000));
        expect(event.durationMicroseconds, equals(5000000));
        expect(event.processId, equals(1234));
        expect(event.eventType, equals(FocusEventType.lost));
        expect(event.eventId, equals('test_event_id'));
        expect(event.sessionId, equals('test_session'));
        expect(event.metadata, equals({'version': '1.0.0'}));
      });

      test('handles legacy duration formats', () {
        // Test legacy 'duration' field in milliseconds
        final legacyJson1 = {
          'appName': 'Test App',
          'duration': 5000, // 5 seconds in milliseconds
        };

        final event1 = FocusEvent.fromJson(legacyJson1);
        expect(event1.durationMicroseconds, equals(5000000)); // Converted to microseconds

        // Test legacy 'durationMs' field
        final legacyJson2 = {
          'appName': 'Test App',
          'durationMs': 3000,
        };

        final event2 = FocusEvent.fromJson(legacyJson2);
        expect(event2.durationMicroseconds, equals(3000000));
      });

      test('handles missing optional fields', () {
        final json = {
          'appName': 'Test App',
        };

        final event = FocusEvent.fromJson(json);

        expect(event.appName, equals('Test App'));
        expect(event.appIdentifier, isNull);
        expect(event.durationMicroseconds, equals(0));
        expect(event.processId, isNull);
        expect(event.eventType, equals(FocusEventType.gained));
        expect(event.metadata, isNull);
      });
    });

    group('Duration Properties', () {
      test('converts duration to milliseconds', () {
        final event = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 5500000, // 5.5 seconds
        );

        expect(event.durationMs, equals(5500));
      });

      test('converts duration to seconds', () {
        final event = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 7500000, // 7.5 seconds
        );

        expect(event.durationSeconds, equals(7.5));
      });

      test('formats duration correctly', () {
        // Less than 60 seconds
        final event1 = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 30500000, // 30.5 seconds
        );
        expect(event1.durationFormatted, equals('30.5s'));

        // Minutes and seconds
        final event2 = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 125000000, // 2 minutes 5 seconds
        );
        expect(event2.durationFormatted, equals('2m 5s'));

        // Hours and minutes
        final event3 = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 7380000000, // 2 hours 3 minutes
        );
        expect(event3.durationFormatted, equals('2h 3m'));
      });
    });

    group('Event Significance', () {
      test('identifies significant events correctly', () {
        // Gained event is always significant
        final gainedEvent = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 1000000,
          eventType: FocusEventType.gained,
        );
        expect(gainedEvent.isSignificantEvent, isTrue);

        // Lost event is always significant
        final lostEvent = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 1000000,
          eventType: FocusEventType.lost,
        );
        expect(lostEvent.isSignificantEvent, isTrue);

        // Duration update less than 5 seconds is not significant
        final shortUpdate = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 3000000, // 3 seconds
          eventType: FocusEventType.durationUpdate,
        );
        expect(shortUpdate.isSignificantEvent, isFalse);

        // Duration update 5 seconds or more is significant
        final longUpdate = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 6000000, // 6 seconds
          eventType: FocusEventType.durationUpdate,
        );
        expect(longUpdate.isSignificantEvent, isTrue);
      });
    });

    group('Copy Methods', () {
      test('copyWithDuration creates new event with updated duration', () {
        final original = FocusEvent(
          appName: 'Test App',
          appIdentifier: 'com.test.app',
          durationMicroseconds: 1000000,
          processId: 1234,
          eventType: FocusEventType.gained,
          sessionId: 'test_session',
        );

        final updated = original.copyWithDuration(5000000);

        expect(updated.appName, equals(original.appName));
        expect(updated.appIdentifier, equals(original.appIdentifier));
        expect(updated.durationMicroseconds, equals(5000000));
        expect(updated.processId, equals(original.processId));
        expect(updated.eventType, equals(FocusEventType.durationUpdate));
        expect(updated.sessionId, equals(original.sessionId));
        expect(updated.eventId, isNot(equals(original.eventId))); // New event ID
      });

      test('copyWithEventType creates new event with updated type', () {
        final original = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 1000000,
          eventType: FocusEventType.gained,
        );

        final updated = original.copyWithEventType(FocusEventType.lost);

        expect(updated.appName, equals(original.appName));
        expect(updated.durationMicroseconds, equals(original.durationMicroseconds));
        expect(updated.eventType, equals(FocusEventType.lost));
        expect(updated.eventId, equals(original.eventId)); // Same event ID
      });
    });

    group('Equality and HashCode', () {
      test('events with same properties are equal', () {
        final timestamp = DateTime.now();
        final event1 = FocusEvent(
          appName: 'Test App',
          appIdentifier: 'com.test.app',
          timestamp: timestamp,
          durationMicroseconds: 1000000,
          processId: 1234,
          eventType: FocusEventType.gained,
          eventId: 'test_id',
          sessionId: 'session',
        );

        final event2 = FocusEvent(
          appName: 'Test App',
          appIdentifier: 'com.test.app',
          timestamp: timestamp,
          durationMicroseconds: 1000000,
          processId: 1234,
          eventType: FocusEventType.gained,
          eventId: 'test_id',
          sessionId: 'session',
        );

        expect(event1, equals(event2));
        expect(event1.hashCode, equals(event2.hashCode));
      });

      test('events with different properties are not equal', () {
        final event1 = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 1000000,
        );

        final event2 = FocusEvent(
          appName: 'Different App',
          durationMicroseconds: 1000000,
        );

        expect(event1, isNot(equals(event2)));
        expect(event1.hashCode, isNot(equals(event2.hashCode)));
      });
    });

    group('Age Calculation', () {
      test('calculates event age correctly', () {
        final pastTime = DateTime.now().subtract(const Duration(seconds: 5));
        final event = FocusEvent(
          appName: 'Test App',
          timestamp: pastTime,
          durationMicroseconds: 1000000,
        );

        final age = event.ageMicroseconds;

        // Should be approximately 5 seconds in microseconds
        expect(age, greaterThan(4000000)); // At least 4 seconds
        expect(age, lessThan(6000000)); // Less than 6 seconds
      });
    });

    group('Event ID Generation', () {
      test('generates unique event IDs', () {
        final event1 = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 1000000,
        );

        final event2 = FocusEvent(
          appName: 'Test App',
          durationMicroseconds: 1000000,
        );

        expect(event1.eventId, isNot(equals(event2.eventId)));
        expect(event1.eventId, startsWith('evt_'));
        expect(event2.eventId, startsWith('evt_'));
      });
    });

    group('Browser Information', () {
      test('isBrowser returns true when metadata flag is set', () {
        final event = FocusEvent(
          appName: 'Google Chrome',
          durationMicroseconds: 1000,
          metadata: {'isBrowser': true},
        );

        expect(event.isBrowser, isTrue);
      });

      test('isBrowser returns false when flag missing or false', () {
        final event1 = FocusEvent(
          appName: 'Finder',
          durationMicroseconds: 1000,
        );
        final event2 = FocusEvent(
          appName: 'Edge',
          durationMicroseconds: 1000,
          metadata: {'isBrowser': false},
        );

        expect(event1.isBrowser, isFalse);
        expect(event2.isBrowser, isFalse);
      });

      test('browserTab parses tab metadata into BrowserTabInfo', () {
        final metadata = {
          'isBrowser': true,
          'browserTab': {
            'domain': 'example.com',
            'url': 'https://example.com',
            'title': 'Example Domain',
            'browserType': 'chrome',
          }
        };

        final event = FocusEvent(
          appName: 'Google Chrome - Example Domain',
          durationMicroseconds: 1000,
          metadata: metadata,
        );

        final tab = event.browserTab;
        expect(tab, isNotNull);
        expect(tab!.domain, equals('example.com'));
        expect(tab.url, equals('https://example.com'));
        expect(tab.title, equals('Example Domain'));
        expect(tab.browserType, equals('chrome'));
      });

      test('browserTab returns null when metadata absent', () {
        final event = FocusEvent(
          appName: 'Not a browser',
          durationMicroseconds: 1000,
        );

        expect(event.browserTab, isNull);
      });
    });
  });
}
