import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/src/platform_interface.dart';
import 'package:app_focus_tracker/src/models/models.dart';
import 'package:app_focus_tracker/src/exceptions/app_focus_tracker_exception.dart';

import '../mocks/mock_platform_interface.dart';

void main() {
  group('macOS Platform Specific Tests', () {
    late MockAppFocusTrackerPlatform macOSPlatform;

    setUp(() {
      macOSPlatform = MockPlatformFactory.createMacOSMock();
      AppFocusTrackerPlatform.instance = macOSPlatform;
    });

    tearDown(() {
      macOSPlatform.reset();
    });

    group('Accessibility Permission Flow', () {
      test('initial permission state is false', () async {
        final platform = MockPlatformFactory.createMacOSMock(hasPermissions: false);

        expect(await platform.getPlatformName(), equals('macOS'));
        expect(await platform.hasPermissions(), isFalse);
        expect(await platform.isSupported(), isTrue);
      });

      test('permission request flow succeeds', () async {
        final platform = MockPlatformFactory.createMacOSMock(
          hasPermissions: false,
          simulatePermissionRequest: true,
        );

        // Initial state - no permissions
        expect(await platform.hasPermissions(), isFalse);

        // Request permissions
        final granted = await platform.requestPermissions();
        expect(granted, isTrue);

        // Should now be able to start tracking
        await platform.startTracking(const FocusTrackerConfig());
        expect(await platform.isTracking(), isTrue);
      });

      test('permission request denial prevents tracking', () async {
        final platform = MockPlatformFactory.createMacOSMock(
          hasPermissions: false,
          simulatePermissionRequest: false,
        );

        // Permission request should throw
        expect(
          () => platform.requestPermissions(),
          throwsA(isA<PermissionDeniedException>()),
        );

        // Should not be able to start tracking without permissions
        expect(
          () => platform.startTracking(const FocusTrackerConfig()),
          throwsA(isA<PermissionDeniedException>()),
        );
      });

      test('tracking starts automatically with existing permissions', () async {
        final platform = MockPlatformFactory.createMacOSMock(hasPermissions: true);

        expect(await platform.hasPermissions(), isTrue);

        // Should be able to start tracking immediately
        await platform.startTracking(const FocusTrackerConfig());
        expect(await platform.isTracking(), isTrue);
      });
    });

    group('App Metadata Extraction', () {
      test('extracts bundle identifiers correctly', () async {
        await macOSPlatform.startTracking(const FocusTrackerConfig());

        final apps = await macOSPlatform.getRunningApplications();
        expect(apps.isNotEmpty, isTrue);

        for (final app in apps) {
          expect(app.identifier, isNotEmpty);
          // macOS bundle identifiers typically follow reverse domain notation
          if (app.identifier.contains('.')) {
            expect(app.identifier, matches(RegExp(r'^[a-zA-Z0-9.-]+$')));
          }
        }
      });

      test('includes macOS-specific metadata', () async {
        const config = FocusTrackerConfig(includeMetadata: true);
        await macOSPlatform.startTracking(config);

        final events = <FocusEvent>[];
        final subscription = macOSPlatform.getFocusStream().listen(events.add);

        macOSPlatform.simulateAppFocus('TestApp', appIdentifier: 'com.test.app');
        await Future.delayed(const Duration(milliseconds: 50));

        await subscription.cancel();

        expect(events.isNotEmpty, isTrue);
        final event = events.first;

        if (event.metadata != null) {
          expect(event.metadata, isA<Map<String, dynamic>>());
          // Verify metadata structure makes sense for macOS
          expect(event.metadata!.containsKey('mockEvent'), isTrue);
        }
      });

      test('handles app versioning information', () async {
        await macOSPlatform.startTracking(const FocusTrackerConfig());

        final apps = await macOSPlatform.getRunningApplications();

        for (final app in apps) {
          if (app.version != null) {
            expect(app.version, isNotEmpty);
            // Version should follow semantic versioning or similar
            expect(app.version, matches(RegExp(r'^\d+(\.\d+)*')));
          }
        }
      });
    });

    group('System App Filtering', () {
      test('excludes system apps by default', () async {
        await macOSPlatform.startTracking(FocusTrackerConfig.privacy());

        final userApps = await macOSPlatform.getRunningApplications(includeSystemApps: false);
        final allApps = await macOSPlatform.getRunningApplications(includeSystemApps: true);

        expect(allApps.length, greaterThanOrEqualTo(userApps.length));

        // Check that common macOS system apps are filtered out
        final userAppIds = userApps.map((app) => app.identifier).toSet();

        final commonSystemApps = [
          'com.apple.finder',
          'com.apple.dock',
          'com.apple.systempreferences',
          'com.apple.controlstrip',
        ];

        for (final systemApp in commonSystemApps) {
          expect(userAppIds.contains(systemApp), isFalse);
        }
      });

      test('includes system apps when requested', () async {
        await macOSPlatform.startTracking(const FocusTrackerConfig());

        final allApps = await macOSPlatform.getRunningApplications(includeSystemApps: true);
        final appCategories =
            allApps.where((app) => app.metadata != null).map((app) => app.metadata!['category']).toSet();

        expect(appCategories.contains('system'), isTrue);
      });
    });

    group('Sandboxing Compatibility', () {
      test('handles sandboxed app limitations gracefully', () async {
        // Simulate a sandboxed environment where some APIs might be restricted
        await macOSPlatform.startTracking(const FocusTrackerConfig());

        // Should still be able to get basic app information
        final currentApp = await macOSPlatform.getCurrentFocusedApp();
        expect(currentApp, anyOf(isNull, isA<AppInfo>()));

        if (currentApp != null) {
          expect(currentApp.name, isNotEmpty);
          expect(currentApp.identifier, isNotEmpty);
        }
      });

      test('handles restricted process information access', () async {
        await macOSPlatform.startTracking(const FocusTrackerConfig());

        final apps = await macOSPlatform.getRunningApplications();

        // Even in restricted environments, should get some basic info
        expect(apps.isNotEmpty, isTrue);

        for (final app in apps) {
          expect(app.name, isNotEmpty);
          expect(app.identifier, isNotEmpty);
          // Process ID might be null in sandboxed environments
          if (app.processId != null) {
            expect(app.processId! > 0, isTrue);
          }
        }
      });
    });

    group('Performance Characteristics', () {
      test('handles high-frequency app switching on macOS', () async {
        const config = FocusTrackerConfig(updateIntervalMs: 50);
        await macOSPlatform.startTracking(config);

        final events = <FocusEvent>[];
        final subscription = macOSPlatform.getFocusStream().listen(events.add);

        // Simulate rapid app switching common on macOS with Mission Control
        final macOSApps = [
          'Safari',
          'TextEdit',
          'Terminal',
          'Finder',
          'System Preferences',
          'Activity Monitor',
        ];

        for (int i = 0; i < macOSApps.length; i++) {
          macOSPlatform.simulateAppFocus(macOSApps[i], appIdentifier: 'com.apple.${macOSApps[i].toLowerCase()}');
          await Future.delayed(const Duration(milliseconds: 20));

          macOSPlatform.simulateAppBlur(macOSApps[i], const Duration(milliseconds: 20));
        }

        await Future.delayed(const Duration(milliseconds: 100));
        await subscription.cancel();

        expect(events.length, equals(macOSApps.length * 2)); // Focus + Blur for each

        // Verify bundle identifiers are correct
        final focusEvents = events.where((e) => e.eventType == FocusEventType.gained).toList();
        for (int i = 0; i < focusEvents.length; i++) {
          expect(focusEvents[i].appName, equals(macOSApps[i]));
          expect(focusEvents[i].appIdentifier, contains('com.apple.'));
        }
      });

      test('maintains accuracy during system resource pressure', () async {
        // Simulate high system load scenario
        const config = FocusTrackerConfig(updateIntervalMs: 100);
        await macOSPlatform.startTracking(config);

        final events = <FocusEvent>[];
        final subscription = macOSPlatform.getFocusStream().listen(events.add);

        // Simulate sustained activity
        for (int cycle = 0; cycle < 10; cycle++) {
          macOSPlatform.simulateAppFocus('Resource Heavy App $cycle');
          await Future.delayed(const Duration(milliseconds: 50));

          // Simulate duration updates
          for (int j = 1; j <= 3; j++) {
            macOSPlatform.simulateDurationUpdate('Resource Heavy App $cycle', Duration(milliseconds: 50 * j));
            await Future.delayed(const Duration(milliseconds: 25));
          }

          macOSPlatform.simulateAppBlur('Resource Heavy App $cycle', const Duration(milliseconds: 150));
        }

        await Future.delayed(const Duration(milliseconds: 100));
        await subscription.cancel();

        // Should have received all expected events despite load
        expect(events.length, greaterThan(30)); // 10 apps * (1 focus + 3 updates + 1 blur)

        // Verify timing consistency
        final gainedEvents = events.where((e) => e.eventType == FocusEventType.gained).toList();
        expect(gainedEvents.length, equals(10));

        // Events should be in chronological order
        for (int i = 1; i < gainedEvents.length; i++) {
          expect(gainedEvents[i].timestamp.isAfter(gainedEvents[i - 1].timestamp), isTrue);
        }
      });
    });

    group('macOS Specific Error Handling', () {
      test('handles accessibility service interruption', () async {
        await macOSPlatform.startTracking(const FocusTrackerConfig());

        // Simulate accessibility service interruption
        macOSPlatform.simulateError('getCurrentFocusedApp',
            const PlatformChannelException('Accessibility service unavailable', code: 'ACCESSIBILITY_ERROR'));

        // Subsequent calls should handle the error gracefully
        final result = macOSPlatform.getCurrentFocusedApp();
        expect(result, throwsA(isA<AppFocusTrackerException>()));
      });

      test('handles app bundle access restrictions', () async {
        await macOSPlatform.startTracking(const FocusTrackerConfig());

        // Add an app with restricted bundle access
        macOSPlatform.addMockApp(const AppInfo(
          name: 'Restricted App',
          identifier: 'com.restricted.app',
          processId: 9999,
          metadata: {'accessRestricted': true},
        ));

        final apps = await macOSPlatform.getRunningApplications();
        final restrictedApp = apps.firstWhere(
          (app) => app.identifier == 'com.restricted.app',
          orElse: () => const AppInfo(name: '', identifier: ''),
        );

        expect(restrictedApp.name, isNotEmpty);
        // Should still have basic information even if bundle access is restricted
        expect(restrictedApp.identifier, equals('com.restricted.app'));
      });
    });

    group('Integration with macOS Features', () {
      test('supports Mission Control app switching detection', () async {
        await macOSPlatform.startTracking(const FocusTrackerConfig());

        final events = <FocusEvent>[];
        final subscription = macOSPlatform.getFocusStream().listen(events.add);

        // Simulate Mission Control style rapid switching
        macOSPlatform.simulateAppFocus('App A');
        macOSPlatform.simulateAppFocus('App B');
        macOSPlatform.simulateAppFocus('App C');
        macOSPlatform.simulateAppFocus('App A'); // Back to first app

        await Future.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        expect(events.length, equals(4));
        expect(events[0].appName, equals('App A'));
        expect(events[1].appName, equals('App B'));
        expect(events[2].appName, equals('App C'));
        expect(events[3].appName, equals('App A'));
      });

      test('handles Spaces (virtual desktop) transitions', () async {
        await macOSPlatform.startTracking(const FocusTrackerConfig());

        final events = <FocusEvent>[];
        final subscription = macOSPlatform.getFocusStream().listen(events.add);

        // Simulate Space transition where same app regains focus
        macOSPlatform.simulateAppFocus('Safari', appIdentifier: 'com.apple.Safari');
        macOSPlatform.simulateAppBlur('Safari', const Duration(milliseconds: 100));

        // Brief moment during Space transition
        await Future.delayed(const Duration(milliseconds: 10));

        // Same app regains focus in new Space
        macOSPlatform.simulateAppFocus('Safari', appIdentifier: 'com.apple.Safari');

        await Future.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        expect(events.length, equals(3));
        expect(events[0].eventType, equals(FocusEventType.gained));
        expect(events[1].eventType, equals(FocusEventType.lost));
        expect(events[2].eventType, equals(FocusEventType.gained));

        // All events should be for the same app
        expect(events.every((e) => e.appName == 'Safari'), isTrue);
      });
    });
  });
}
