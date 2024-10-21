import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/app_focus_tracker.dart';
import 'package:app_focus_tracker/app_focus_tracker_platform_interface.dart';
import 'package:app_focus_tracker/app_focus_tracker_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAppFocusTrackerPlatform
    with MockPlatformInterfaceMixin
    implements AppFocusTrackerPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final AppFocusTrackerPlatform initialPlatform = AppFocusTrackerPlatform.instance;

  test('$MethodChannelAppFocusTracker is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAppFocusTracker>());
  });

  test('getPlatformVersion', () async {
    AppFocusTracker appFocusTrackerPlugin = AppFocusTracker();
    MockAppFocusTrackerPlatform fakePlatform = MockAppFocusTrackerPlatform();
    AppFocusTrackerPlatform.instance = fakePlatform;

    expect(await appFocusTrackerPlugin.getPlatformVersion(), '42');
  });
}
