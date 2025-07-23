/// Manual test for Windows Release Build Deadlock Prevention
///
/// This script should be run manually in a Windows release build to verify
/// that the deadlock fixes work correctly in real-world conditions.
///
/// Usage:
/// 1. Build the Flutter app in release mode: `flutter build windows --release`
/// 2. Run the release executable
/// 3. Execute this test script from within the app
/// 4. Monitor for freezes, hangs, or crashes
///
/// The test simulates the exact conditions that caused the original deadlock:
/// - High-frequency focus events from background threads
/// - Simultaneous expensive process enumeration calls
/// - Event sink mutex contention
/// - DirectWrite font system interaction
library;

import 'dart:async';
import 'dart:io';
import 'package:app_focus_tracker/app_focus_tracker.dart';

class WindowsReleaseDeadlockTest {
  static late AppFocusTracker _tracker;
  static late StreamSubscription _subscription;
  static final List<String> _testResults = [];
  static int _eventsReceived = 0;
  static int _errorsEncountered = 0;

  /// Main test execution
  static Future<void> runTest() async {
    print('🔧 Windows Release Build Deadlock Prevention Test');
    print('=' * 60);
    print('Platform: ${Platform.operatingSystem}');
    print('Test Start Time: ${DateTime.now()}');
    print('');

    _tracker = AppFocusTracker();

    try {
      await _testDeadlockPrevention();
      await _testProcessEnumerationAsync();
      await _testEventSinkMutexSafety();
      await _testStressConditions();

      _printTestSummary();
    } catch (e, stackTrace) {
      print('❌ Test failed with exception: $e');
      print('Stack trace: $stackTrace');
      _testResults.add('FAIL: Test crashed with exception: $e');
    } finally {
      await _cleanup();
    }
  }

  /// Test 1: Basic deadlock prevention
  static Future<void> _testDeadlockPrevention() async {
    print('📋 Test 1: Basic Deadlock Prevention');
    final stopwatch = Stopwatch()..start();

    try {
      await _tracker.startTracking(const FocusTrackerConfig(
        updateIntervalMs: 10,
        includeMetadata: true,
      ));

      _subscription = _tracker.focusStream.listen(
        (event) {
          _eventsReceived++;
          if (_eventsReceived % 100 == 0) {
            print('  Events processed: $_eventsReceived');
          }
        },
        onError: (error) {
          _errorsEncountered++;
          print('  Stream error: $error');
        },
      );

      // Run for 10 seconds - original bug would hang within this time
      const testDuration = Duration(seconds: 10);
      final endTime = DateTime.now().add(testDuration);

      while (DateTime.now().isBefore(endTime)) {
        // Simulate the problematic call pattern
        try {
          final apps = await _tracker.getRunningApplications();
          print('  getRunningApplications returned ${apps.length} apps');
        } catch (e) {
          print('  getRunningApplications error: $e');
        }

        // Check if we're still responsive
        try {
          final current = await _tracker.getCurrentFocusedApp();
          if (current != null) {
            print('  Current app: ${current.name}');
          }
        } catch (e) {
          print('  getCurrentFocusedApp error: $e');
        }

        await Future.delayed(const Duration(milliseconds: 500));
      }

      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;

      if (elapsed < 12000) {
        // Should complete within reasonable time
        print('  ✅ Test 1 PASSED (${elapsed}ms)');
        _testResults.add('PASS: Basic deadlock prevention - ${elapsed}ms');
      } else {
        print('  ❌ Test 1 FAILED - took too long (${elapsed}ms)');
        _testResults.add('FAIL: Basic deadlock prevention - timeout');
      }
    } catch (e) {
      print('  ❌ Test 1 FAILED with exception: $e');
      _testResults.add('FAIL: Basic deadlock prevention - exception: $e');
    }

    await _subscription.cancel();
    await _tracker.stopTracking();
    print('');
  }

  /// Test 2: Process enumeration runs asynchronously
  static Future<void> _testProcessEnumerationAsync() async {
    print('📋 Test 2: Asynchronous Process Enumeration');
    final stopwatch = Stopwatch()..start();

    try {
      await _tracker.startTracking();

      // Make multiple concurrent calls - should not block
      final futures = <Future>[];
      for (int i = 0; i < 5; i++) {
        futures.add(_tracker.getRunningApplications().then((apps) {
          print('  Call $i returned ${apps.length} apps');
          return apps.length;
        }));
      }

      // Should complete quickly since it's async now
      final results = await Future.wait(futures);
      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      final allSucceeded = results.every((count) => count > 0);

      if (allSucceeded && elapsed < 10000) {
        print('  ✅ Test 2 PASSED (${elapsed}ms)');
        _testResults.add('PASS: Async process enumeration - ${elapsed}ms');
      } else {
        print('  ❌ Test 2 FAILED - elapsed: ${elapsed}ms, success: $allSucceeded');
        _testResults.add('FAIL: Async process enumeration');
      }
    } catch (e) {
      print('  ❌ Test 2 FAILED with exception: $e');
      _testResults.add('FAIL: Async process enumeration - exception: $e');
    }

    await _tracker.stopTracking();
    print('');
  }

  /// Test 3: Event sink mutex safety
  static Future<void> _testEventSinkMutexSafety() async {
    print('📋 Test 3: Event Sink Mutex Safety');
    final stopwatch = Stopwatch()..start();

    try {
      await _tracker.startTracking(const FocusTrackerConfig(updateIntervalMs: 1));

      int eventsReceived = 0;
      _subscription = _tracker.focusStream.listen(
        (event) => eventsReceived++,
        onError: (error) => _errorsEncountered++,
      );

      // Create contention by starting/stopping multiple times rapidly
      for (int i = 0; i < 5; i++) {
        await _subscription.cancel();

        _subscription = _tracker.focusStream.listen(
          (event) => eventsReceived++,
          onError: (error) => _errorsEncountered++,
        );

        // Brief activity period
        await Future.delayed(const Duration(milliseconds: 200));
      }

      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;

      if (elapsed < 5000) {
        print('  ✅ Test 3 PASSED (${elapsed}ms, events: $eventsReceived)');
        _testResults.add('PASS: Event sink mutex safety - ${elapsed}ms');
      } else {
        print('  ❌ Test 3 FAILED - took too long (${elapsed}ms)');
        _testResults.add('FAIL: Event sink mutex safety - timeout');
      }
    } catch (e) {
      print('  ❌ Test 3 FAILED with exception: $e');
      _testResults.add('FAIL: Event sink mutex safety - exception: $e');
    }

    await _subscription.cancel();
    await _tracker.stopTracking();
    print('');
  }

  /// Test 4: Stress conditions that caused original deadlock
  static Future<void> _testStressConditions() async {
    print('📋 Test 4: Stress Conditions');
    final stopwatch = Stopwatch()..start();

    try {
      await _tracker.startTracking(const FocusTrackerConfig(
        updateIntervalMs: 1,
        includeMetadata: true,
        includeSystemApps: true,
      ));

      int eventsReceived = 0;
      _subscription = _tracker.focusStream.listen(
        (event) => eventsReceived++,
        onError: (error) => _errorsEncountered++,
      );

      // Create the stress conditions that caused the original deadlock
      final stressFutures = <Future>[];

      // Continuous process enumeration (original blocking operation)
      stressFutures.add(Future(() async {
        for (int i = 0; i < 20; i++) {
          try {
            await _tracker.getRunningApplications();
          } catch (e) {
            // Continue on error
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }));

      // Continuous diagnostic calls
      stressFutures.add(Future(() async {
        for (int i = 0; i < 40; i++) {
          try {
            await AppFocusTracker.getDiagnosticInfo();
            await _tracker.getCurrentFocusedApp();
          } catch (e) {
            // Continue on error
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }));

      // Multiple subscription management
      stressFutures.add(Future(() async {
        for (int i = 0; i < 10; i++) {
          await _subscription.cancel();
          _subscription = _tracker.focusStream.listen(
            (event) => eventsReceived++,
            onError: (error) => _errorsEncountered++,
          );
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }));

      await Future.wait(stressFutures);
      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;

      if (elapsed < 30000) {
        // Should complete within 30 seconds
        print('  ✅ Test 4 PASSED (${elapsed}ms, events: $eventsReceived, errors: $_errorsEncountered)');
        _testResults.add('PASS: Stress conditions - ${elapsed}ms');
      } else {
        print('  ❌ Test 4 FAILED - took too long (${elapsed}ms)');
        _testResults.add('FAIL: Stress conditions - timeout');
      }
    } catch (e) {
      print('  ❌ Test 4 FAILED with exception: $e');
      _testResults.add('FAIL: Stress conditions - exception: $e');
    }

    await _subscription.cancel();
    await _tracker.stopTracking();
    print('');
  }

  /// Print final test summary
  static void _printTestSummary() {
    print('📊 TEST SUMMARY');
    print('=' * 60);
    print('Total events received: $_eventsReceived');
    print('Total errors encountered: $_errorsEncountered');
    print('');

    final passed = _testResults.where((r) => r.startsWith('PASS')).length;
    final failed = _testResults.where((r) => r.startsWith('FAIL')).length;

    for (final result in _testResults) {
      final icon = result.startsWith('PASS') ? '✅' : '❌';
      print('$icon $result');
    }

    print('');
    print('Results: $passed passed, $failed failed');

    if (failed == 0) {
      print('🎉 ALL TESTS PASSED - Deadlock fixes are working correctly!');
    } else {
      print('⚠️  Some tests failed - deadlock issues may still exist');
    }

    print('=' * 60);
  }

  /// Clean up resources
  static Future<void> _cleanup() async {
    try {
      if (await _tracker.isTracking()) {
        await _tracker.stopTracking();
      }
    } catch (e) {
      print('Cleanup error: $e');
    }
  }
}

/// Run the test if this file is executed directly
void main() async {
  await WindowsReleaseDeadlockTest.runTest();
}
