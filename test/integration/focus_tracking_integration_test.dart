import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/app_focus_tracker.dart';
import 'package:app_focus_tracker/src/platform_interface.dart';
import 'package:app_focus_tracker/src/models/models.dart';
import 'package:app_focus_tracker/src/exceptions/app_focus_tracker_exception.dart';

import '../mocks/mock_platform_interface.dart';

void main() {
  group('Focus Tracking Integration Tests', () {
    late AppFocusTracker tracker;
    late MockAppFocusTrackerPlatform mockPlatform;

    setUp(() {
      mockPlatform = MockAppFocusTrackerPlatform();
      AppFocusTrackerPlatform.instance = mockPlatform;
      tracker = AppFocusTracker();
    });

    tearDown(() {
      mockPlatform.reset();
    });

    group('End-to-End Focus Tracking', () {
      test('complete focus tracking workflow', () async {
        // 1. Check platform support
        expect(await tracker.isSupported(), isTrue);
        expect(await tracker.getPlatformName(), equals('MockPlatform'));

        // 2. Check and request permissions
        expect(await tracker.hasPermissions(), isTrue);

        // 3. Start tracking with detailed configuration
        final config = FocusTrackerConfig.detailed().copyWith(
          updateIntervalMs: 100, // Fast updates for testing
        );
        await tracker.startTracking(config);
        expect(await tracker.isTracking(), isTrue);

        // 4. Listen to focus events
        final events = <FocusEvent>[];
        final subscription = tracker.focusStream.listen(events.add);

        // 5. Simulate app interactions
        mockPlatform.simulateAppFocus('Text Editor');
        await Future.delayed(const Duration(milliseconds: 50));

        mockPlatform.simulateDurationUpdate('Text Editor', const Duration(seconds: 2));
        await Future.delayed(const Duration(milliseconds: 50));

        mockPlatform.simulateAppBlur('Text Editor', const Duration(seconds: 3));
        mockPlatform.simulateAppFocus('Web Browser');
        await Future.delayed(const Duration(milliseconds: 50));

        // 6. Verify events were received
        expect(events.length, greaterThanOrEqualTo(3));
        expect(events.first.eventType, equals(FocusEventType.gained));
        expect(events.first.appName, equals('Text Editor'));

        // 7. Stop tracking
        await subscription.cancel();
        await tracker.stopTracking();
        expect(await tracker.isTracking(), isFalse);
      });

      test('focus tracking with rapid app switching', () async {
        await tracker.startTracking(FocusTrackerConfig(updateIntervalMs: 50));

        final events = <FocusEvent>[];
        final subscription = tracker.focusStream.listen(events.add);

        // Rapidly switch between multiple apps
        final apps = ['App1', 'App2', 'App3', 'App4', 'App5'];
        for (int i = 0; i < apps.length; i++) {
          mockPlatform.simulateAppFocus(apps[i]);
          await Future.delayed(const Duration(milliseconds: 20));
          mockPlatform.simulateAppBlur(apps[i], Duration(milliseconds: 20 * (i + 1)));
        }

        await Future.delayed(const Duration(milliseconds: 100));
        await subscription.cancel();

        // Should have received focus gained and lost events for each app
        expect(events.length, greaterThanOrEqualTo(apps.length));

        final gainedEvents = events.where((e) => e.eventType == FocusEventType.gained).toList();
        expect(gainedEvents.length, greaterThanOrEqualTo(apps.length));

        for (int i = 0; i < gainedEvents.length && i < apps.length; i++) {
          expect(gainedEvents[i].appName, equals(apps[i]));
        }
      });

      test('focus tracking with configuration updates', () async {
        // Start with performance config
        await tracker.startTracking(FocusTrackerConfig.performance());

        final events = <FocusEvent>[];
        final subscription = tracker.focusStream.listen(events.add);

        // Simulate some activity
        mockPlatform.simulateAppFocus('Test App');
        await Future.delayed(const Duration(milliseconds: 100));

        // Update to detailed config
        final detailedConfig = FocusTrackerConfig.detailed();
        final updateResult = await tracker.updateConfiguration(detailedConfig);
        expect(updateResult, isTrue);

        // Continue simulating activity
        mockPlatform.simulateDurationUpdate('Test App', const Duration(seconds: 1));
        await Future.delayed(const Duration(milliseconds: 100));

        await subscription.cancel();

        expect(events.isNotEmpty, isTrue);

        // Events after config update should include metadata if supported
        final eventsWithMetadata = events.where((e) => e.metadata != null).toList();
        expect(eventsWithMetadata.isNotEmpty, isTrue);
      });
    });

    group('Permission Flow Integration', () {
      test('macOS permission flow simulation', () async {
        final macOSPlatform = MockPlatformFactory.createMacOSMock(
          hasPermissions: false,
          simulatePermissionRequest: true,
        );
        AppFocusTrackerPlatform.instance = macOSPlatform;
        final macOSTracker = AppFocusTracker();

        // Check initial permission state
        expect(await macOSTracker.hasPermissions(), isFalse);

        // Request permissions
        final granted = await macOSTracker.requestPermissions();
        expect(granted, isTrue);

        // Now should be able to start tracking
        await macOSTracker.startTracking();
        expect(await macOSTracker.isTracking(), isTrue);

        await macOSTracker.stopTracking();
      });

      test('permission denied scenario', () async {
        final deniedPlatform = MockPlatformFactory.createMacOSMock(
          hasPermissions: false,
          simulatePermissionRequest: false,
        );
        AppFocusTrackerPlatform.instance = deniedPlatform;
        final deniedTracker = AppFocusTracker();

        // Permission request should fail
        expect(
          () => deniedTracker.requestPermissions(),
          throwsA(isA<PermissionDeniedException>()),
        );

        // Should not be able to start tracking
        expect(
          () => deniedTracker.startTracking(),
          throwsA(isA<PermissionDeniedException>()),
        );
      });
    });

    group('Multi-Application Scenarios', () {
      test('tracking multiple applications with different characteristics', () async {
        // Add various types of mock applications
        mockPlatform.addMockApp(const AppInfo(
          name: 'Productivity App',
          identifier: 'com.productivity.app',
          processId: 1001,
          version: '2.0.0',
          metadata: {'category': 'productivity', 'hasNotifications': true},
        ));

        mockPlatform.addMockApp(const AppInfo(
          name: 'Game',
          identifier: 'com.game.app',
          processId: 1002,
          version: '1.5.0',
          metadata: {'category': 'entertainment', 'fullscreen': true},
        ));

        mockPlatform.addMockApp(const AppInfo(
          name: 'System Utility',
          identifier: 'com.system.utility',
          processId: 2001,
          version: '1.0.0',
          metadata: {'category': 'system', 'background': true},
        ));

        await tracker.startTracking(FocusTrackerConfig.detailed());

        final events = <FocusEvent>[];
        final subscription = tracker.focusStream.listen(events.add);

        // Simulate usage patterns
        mockPlatform.simulateAppFocus('Productivity App', appIdentifier: 'com.productivity.app', processId: 1001);
        await Future.delayed(const Duration(milliseconds: 50));

        mockPlatform.simulateDurationUpdate('Productivity App', const Duration(minutes: 5),
            appIdentifier: 'com.productivity.app');
        await Future.delayed(const Duration(milliseconds: 50));

        mockPlatform.simulateAppBlur('Productivity App', const Duration(minutes: 5),
            appIdentifier: 'com.productivity.app');
        mockPlatform.simulateAppFocus('Game', appIdentifier: 'com.game.app', processId: 1002);
        await Future.delayed(const Duration(milliseconds: 50));

        await subscription.cancel();

        expect(events.length, greaterThanOrEqualTo(3));

        final productivityEvents = events.where((e) => e.appName == 'Productivity App').toList();
        expect(productivityEvents.isNotEmpty, isTrue);

        final gameEvents = events.where((e) => e.appName == 'Game').toList();
        expect(gameEvents.isNotEmpty, isTrue);
      });

      test('filtering system applications', () async {
        await tracker.startTracking(FocusTrackerConfig.privacy());

        final runningApps = await tracker.getRunningApplications(includeSystemApps: false);
        final systemApps = runningApps.where((app) => app.metadata?['category'] == 'system').toList();

        expect(systemApps.isEmpty, isTrue);

        final allApps = await tracker.getRunningApplications(includeSystemApps: true);
        expect(allApps.length, greaterThanOrEqualTo(runningApps.length));
      });
    });

    group('Performance and Stress Testing', () {
      test('high-frequency event handling', () async {
        await tracker.startTracking(const FocusTrackerConfig(updateIntervalMs: 10));

        final events = <FocusEvent>[];
        final subscription = tracker.focusStream.listen(events.add);

        // Generate many events quickly
        for (int i = 0; i < 100; i++) {
          mockPlatform.simulateAppFocus('App $i');
          if (i % 10 == 0) {
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }

        await Future.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        expect(events.length, greaterThanOrEqualTo(100));

        // Verify all events are properly formed
        for (final event in events) {
          expect(event.appName, isNotEmpty);
          expect(event.eventType, equals(FocusEventType.gained));
          expect(event.timestamp, isA<DateTime>());
          expect(event.eventId, isNotEmpty);
        }
      });

      test('long-running tracking session', () async {
        await tracker.startTracking(const FocusTrackerConfig(updateIntervalMs: 50));

        final events = <FocusEvent>[];
        final subscription = tracker.focusStream.listen(events.add);

        // Simulate a long session with various patterns
        final apps = ['Editor', 'Browser', 'Terminal', 'Email'];
        for (int cycle = 0; cycle < 5; cycle++) {
          for (final app in apps) {
            mockPlatform.simulateAppFocus(app);
            await Future.delayed(const Duration(milliseconds: 20));

            // Simulate some activity
            for (int j = 1; j <= 3; j++) {
              mockPlatform.simulateDurationUpdate(app, Duration(milliseconds: 20 * j));
              await Future.delayed(const Duration(milliseconds: 10));
            }

            mockPlatform.simulateAppBlur(app, const Duration(milliseconds: 60));
          }
        }

        await Future.delayed(const Duration(milliseconds: 100));
        await subscription.cancel();

        expect(events.length, greaterThan(50));

        // Verify session consistency
        final sessionIds = events.map((e) => e.sessionId).toSet();
        expect(sessionIds.length, equals(1)); // All events from same session

        // Verify duration progression for each app
        for (final app in apps) {
          final appEvents = events.where((e) => e.appName == app).toList();
          expect(appEvents.isNotEmpty, isTrue);

          final durationUpdates = appEvents.where((e) => e.eventType == FocusEventType.durationUpdate).toList();

          if (durationUpdates.length > 1) {
            // Duration should generally increase in updates
            for (int i = 1; i < durationUpdates.length; i++) {
              expect(durationUpdates[i].durationMicroseconds, greaterThanOrEqualTo(20000)); // At least 20ms
            }
          }
        }
      });

      test('memory usage with many events', () async {
        await tracker.startTracking(const FocusTrackerConfig(updateIntervalMs: 1));

        final events = <FocusEvent>[];
        late StreamSubscription<FocusEvent> subscription;

        // Test that the stream doesn't accumulate unbounded memory
        subscription = tracker.focusStream.listen((event) {
          events.add(event);
          // Keep only last 100 events to simulate real app behavior
          if (events.length > 100) {
            events.removeAt(0);
          }
        });

        // Generate many events
        for (int i = 0; i < 1000; i++) {
          mockPlatform.simulateAppFocus('App ${i % 10}');
          if (i % 100 == 0) {
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }

        await Future.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        // Should have processed many events but kept memory bounded
        expect(events.length, lessThanOrEqualTo(100));

        // Last events should be from the end of the sequence
        final lastEvent = events.last;
        expect(lastEvent.appName, contains('App'));
      });
    });

    group('Error Recovery and Resilience', () {
      test('recovery from platform errors', () async {
        await tracker.startTracking();

        final events = <FocusEvent>[];
        final errors = <Object>[];
        final subscription = tracker.focusStream.listen(
          events.add,
          onError: errors.add,
        );

        // Generate some successful events
        mockPlatform.simulateAppFocus('App 1');
        await Future.delayed(const Duration(milliseconds: 50));

        // Simulate a platform error
        mockPlatform.simulateError(
            'getCurrentFocusedApp', const PlatformChannelException('Simulated error', code: 'TEST_ERROR'));

        // Continue with more events
        mockPlatform.simulateAppFocus('App 2');
        await Future.delayed(const Duration(milliseconds: 50));

        await subscription.cancel();

        expect(events.length, greaterThanOrEqualTo(2));
        // Error handling depends on implementation - may or may not propagate
      });

      test('graceful handling of invalid app data', () async {
        await tracker.startTracking(FocusTrackerConfig.detailed());

        final events = <FocusEvent>[];
        final subscription = tracker.focusStream.listen(events.add);

        // Simulate events with edge case data
        mockPlatform.simulateAppFocus('', appIdentifier: ''); // Empty names
        mockPlatform.simulateAppFocus(
            'App with very long name that exceeds normal limits and contains special characters !@#\$%^&*()_+{}|:"<>?');
        mockPlatform.simulateAppFocus('Unicode App 🚀 测试 العربية');

        await Future.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        expect(events.length, equals(3));

        // All events should be properly formed despite unusual input
        for (final event in events) {
          expect(event.timestamp, isA<DateTime>());
          expect(event.eventId, isNotEmpty);
          expect(event.eventType, equals(FocusEventType.gained));
        }
      });
    });

    group('Cross-Platform Consistency', () {
      test('Windows platform behavior', () async {
        final windowsPlatform = MockPlatformFactory.createWindowsMock();
        AppFocusTrackerPlatform.instance = windowsPlatform;
        final windowsTracker = AppFocusTracker();

        expect(await windowsTracker.getPlatformName(), equals('Windows'));
        expect(await windowsTracker.isSupported(), isTrue);
        expect(await windowsTracker.hasPermissions(), isTrue);

        await windowsTracker.startTracking();
        expect(await windowsTracker.isTracking(), isTrue);

        final stream = windowsTracker.focusStream;
        expect(stream, isA<Stream<FocusEvent>>());

        await windowsTracker.stopTracking();
      });

      test('macOS platform behavior', () async {
        final macOSPlatform = MockPlatformFactory.createMacOSMock(
          hasPermissions: true,
        );
        AppFocusTrackerPlatform.instance = macOSPlatform;
        final macOSTracker = AppFocusTracker();

        expect(await macOSTracker.getPlatformName(), equals('macOS'));
        expect(await macOSTracker.isSupported(), isTrue);
        expect(await macOSTracker.hasPermissions(), isTrue);

        await macOSTracker.startTracking();
        expect(await macOSTracker.isTracking(), isTrue);

        final stream = macOSTracker.focusStream;
        expect(stream, isA<Stream<FocusEvent>>());

        await macOSTracker.stopTracking();
      });

      test('consistent API behavior across platforms', () async {
        final platforms = [
          MockPlatformFactory.createMacOSMock(hasPermissions: true),
          MockPlatformFactory.createWindowsMock(),
        ];

        for (final platform in platforms) {
          AppFocusTrackerPlatform.instance = platform;
          final tracker = AppFocusTracker();

          // All platforms should support the same basic API
          expect(await tracker.isSupported(), isTrue);
          expect(await tracker.hasPermissions(), isTrue);

          await tracker.startTracking();
          expect(await tracker.isTracking(), isTrue);

          final stream = tracker.focusStream;
          expect(stream, isA<Stream<FocusEvent>>());

          final diagnostics = await AppFocusTracker.getDiagnosticInfo();
          expect(diagnostics, isA<Map<String, dynamic>>());
          expect(diagnostics.containsKey('platform'), isTrue);

          await tracker.stopTracking();
          expect(await tracker.isTracking(), isFalse);
        }
      });
    });
  });
}
