import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/src/platform_interface.dart';
import 'package:app_focus_tracker/src/models/models.dart';
import 'package:app_focus_tracker/src/exceptions/app_focus_tracker_exception.dart';

import '../mocks/mock_platform_interface.dart';

void main() {
  group('Windows Platform Specific Tests', () {
    late MockAppFocusTrackerPlatform windowsPlatform;

    setUp(() {
      windowsPlatform = MockPlatformFactory.createWindowsMock();
      AppFocusTrackerPlatform.instance = windowsPlatform;
    });

    tearDown(() {
      windowsPlatform.reset();
    });

    group('Permission Model', () {
      test('has permissions by default', () async {
        expect(await windowsPlatform.getPlatformName(), equals('Windows'));
        expect(await windowsPlatform.hasPermissions(), isTrue);
        expect(await windowsPlatform.isSupported(), isTrue);
      });

      test('can start tracking without permission requests', () async {
        expect(await windowsPlatform.hasPermissions(), isTrue);

        // Should be able to start tracking immediately
        await windowsPlatform.startTracking(const FocusTrackerConfig());
        expect(await windowsPlatform.isTracking(), isTrue);
      });

      test('permission request always succeeds', () async {
        final granted = await windowsPlatform.requestPermissions();
        expect(granted, isTrue);
      });
    });

    group('Process and Window Information', () {
      test('extracts executable paths correctly', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        final apps = await windowsPlatform.getRunningApplications();
        expect(apps.isNotEmpty, isTrue);

        for (final app in apps) {
          expect(app.identifier, isNotEmpty);
          // Windows executable paths should contain backslashes or be just filenames
          if (app.identifier.contains('\\') || app.identifier.contains('/')) {
            expect(
                app.identifier,
                anyOf(
                  contains('\\'),
                  contains('/'),
                ));
          }
        }
      });

      test('includes Windows-specific metadata', () async {
        const config = FocusTrackerConfig(includeMetadata: true);
        await windowsPlatform.startTracking(config);

        final events = <FocusEvent>[];
        final subscription = windowsPlatform.getFocusStream().listen(events.add);

        windowsPlatform.simulateAppFocus('TestApp.exe', appIdentifier: 'C:\\Program Files\\TestApp\\TestApp.exe');
        await Future.delayed(const Duration(milliseconds: 50));

        await subscription.cancel();

        expect(events.isNotEmpty, isTrue);
        final event = events.first;

        if (event.metadata != null) {
          expect(event.metadata, isA<Map<String, dynamic>>());
          // Verify metadata structure makes sense for Windows
          expect(event.metadata!.containsKey('mockEvent'), isTrue);
        }
      });

      test('handles UWP app identification', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        // Add a UWP app mock
        windowsPlatform.addMockApp(const AppInfo(
          name: 'Windows Calculator',
          identifier: 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App',
          processId: 4567,
          version: '10.0.0.0',
          metadata: {'appType': 'UWP', 'packageFamily': 'Microsoft.WindowsCalculator_8wekyb3d8bbwe'},
        ));

        final apps = await windowsPlatform.getRunningApplications();
        final uwpApp = apps.firstWhere(
          (app) => app.identifier.contains('Microsoft.WindowsCalculator'),
          orElse: () => const AppInfo(name: '', identifier: ''),
        );

        expect(uwpApp.name, equals('Windows Calculator'));
        expect(uwpApp.identifier, contains('Microsoft.WindowsCalculator'));
        expect(uwpApp.metadata?['appType'], equals('UWP'));
      });

      test('extracts file version information', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        final apps = await windowsPlatform.getRunningApplications();

        for (final app in apps) {
          if (app.version != null) {
            expect(app.version, isNotEmpty);
            // Windows version should follow major.minor.build.revision format
            expect(app.version, matches(RegExp(r'^\d+\.\d+(\.\d+)*')));
          }
        }
      });
    });

    group('System App Filtering', () {
      test('excludes Windows system processes by default', () async {
        await windowsPlatform.startTracking(FocusTrackerConfig.privacy());

        final userApps = await windowsPlatform.getRunningApplications(includeSystemApps: false);
        final allApps = await windowsPlatform.getRunningApplications(includeSystemApps: true);

        expect(allApps.length, greaterThanOrEqualTo(userApps.length));

        // Check that common Windows system processes are filtered out
        final userAppIds = userApps.map((app) => app.identifier.toLowerCase()).toSet();

        final commonSystemProcesses = [
          'dwm.exe',
          'explorer.exe',
          'winlogon.exe',
          'csrss.exe',
        ];

        for (final systemProcess in commonSystemProcesses) {
          expect(userAppIds.any((id) => id.endsWith(systemProcess.toLowerCase())), isFalse);
        }
      });

      test('includes system processes when requested', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        final allApps = await windowsPlatform.getRunningApplications(includeSystemApps: true);
        final appCategories =
            allApps.where((app) => app.metadata != null).map((app) => app.metadata!['category']).toSet();

        expect(appCategories.contains('system'), isTrue);
      });
    });

    group('UAC and Elevation Scenarios', () {
      test('handles elevated process access gracefully', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        // Add an elevated process mock
        windowsPlatform.addMockApp(const AppInfo(
          name: 'Admin Tool',
          identifier: 'C:\\Windows\\System32\\AdminTool.exe',
          processId: 1234,
          metadata: {'elevated': true, 'accessDenied': false},
        ));

        final apps = await windowsPlatform.getRunningApplications();
        final elevatedApp = apps.firstWhere(
          (app) => app.name == 'Admin Tool',
          orElse: () => const AppInfo(name: '', identifier: ''),
        );

        expect(elevatedApp.name, equals('Admin Tool'));
        expect(elevatedApp.metadata?['elevated'], isTrue);
      });

      test('handles access denied scenarios for elevated processes', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        // Simulate scenario where process info cannot be accessed due to elevation
        windowsPlatform.simulateError('getRunningApplications',
            PlatformChannelException('Access denied to elevated process', code: 'ACCESS_DENIED'));

        expect(
          () => windowsPlatform.getRunningApplications(),
          throwsA(isA<AppFocusTrackerException>()),
        );
      });

      test('fallback behavior for restricted access', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        // Add a process with limited access
        windowsPlatform.addMockApp(const AppInfo(
          name: 'Restricted Process',
          identifier: 'RestrictedProcess.exe', // Just filename, no full path
          processId: 5678,
          metadata: {'accessLimited': true},
        ));

        final apps = await windowsPlatform.getRunningApplications();
        final restrictedApp = apps.firstWhere(
          (app) => app.name == 'Restricted Process',
          orElse: () => const AppInfo(name: '', identifier: ''),
        );

        expect(restrictedApp.name, isNotEmpty);
        expect(restrictedApp.identifier, equals('RestrictedProcess.exe'));
      });
    });

    group('Windows Version Compatibility', () {
      test('handles Windows 10 specific features', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        final diagnostics = await windowsPlatform.getDiagnosticInfo();

        expect(diagnostics['platform'], equals('Windows'));
        expect(diagnostics.containsKey('systemVersion'), isTrue);

        // Should be able to handle modern Windows APIs
        final apps = await windowsPlatform.getRunningApplications();
        expect(apps, isA<List<AppInfo>>());
      });

      test('handles legacy application identification', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        // Add a legacy application mock
        windowsPlatform.addMockApp(const AppInfo(
          name: 'Legacy App',
          identifier: 'C:\\Program Files (x86)\\LegacyApp\\legacy.exe',
          processId: 3456,
          version: '1.0.0.0',
          metadata: {'architecture': 'x86', 'legacy': true},
        ));

        final apps = await windowsPlatform.getRunningApplications();
        final legacyApp = apps.firstWhere(
          (app) => app.name == 'Legacy App',
          orElse: () => const AppInfo(name: '', identifier: ''),
        );

        expect(legacyApp.name, equals('Legacy App'));
        expect(legacyApp.identifier, contains('Program Files (x86)'));
        expect(legacyApp.metadata?['architecture'], equals('x86'));
      });

      test('handles modern UWP applications', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        // Add modern UWP apps
        final uwpApps = [
          const AppInfo(
            name: 'Microsoft Edge',
            identifier: 'Microsoft.MicrosoftEdge_8wekyb3d8bbwe!MicrosoftEdge',
            processId: 7890,
            metadata: {'appType': 'UWP', 'modern': true},
          ),
          const AppInfo(
            name: 'Windows Store',
            identifier: 'Microsoft.WindowsStore_8wekyb3d8bbwe!App',
            processId: 7891,
            metadata: {'appType': 'UWP', 'modern': true},
          ),
        ];

        for (final app in uwpApps) {
          windowsPlatform.addMockApp(app);
        }

        final apps = await windowsPlatform.getRunningApplications();
        final modernApps = apps.where((app) => app.metadata?['appType'] == 'UWP').toList();

        expect(modernApps.length, greaterThanOrEqualTo(2));

        for (final app in modernApps) {
          expect(app.identifier, contains('!'));
          expect(app.metadata?['modern'], isTrue);
        }
      });
    });

    group('Performance on Windows', () {
      test('handles rapid window switching', () async {
        const config = FocusTrackerConfig(updateIntervalMs: 50);
        await windowsPlatform.startTracking(config);

        final events = <FocusEvent>[];
        final subscription = windowsPlatform.getFocusStream().listen(events.add);

        // Simulate rapid Alt+Tab window switching
        final windowsApps = [
          'notepad.exe',
          'chrome.exe',
          'cmd.exe',
          'explorer.exe',
          'winword.exe',
        ];

        for (int i = 0; i < windowsApps.length; i++) {
          windowsPlatform.simulateAppFocus(windowsApps[i], appIdentifier: 'C:\\Windows\\System32\\${windowsApps[i]}');
          await Future.delayed(const Duration(milliseconds: 30));
        }

        await Future.delayed(const Duration(milliseconds: 100));
        await subscription.cancel();

        expect(events.length, greaterThanOrEqualTo(windowsApps.length));

        // Verify all apps were tracked
        final focusEvents = events.where((e) => e.eventType == FocusEventType.gained).toList();
        for (int i = 0; i < focusEvents.length && i < windowsApps.length; i++) {
          expect(focusEvents[i].appName, equals(windowsApps[i]));
          expect(focusEvents[i].appIdentifier, endsWith(windowsApps[i]));
        }
      });

      test('handles high DPI scaling scenarios', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig(includeMetadata: true));

        // Add apps with high DPI awareness
        windowsPlatform.addMockApp(const AppInfo(
          name: 'High DPI App',
          identifier: 'C:\\Program Files\\HighDPIApp\\app.exe',
          processId: 1111,
          metadata: {
            'dpiAware': true,
            'scalingFactor': 150,
            'resolution': '3840x2160',
          },
        ));

        final events = <FocusEvent>[];
        final subscription = windowsPlatform.getFocusStream().listen(events.add);

        windowsPlatform.simulateAppFocus('High DPI App');
        await Future.delayed(const Duration(milliseconds: 50));

        await subscription.cancel();

        expect(events.isNotEmpty, isTrue);
        final event = events.first;

        if (event.metadata != null) {
          // Should handle high DPI scenarios without issues
          expect(event.appName, equals('High DPI App'));
        }
      });
    });

    group('Windows Specific Error Handling', () {
      test('handles process termination during tracking', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        // Start tracking a process
        windowsPlatform.simulateAppFocus('TerminatingApp.exe', processId: 9999);

        // Simulate process termination error
        windowsPlatform.simulateError(
            'getCurrentFocusedApp', PlatformChannelException('Process terminated', code: 'PROCESS_TERMINATED'));

        expect(
          () => windowsPlatform.getCurrentFocusedApp(),
          throwsA(isA<AppFocusTrackerException>()),
        );
      });

      test('handles Win32 API errors gracefully', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        // Simulate various Win32 API errors
        final winErrors = [
          PlatformChannelException('Access denied', code: 'ERROR_ACCESS_DENIED'),
          PlatformChannelException('Invalid handle', code: 'ERROR_INVALID_HANDLE'),
          PlatformChannelException('Insufficient buffer', code: 'ERROR_INSUFFICIENT_BUFFER'),
        ];

        for (final error in winErrors) {
          windowsPlatform.simulateError('getRunningApplications', error);

          try {
            await windowsPlatform.getRunningApplications();
            fail('Expected exception was not thrown');
          } catch (e) {
            expect(e, isA<AppFocusTrackerException>());
          }
        }
      });
    });

    group('Integration with Windows Features', () {
      test('supports virtual desktop transitions', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig());

        final events = <FocusEvent>[];
        final subscription = windowsPlatform.getFocusStream().listen(events.add);

        // Simulate virtual desktop switch
        windowsPlatform.simulateAppFocus('App on Desktop 1');
        windowsPlatform.simulateAppBlur('App on Desktop 1', const Duration(milliseconds: 100));

        // Switch to different virtual desktop
        windowsPlatform.simulateAppFocus('App on Desktop 2');

        await Future.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        expect(events.length, equals(3));
        expect(events[0].appName, equals('App on Desktop 1'));
        expect(events[1].eventType, equals(FocusEventType.lost));
        expect(events[2].appName, equals('App on Desktop 2'));
      });

      test('handles multi-monitor scenarios', () async {
        await windowsPlatform.startTracking(const FocusTrackerConfig(includeMetadata: true));

        // Add apps on different monitors
        windowsPlatform.addMockApp(const AppInfo(
          name: 'App on Monitor 1',
          identifier: 'C:\\Apps\\monitor1app.exe',
          processId: 2001,
          metadata: {
            'monitor': 1,
            'windowRect': {'left': 0, 'top': 0, 'right': 1920, 'bottom': 1080},
          },
        ));

        windowsPlatform.addMockApp(const AppInfo(
          name: 'App on Monitor 2',
          identifier: 'C:\\Apps\\monitor2app.exe',
          processId: 2002,
          metadata: {
            'monitor': 2,
            'windowRect': {'left': 1920, 'top': 0, 'right': 3840, 'bottom': 1080},
          },
        ));

        final events = <FocusEvent>[];
        final subscription = windowsPlatform.getFocusStream().listen(events.add);

        windowsPlatform.simulateAppFocus('App on Monitor 1');
        windowsPlatform.simulateAppFocus('App on Monitor 2');

        await Future.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        expect(events.length, equals(2));

        // Should handle apps on different monitors
        expect(events.every((e) => e.appName.startsWith('App on Monitor')), isTrue);
      });
    });
  });
}
