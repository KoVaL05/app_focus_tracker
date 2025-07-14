import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/src/platform_interface.dart';
import 'package:app_focus_tracker/src/models/models.dart';
import 'package:app_focus_tracker/src/exceptions/app_focus_tracker_exception.dart';

import 'mocks/mock_platform_interface.dart';

void main() {
  group('AppFocusTrackerPlatform Interface Compliance', () {
    late MockAppFocusTrackerPlatform mockPlatform;

    setUp(() {
      mockPlatform = MockAppFocusTrackerPlatform();
      AppFocusTrackerPlatform.instance = mockPlatform;
    });

    tearDown(() {
      mockPlatform.reset();
    });

    group('Platform Information', () {
      test('getPlatformName returns string', () async {
        final platformName = await mockPlatform.getPlatformName();
        expect(platformName, isA<String>());
        expect(platformName.isNotEmpty, isTrue);
      });

      test('isSupported returns boolean', () async {
        final supported = await mockPlatform.isSupported();
        expect(supported, isA<bool>());
      });

      test('hasPermissions returns boolean', () async {
        final hasPerms = await mockPlatform.hasPermissions();
        expect(hasPerms, isA<bool>());
      });
    });

    group('Permission Management', () {
      test('requestPermissions returns boolean', () async {
        final granted = await mockPlatform.requestPermissions();
        expect(granted, isA<bool>());
      });

      test('requestPermissions can throw PermissionDeniedException', () async {
        final deniedPlatform = MockAppFocusTrackerPlatform(
          simulatePermissionRequest: false,
        );

        expect(
          () => deniedPlatform.requestPermissions(),
          throwsA(isA<PermissionDeniedException>()),
        );
      });
    });

    group('Tracking Lifecycle', () {
      test('startTracking with valid config succeeds', () async {
        const config = FocusTrackerConfig();

        await expectLater(
          mockPlatform.startTracking(config),
          completes,
        );

        final isTracking = await mockPlatform.isTracking();
        expect(isTracking, isTrue);
      });

      test('startTracking without permissions throws PermissionDeniedException', () async {
        final noPermsPlatform = MockAppFocusTrackerPlatform(
          hasPermissions: false,
        );

        const config = FocusTrackerConfig();

        expect(
          () => noPermsPlatform.startTracking(config),
          throwsA(isA<PermissionDeniedException>()),
        );
      });

      test('startTracking on unsupported platform throws PlatformNotSupportedException', () async {
        final unsupportedPlatform = MockAppFocusTrackerPlatform(
          isSupported: false,
        );

        const config = FocusTrackerConfig();

        expect(
          () => unsupportedPlatform.startTracking(config),
          throwsA(isA<PlatformNotSupportedException>()),
        );
      });

      test('startTracking twice throws exception', () async {
        const config = FocusTrackerConfig();

        await mockPlatform.startTracking(config);

        expect(
          () => mockPlatform.startTracking(config),
          throwsA(isA<AppFocusTrackerException>()),
        );
      });

      test('stopTracking succeeds when tracking', () async {
        const config = FocusTrackerConfig();
        await mockPlatform.startTracking(config);

        await expectLater(
          mockPlatform.stopTracking(),
          completes,
        );

        final isTracking = await mockPlatform.isTracking();
        expect(isTracking, isFalse);
      });

      test('stopTracking when not tracking is safe', () async {
        await expectLater(
          mockPlatform.stopTracking(),
          completes,
        );
      });

      test('isTracking returns correct state', () async {
        expect(await mockPlatform.isTracking(), isFalse);

        const config = FocusTrackerConfig();
        await mockPlatform.startTracking(config);
        expect(await mockPlatform.isTracking(), isTrue);

        await mockPlatform.stopTracking();
        expect(await mockPlatform.isTracking(), isFalse);
      });
    });

    group('Focus Stream', () {
      test('getFocusStream throws when not tracking', () {
        expect(
          () => mockPlatform.getFocusStream(),
          throwsA(isA<StateError>()),
        );
      });

      test('getFocusStream returns stream when tracking', () async {
        const config = FocusTrackerConfig();
        await mockPlatform.startTracking(config);

        final stream = mockPlatform.getFocusStream();
        expect(stream, isA<Stream<FocusEvent>>());
      });

      test('focus stream emits events', () async {
        const config = FocusTrackerConfig();
        await mockPlatform.startTracking(config);

        final stream = mockPlatform.getFocusStream();
        final events = <FocusEvent>[];

        final subscription = stream.listen(events.add);

        // Simulate some focus events
        mockPlatform.simulateAppFocus('Test App');
        mockPlatform.simulateDurationUpdate('Test App', const Duration(seconds: 1));
        mockPlatform.simulateAppBlur('Test App', const Duration(seconds: 2));

        await Future.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        expect(events.length, equals(3));
        expect(events[0].eventType, equals(FocusEventType.gained));
        expect(events[1].eventType, equals(FocusEventType.durationUpdate));
        expect(events[2].eventType, equals(FocusEventType.lost));
      });
    });

    group('App Information', () {
      test('getCurrentFocusedApp returns AppInfo or null', () async {
        final currentApp = await mockPlatform.getCurrentFocusedApp();
        expect(currentApp, anyOf(isNull, isA<AppInfo>()));
      });

      test('getRunningApplications returns list of AppInfo', () async {
        final apps = await mockPlatform.getRunningApplications();
        expect(apps, isA<List<AppInfo>>());

        if (apps.isNotEmpty) {
          expect(apps.first, isA<AppInfo>());
          expect(apps.first.name.isNotEmpty, isTrue);
          expect(apps.first.identifier.isNotEmpty, isTrue);
        }
      });

      test('getRunningApplications with includeSystemApps parameter', () async {
        final appsNoSystem = await mockPlatform.getRunningApplications(includeSystemApps: false);
        final appsWithSystem = await mockPlatform.getRunningApplications(includeSystemApps: true);

        expect(appsNoSystem, isA<List<AppInfo>>());
        expect(appsWithSystem, isA<List<AppInfo>>());
        expect(appsWithSystem.length, greaterThanOrEqualTo(appsNoSystem.length));
      });
    });

    group('Configuration Management', () {
      test('updateConfiguration succeeds when tracking', () async {
        const config = FocusTrackerConfig();
        await mockPlatform.startTracking(config);

        final newConfig = config.copyWith(updateIntervalMs: 2000);
        final result = await mockPlatform.updateConfiguration(newConfig);

        expect(result, isA<bool>());
      });

      test('updateConfiguration throws when not tracking', () async {
        const config = FocusTrackerConfig();

        expect(
          () => mockPlatform.updateConfiguration(config),
          throwsA(isA<AppFocusTrackerException>()),
        );
      });
    });

    group('Diagnostics', () {
      test('getDiagnosticInfo returns map with required fields', () async {
        final diagnostics = await mockPlatform.getDiagnosticInfo();

        expect(diagnostics, isA<Map<String, dynamic>>());
        expect(diagnostics.containsKey('platform'), isTrue);
        expect(diagnostics.containsKey('isTracking'), isTrue);
        expect(diagnostics.containsKey('hasPermissions'), isTrue);
      });

      test('getDiagnosticInfo includes tracking state', () async {
        var diagnostics = await mockPlatform.getDiagnosticInfo();
        expect(diagnostics['isTracking'], isFalse);

        const config = FocusTrackerConfig();
        await mockPlatform.startTracking(config);

        diagnostics = await mockPlatform.getDiagnosticInfo();
        expect(diagnostics['isTracking'], isTrue);
        expect(diagnostics.containsKey('sessionId'), isTrue);
        expect(diagnostics.containsKey('config'), isTrue);
      });
    });

    group('Error Handling', () {
      test('platform methods handle errors gracefully', () async {
        final errorPlatform = MockPlatformFactory.createErrorMock();

        expect(
          () => errorPlatform.getPlatformName(),
          throwsA(isA<AppFocusTrackerException>()),
        );

        expect(
          () => errorPlatform.isSupported(),
          throwsA(isA<AppFocusTrackerException>()),
        );

        expect(
          () => errorPlatform.hasPermissions(),
          throwsA(isA<AppFocusTrackerException>()),
        );
      });

      test('specific errors can be simulated', () async {
        const specificError = PlatformChannelException(
          'Custom error message',
          code: 'CUSTOM_ERROR',
        );

        mockPlatform.simulateError('getPlatformName', specificError);

        expect(
          () => mockPlatform.getPlatformName(),
          throwsA(predicate(
              (e) => e is AppFocusTrackerException && e.message == 'Custom error message' && e.code == 'CUSTOM_ERROR')),
        );
      });
    });

    group('Performance Characteristics', () {
      test('slow responses still complete', () async {
        final slowPlatform = MockPlatformFactory.createSlowMock();

        final stopwatch = Stopwatch()..start();
        await slowPlatform.getPlatformName();
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, greaterThan(50));
      });

      test('concurrent operations are handled', () async {
        const config = FocusTrackerConfig();
        await mockPlatform.startTracking(config);

        // Start multiple concurrent operations
        final futures = [
          mockPlatform.getCurrentFocusedApp(),
          mockPlatform.getRunningApplications(),
          mockPlatform.getDiagnosticInfo(),
          mockPlatform.isTracking(),
        ];

        final results = await Future.wait(futures);

        expect(results.length, equals(4));
        expect(results[0], anyOf(isNull, isA<AppInfo>()));
        expect(results[1], isA<List<AppInfo>>());
        expect(results[2], isA<Map<String, dynamic>>());
        expect(results[3], isA<bool>());
      });
    });

    group('Platform-Specific Behavior', () {
      test('macOS platform simulates accessibility permissions', () async {
        final macOSPlatform = MockPlatformFactory.createMacOSMock(
          hasPermissions: false,
        );

        expect(await macOSPlatform.hasPermissions(), isFalse);
        expect(await macOSPlatform.requestPermissions(), isTrue);
      });

      test('Windows platform has permissions by default', () async {
        final windowsPlatform = MockPlatformFactory.createWindowsMock();

        expect(await windowsPlatform.hasPermissions(), isTrue);
        expect(await windowsPlatform.getPlatformName(), equals('Windows'));
      });

      test('unsupported platform throws appropriate errors', () async {
        final unsupportedPlatform = MockPlatformFactory.createUnsupportedMock();

        expect(await unsupportedPlatform.isSupported(), isFalse);
        expect(await unsupportedPlatform.hasPermissions(), isFalse);

        const config = FocusTrackerConfig();
        expect(
          () => unsupportedPlatform.startTracking(config),
          throwsA(isA<PlatformNotSupportedException>()),
        );
      });
    });

    group('State Management', () {
      test('platform maintains consistent state across operations', () async {
        // Initial state
        expect(await mockPlatform.isTracking(), isFalse);

        // Start tracking
        const config = FocusTrackerConfig();
        await mockPlatform.startTracking(config);
        expect(await mockPlatform.isTracking(), isTrue);

        // Verify stream is available
        final stream = mockPlatform.getFocusStream();
        expect(stream, isA<Stream<FocusEvent>>());

        // Update configuration
        final newConfig = config.copyWith(updateIntervalMs: 2000);
        await mockPlatform.updateConfiguration(newConfig);
        expect(await mockPlatform.isTracking(), isTrue);

        // Stop tracking
        await mockPlatform.stopTracking();
        expect(await mockPlatform.isTracking(), isFalse);

        // Stream should no longer be available
        expect(
          () => mockPlatform.getFocusStream(),
          throwsA(isA<StateError>()),
        );
      });

      test('platform can be reset to initial state', () async {
        const config = FocusTrackerConfig();
        await mockPlatform.startTracking(config);

        mockPlatform.addMockApp(const AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
        ));

        mockPlatform.reset();

        expect(await mockPlatform.isTracking(), isFalse);
        expect(
          () => mockPlatform.getFocusStream(),
          throwsA(isA<StateError>()),
        );
      });
    });
  });
}
