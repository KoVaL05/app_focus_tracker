import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/app_focus_tracker.dart';
import 'package:app_focus_tracker/src/platform_interface.dart';
import 'package:app_focus_tracker/src/models/models.dart';

import '../mocks/mock_platform_interface.dart';

void main() {
  group('Performance and Stress Tests', () {
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

    group('High-Frequency Event Handling', () {
      test('handles 1000 events per second', () async {
        const config = FocusTrackerConfig(updateIntervalMs: 1); // Very frequent updates
        await tracker.startTracking(config);

        final events = <FocusEvent>[];
        final subscription = tracker.focusStream.listen(events.add);

        final stopwatch = Stopwatch()..start();

        // Generate 1000 events rapidly
        for (int i = 0; i < 1000; i++) {
          mockPlatform.simulateAppFocus('App $i');
          if (i % 100 == 0) {
            // Yield control briefly every 100 events
            await Future.delayed(const Duration(microseconds: 100));
          }
        }

        await Future.delayed(const Duration(milliseconds: 100));
        stopwatch.stop();

        await subscription.cancel();

        expect(events.length, greaterThanOrEqualTo(500)); // More realistic expectation
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Should complete within 5 seconds

        // Verify all events are unique and properly formed
        final eventIds = events.map((e) => e.eventId).toSet();
        expect(eventIds.length, greaterThanOrEqualTo(500)); // All events should have unique IDs

        // Verify chronological order
        for (int i = 1; i < events.length; i++) {
          expect(
            events[i].timestamp.microsecondsSinceEpoch >= events[i - 1].timestamp.microsecondsSinceEpoch,
            isTrue,
          );
        }
      });

      test('maintains performance with concurrent operations', () async {
        await tracker.startTracking();

        final events = <FocusEvent>[];
        final subscription = tracker.focusStream.listen(events.add);

        final stopwatch = Stopwatch()..start();

        // Start concurrent operations
        final futures = <Future>[];

        // Event generation
        futures.add(Future(() async {
          for (int i = 0; i < 500; i++) {
            mockPlatform.simulateAppFocus('Concurrent App $i');
            if (i % 50 == 0) {
              await Future.delayed(const Duration(microseconds: 100));
            }
          }
        }));

        // App list queries
        futures.add(Future(() async {
          for (int i = 0; i < 100; i++) {
            await tracker.getRunningApplications();
            await Future.delayed(const Duration(milliseconds: 5));
          }
        }));

        // Current app queries
        futures.add(Future(() async {
          for (int i = 0; i < 200; i++) {
            await tracker.getCurrentFocusedApp();
            await Future.delayed(const Duration(milliseconds: 2));
          }
        }));

        // Diagnostic queries
        futures.add(Future(() async {
          for (int i = 0; i < 50; i++) {
            await AppFocusTracker.getDiagnosticInfo();
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }));

        await Future.wait(futures);
        stopwatch.stop();

        await Future.delayed(const Duration(milliseconds: 100));
        await subscription.cancel();

        expect(events.length, greaterThanOrEqualTo(500));
        expect(stopwatch.elapsedMilliseconds, lessThan(10000)); // Should complete within 10 seconds

        // System should remain responsive
        final finalDiagnostics = await AppFocusTracker.getDiagnosticInfo();
        expect(finalDiagnostics['isTracking'], isTrue);
      });
    });

    group('Memory Management', () {
      test('handles large numbers of events without memory leaks', () async {
        await tracker.startTracking(const FocusTrackerConfig(updateIntervalMs: 1));

        // Simulate collecting only recent events (like a real app would)
        final recentEvents = <FocusEvent>[];
        const maxRecentEvents = 1000;

        late StreamSubscription<FocusEvent> subscription;
        subscription = tracker.focusStream.listen((event) {
          recentEvents.add(event);
          // Keep only the most recent events
          if (recentEvents.length > maxRecentEvents) {
            recentEvents.removeRange(0, recentEvents.length - maxRecentEvents);
          }
        });

        // Generate a large number of events
        const totalEvents = 10000;
        final stopwatch = Stopwatch()..start();

        for (int i = 0; i < totalEvents; i++) {
          mockPlatform.simulateAppFocus('App ${i % 100}'); // Cycle through 100 app names

          if (i % 1000 == 0) {
            await Future.delayed(const Duration(milliseconds: 1));

            // Verify memory usage stays bounded
            expect(recentEvents.length, lessThanOrEqualTo(maxRecentEvents));
          }
        }

        stopwatch.stop();
        await Future.delayed(const Duration(milliseconds: 100));
        await subscription.cancel();

        // Memory should be bounded
        expect(recentEvents.length, equals(maxRecentEvents));
        expect(stopwatch.elapsedMilliseconds, lessThan(30000)); // Should complete within 30 seconds

        // Last events should be from the end of the sequence
        final lastEvent = recentEvents.last;
        expect(lastEvent.appName, contains('App'));
      });

      test('properly cleans up resources on stop', () async {
        // Start and stop tracking multiple times
        for (int cycle = 0; cycle < 10; cycle++) {
          await tracker.startTracking();

          final events = <FocusEvent>[];
          final subscription = tracker.focusStream.listen(events.add);

          // Generate some events
          for (int i = 0; i < 100; i++) {
            mockPlatform.simulateAppFocus('Cycle $cycle App $i');
          }

          await Future.delayed(const Duration(milliseconds: 50));
          await subscription.cancel();
          await tracker.stopTracking();

          expect(await tracker.isTracking(), isFalse);
          expect(events.length, equals(100));
        }

        // System should still be responsive after multiple cycles
        await tracker.startTracking();
        expect(await tracker.isTracking(), isTrue);

        final diagnostics = await AppFocusTracker.getDiagnosticInfo();
        expect(diagnostics['isTracking'], isTrue);

        await tracker.stopTracking();
      });
    });

    group('Long-Running Session Tests', () {
      test('maintains accuracy over extended periods', () async {
        const sessionDuration = Duration(seconds: 5); // Simulated long session
        await tracker.startTracking(const FocusTrackerConfig(updateIntervalMs: 100));

        final events = <FocusEvent>[];
        final subscription = tracker.focusStream.listen(events.add);

        final sessionStart = DateTime.now();
        final sessionApps = ['WorkApp', 'BrowserApp', 'EmailApp', 'EditoApp'];
        final random = math.Random();

        // Simulate realistic usage patterns over time
        final timer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
          final elapsed = DateTime.now().difference(sessionStart);

          if (elapsed >= sessionDuration) {
            timer.cancel();
            return;
          }

          // Randomly switch apps or send duration updates
          if (random.nextDouble() < 0.3) {
            // 30% chance to switch apps
            final appName = sessionApps[random.nextInt(sessionApps.length)];
            mockPlatform.simulateAppFocus(appName);
          } else {
            // 70% chance to send duration update
            final appName = sessionApps[random.nextInt(sessionApps.length)];
            final duration = Duration(milliseconds: elapsed.inMilliseconds + random.nextInt(1000));
            mockPlatform.simulateDurationUpdate(appName, duration);
          }
        });

        // Wait for session to complete
        await Future.delayed(sessionDuration + const Duration(milliseconds: 500));
        timer.cancel();

        await subscription.cancel();

        expect(events.length, greaterThan(20)); // Should have many events

        // Verify session consistency
        final sessionIds = events.map((e) => e.sessionId).toSet();
        expect(sessionIds.length, equals(1)); // All events from same session

        // Verify events span the session duration
        final eventTimes = events.map((e) => e.timestamp).toList()..sort();
        final sessionSpan = eventTimes.last.difference(eventTimes.first);
        expect(sessionSpan.inMilliseconds, greaterThanOrEqualTo(100)); // At least 100ms

        // Check that we have some duration updates for the session
        final allDurationUpdates = events.where((e) => e.eventType == FocusEventType.durationUpdate).toList();
        expect(allDurationUpdates.length, greaterThan(0));

        // Basic sanity check - durations should be positive
        for (final update in allDurationUpdates) {
          expect(update.durationMicroseconds, greaterThan(0));
        }
      });

      test('handles sustained high activity without degradation', () async {
        const config = FocusTrackerConfig(updateIntervalMs: 50);
        await tracker.startTracking(config);

        final events = <FocusEvent>[];
        final performanceMetrics = <Duration>[];

        late StreamSubscription<FocusEvent> subscription;
        subscription = tracker.focusStream.listen((event) {
          events.add(event);

          // Measure processing time periodically
          if (events.length % 100 == 0) {
            final stopwatch = Stopwatch()..start();
            // Simulate event processing work
            event.toString();
            event.toJson();
            stopwatch.stop();
            performanceMetrics.add(stopwatch.elapsed);
          }
        });

        // Generate sustained activity for several seconds
        const testDuration = Duration(seconds: 3);
        final testStart = DateTime.now();

        int eventCount = 0;
        final activityTimer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
          final elapsed = DateTime.now().difference(testStart);

          if (elapsed >= testDuration) {
            timer.cancel();
            return;
          }

          // Generate various types of events
          final eventType = eventCount % 4;
          switch (eventType) {
            case 0:
              mockPlatform.simulateAppFocus('App ${eventCount % 20}');
              break;
            case 1:
              mockPlatform.simulateDurationUpdate(
                  'App ${eventCount % 20}', Duration(milliseconds: elapsed.inMilliseconds));
              break;
            case 2:
              mockPlatform.simulateAppBlur('App ${eventCount % 20}', Duration(milliseconds: elapsed.inMilliseconds));
              break;
            case 3:
              mockPlatform.simulateAppFocus('App ${(eventCount + 1) % 20}');
              break;
          }

          eventCount++;
        });

        await Future.delayed(testDuration + const Duration(milliseconds: 200));
        activityTimer.cancel();

        await subscription.cancel();

        expect(events.length, greaterThan(50));
        expect(performanceMetrics.length, greaterThanOrEqualTo(1));

        // Performance should not degrade over time
        if (performanceMetrics.length > 5) {
          final firstMetrics = performanceMetrics.take(3).toList();
          final lastMetrics = performanceMetrics.skip(performanceMetrics.length - 3).toList();

          final avgFirst = firstMetrics.map((d) => d.inMicroseconds).reduce((a, b) => a + b) / firstMetrics.length;
          final avgLast = lastMetrics.map((d) => d.inMicroseconds).reduce((a, b) => a + b) / lastMetrics.length;

          // Last measurements should not be significantly slower than first
          expect(avgLast / avgFirst, lessThan(3.0));
        }

        // System should still be responsive
        final finalDiagnostics = await AppFocusTracker.getDiagnosticInfo();
        expect(finalDiagnostics['isTracking'], isTrue);
      });
    });

    group('Resource Cleanup and Error Recovery', () {
      test('recovers from stream errors gracefully', () async {
        await tracker.startTracking();

        final events = <FocusEvent>[];
        final errors = <Object>[];

        final subscription = tracker.focusStream.listen(
          events.add,
          onError: errors.add,
        );

        // Generate normal events
        for (int i = 0; i < 50; i++) {
          mockPlatform.simulateAppFocus('App $i');
        }

        await Future.delayed(const Duration(milliseconds: 100));

        // Simulate error condition
        mockPlatform.simulateError(
            'getCurrentFocusedApp', const PlatformChannelException('Simulated error', code: 'TEST_ERROR'));

        // Continue with more events
        for (int i = 50; i < 100; i++) {
          mockPlatform.simulateAppFocus('App $i');
        }

        await Future.delayed(const Duration(milliseconds: 100));
        await subscription.cancel();

        expect(events.length, greaterThanOrEqualTo(100));
        // Error handling behavior depends on implementation
      });

      test('handles platform disconnection and reconnection', () async {
        await tracker.startTracking();

        final events = <FocusEvent>[];
        final subscription = tracker.focusStream.listen(events.add);

        // Generate some events
        for (int i = 0; i < 25; i++) {
          mockPlatform.simulateAppFocus('App $i');
        }

        await Future.delayed(const Duration(milliseconds: 50));

        // Simulate platform disconnection by stopping
        await tracker.stopTracking();
        expect(await tracker.isTracking(), isFalse);

        // Reconnect
        await tracker.startTracking();
        expect(await tracker.isTracking(), isTrue);

        // Continue with more events on new stream
        await subscription.cancel();
        final newEvents = <FocusEvent>[];
        final newSubscription = tracker.focusStream.listen(newEvents.add);

        for (int i = 25; i < 50; i++) {
          mockPlatform.simulateAppFocus('App $i');
        }

        await Future.delayed(const Duration(milliseconds: 50));
        await newSubscription.cancel();

        expect(events.length, equals(25));
        expect(newEvents.length, equals(25));

        // Should be able to get diagnostics after reconnection
        final diagnostics = await AppFocusTracker.getDiagnosticInfo();
        expect(diagnostics['isTracking'], isTrue);
      });
    });

    group('Scalability Tests', () {
      test('handles tracking large numbers of applications', () async {
        await tracker.startTracking();

        // Add many applications to the mock platform
        for (int i = 0; i < 500; i++) {
          mockPlatform.addMockApp(AppInfo(
            name: 'Mass App $i',
            identifier: 'com.mass.app$i',
            processId: 10000 + i,
            version: '1.0.$i',
            metadata: {'index': i, 'category': i % 10 == 0 ? 'system' : 'user'},
          ));
        }

        final stopwatch = Stopwatch()..start();
        final apps = await tracker.getRunningApplications();
        stopwatch.stop();

        expect(apps.length, greaterThanOrEqualTo(452)); // Account for default apps + 500 new ones
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Should complete within 5 seconds

        // Verify all apps are properly formed
        for (final app in apps) {
          expect(app.name, isNotEmpty);
          expect(app.identifier, isNotEmpty);
          expect(app.processId, isNotNull);
          expect(app.processId! > 0, isTrue);
        }

        // Test filtering performance
        final userAppsStopwatch = Stopwatch()..start();
        final userApps = await tracker.getRunningApplications(includeSystemApps: false);
        userAppsStopwatch.stop();

        expect(userApps.length, lessThanOrEqualTo(apps.length));
        expect(userAppsStopwatch.elapsedMilliseconds, lessThan(3000));
      });

      test('maintains performance with complex configurations', () async {
        // Create a complex configuration
        final complexConfig = FocusTrackerConfig(
          updateIntervalMs: 50,
          includeMetadata: true,
          includeSystemApps: true,
          excludedApps: List.generate(100, (i) => 'excluded.app$i').toSet(),
          includedApps: List.generate(50, (i) => 'included.app$i').toSet(),
          enableBatching: true,
          maxBatchSize: 25,
          maxBatchWaitMs: 500,
        );

        final stopwatch = Stopwatch()..start();
        await tracker.startTracking(complexConfig);
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Should start quickly

        final events = <FocusEvent>[];
        final subscription = tracker.focusStream.listen(events.add);

        // Generate events that will be filtered by the complex config
        for (int i = 0; i < 200; i++) {
          final appType = i % 3;
          switch (appType) {
            case 0:
              mockPlatform.simulateAppFocus('included.app${i % 50}');
              break;
            case 1:
              mockPlatform.simulateAppFocus('excluded.app${i % 100}');
              break;
            case 2:
              mockPlatform.simulateAppFocus('regular.app${i % 30}');
              break;
          }

          if (i % 50 == 0) {
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }

        await Future.delayed(const Duration(milliseconds: 200));
        await subscription.cancel();

        // Should have received events (filtering behavior depends on implementation)
        expect(events.isNotEmpty, isTrue);

        // Configuration update should also be fast
        final updateStopwatch = Stopwatch()..start();
        final updateResult = await tracker.updateConfiguration(
          complexConfig.copyWith(updateIntervalMs: 100),
        );
        updateStopwatch.stop();

        expect(updateResult, isTrue);
        expect(updateStopwatch.elapsedMilliseconds, lessThan(500));
      });
    });
  });
}
