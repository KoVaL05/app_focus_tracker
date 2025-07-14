import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/src/method_channel.dart';
import 'package:app_focus_tracker/src/models/models.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Type Casting Fix Tests', () {
    test('handles _Map<Object?, Object?> from platform correctly', () async {
      // Create a mock method channel that returns the problematic map type
      const MethodChannel methodChannel = MethodChannel('app_focus_tracker_method');

      // Mock the method channel to return a _Map<Object?, Object?>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannel,
        (MethodCall methodCall) async {
          if (methodCall.method == 'getRunningApplications') {
            // Return a list with a _Map<Object?, Object?> (simulated)
            return [
              {
                'name': 'Test App',
                'identifier': 'com.test.app',
                'processId': 1234,
                'version': '1.0.0',
                'executablePath': '/test/path',
                'metadata': {'category': 'test'},
              }
            ];
          }
          return null;
        },
      );

      try {
        final tracker = MethodChannelAppFocusTracker();
        final apps = await tracker.getRunningApplications();

        // Verify that the fix works and we get a proper AppInfo object
        expect(apps, isA<List<AppInfo>>());
        expect(apps.length, equals(1));

        final app = apps.first;
        expect(app.name, equals('Test App'));
        expect(app.identifier, equals('com.test.app'));
        expect(app.processId, equals(1234));
        expect(app.version, equals('1.0.0'));
        expect(app.executablePath, equals('/test/path'));
        expect(app.metadata?['category'], equals('test'));
      } finally {
        // Clean up the mock
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          methodChannel,
          null,
        );
      }
    });

    test('handles _Map<Object?, Object?> for getCurrentFocusedApp correctly', () async {
      const MethodChannel methodChannel = MethodChannel('app_focus_tracker_method');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannel,
        (MethodCall methodCall) async {
          if (methodCall.method == 'getCurrentFocusedApp') {
            return {
              'name': 'Current App',
              'identifier': 'com.current.app',
              'processId': 5678,
              'version': '2.0.0',
              'executablePath': '/current/path',
              'metadata': {'category': 'current'},
            };
          }
          return null;
        },
      );

      try {
        final tracker = MethodChannelAppFocusTracker();
        final app = await tracker.getCurrentFocusedApp();

        // Verify that the fix works and we get a proper AppInfo object
        expect(app, isA<AppInfo>());
        expect(app?.name, equals('Current App'));
        expect(app?.identifier, equals('com.current.app'));
        expect(app?.processId, equals(5678));
        expect(app?.version, equals('2.0.0'));
        expect(app?.executablePath, equals('/current/path'));
        expect(app?.metadata?['category'], equals('current'));
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          methodChannel,
          null,
        );
      }
    });

    test('handles null result from getCurrentFocusedApp correctly', () async {
      const MethodChannel methodChannel = MethodChannel('app_focus_tracker_method');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannel,
        (MethodCall methodCall) async {
          if (methodCall.method == 'getCurrentFocusedApp') {
            return null;
          }
          return null;
        },
      );

      try {
        final tracker = MethodChannelAppFocusTracker();
        final app = await tracker.getCurrentFocusedApp();

        // Verify that null is handled correctly
        expect(app, isNull);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          methodChannel,
          null,
        );
      }
    });

    test('handles empty list from getRunningApplications correctly', () async {
      const MethodChannel methodChannel = MethodChannel('app_focus_tracker_method');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannel,
        (MethodCall methodCall) async {
          if (methodCall.method == 'getRunningApplications') {
            return <dynamic>[];
          }
          return null;
        },
      );

      try {
        final tracker = MethodChannelAppFocusTracker();
        final apps = await tracker.getRunningApplications();

        // Verify that empty list is handled correctly
        expect(apps, isA<List<AppInfo>>());
        expect(apps.length, equals(0));
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          methodChannel,
          null,
        );
      }
    });
  });
}
