import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/src/method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelAppFocusTracker platform = MethodChannelAppFocusTracker();
  const MethodChannel channel = MethodChannel('app_focus_tracker_method');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'getPlatformName':
            return 'MockPlatform';
          case 'isSupported':
            return true;
          case 'hasPermissions':
            return true;
          case 'requestPermissions':
            return true;
          case 'startTracking':
            return null;
          case 'stopTracking':
            return null;
          case 'isTracking':
            return false;
          case 'getCurrentFocusedApp':
            return null;
          case 'getRunningApplications':
            return [];
          case 'updateConfiguration':
            return true;
          case 'getDiagnosticInfo':
            return {};
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformName', () async {
    expect(await platform.getPlatformName(), 'MockPlatform');
  });
}
