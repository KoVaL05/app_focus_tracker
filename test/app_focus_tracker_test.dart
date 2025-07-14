import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/app_focus_tracker.dart';
import 'package:app_focus_tracker/src/platform_interface.dart';
import 'package:app_focus_tracker/src/method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAppFocusTrackerPlatform with MockPlatformInterfaceMixin implements AppFocusTrackerPlatform {
  @override
  Future<String> getPlatformName() => Future.value('MockPlatform');

  @override
  Future<bool> isSupported() => Future.value(true);

  @override
  Future<bool> hasPermissions() => Future.value(true);

  @override
  Future<bool> requestPermissions() => Future.value(true);

  @override
  Future<void> startTracking(FocusTrackerConfig config) => Future.value();

  @override
  Future<void> stopTracking() => Future.value();

  @override
  Future<bool> isTracking() => Future.value(false);

  @override
  Stream<FocusEvent> getFocusStream() => Stream.empty();

  @override
  Future<AppInfo?> getCurrentFocusedApp() => Future.value(null);

  @override
  Future<List<AppInfo>> getRunningApplications({bool includeSystemApps = false}) => Future.value([]);

  @override
  Future<bool> updateConfiguration(FocusTrackerConfig config) => Future.value(true);

  @override
  Future<Map<String, dynamic>> getDiagnosticInfo() => Future.value({});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppFocusTrackerPlatform.instance = MockAppFocusTrackerPlatform();

  test('getPlatformVersion', () async {
    AppFocusTracker appFocusTrackerPlugin = AppFocusTracker();
    expect(await appFocusTrackerPlugin.getPlatformName(), 'MockPlatform');
  });
}
