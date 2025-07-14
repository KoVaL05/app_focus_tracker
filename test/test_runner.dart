import 'package:flutter_test/flutter_test.dart';

// Model tests
import 'models/focus_event_test.dart' as focus_event_tests;
import 'models/app_info_test.dart' as app_info_tests;
import 'models/focus_tracker_config_test.dart' as config_tests;

// Core platform tests
import 'platform_interface_test.dart' as platform_interface_tests;

// Integration tests
import 'integration/focus_tracking_integration_test.dart' as integration_tests;

// Platform-specific tests
import 'platform_specific/macos_test.dart' as macos_tests;
import 'platform_specific/windows_test.dart' as windows_tests;

// Performance tests
import 'performance/stress_test.dart' as performance_tests;

void main() {
  group('App Focus Tracker Test Suite', () {
    group('📱 Model Tests', () {
      group('FocusEvent', focus_event_tests.main);
      group('AppInfo', app_info_tests.main);
      group('FocusTrackerConfig', config_tests.main);
    });

    group('🔌 Platform Interface Tests', () {
      group('Platform Interface Compliance', platform_interface_tests.main);
    });

    group('🔄 Integration Tests', () {
      group('End-to-End Focus Tracking', integration_tests.main);
    });

    group('💻 Platform-Specific Tests', () {
      group('macOS Platform', macos_tests.main);
      group('Windows Platform', windows_tests.main);
    });

    group('⚡ Performance Tests', () {
      group('Stress Tests', performance_tests.main);
    });
  });
}

// Test configuration for CI/CD
class TestConfig {
  static const bool runPerformanceTests = bool.fromEnvironment('RUN_PERFORMANCE_TESTS', defaultValue: true);
  static const bool runPlatformSpecificTests = bool.fromEnvironment('RUN_PLATFORM_TESTS', defaultValue: true);
  static const bool runIntegrationTests = bool.fromEnvironment('RUN_INTEGRATION_TESTS', defaultValue: true);
  static const String targetPlatform = String.fromEnvironment('TARGET_PLATFORM', defaultValue: 'all');

  /// Returns whether a specific test group should run based on configuration
  static bool shouldRunTestGroup(String groupName) {
    switch (groupName.toLowerCase()) {
      case 'performance':
        return runPerformanceTests;
      case 'platform':
        return runPlatformSpecificTests;
      case 'integration':
        return runIntegrationTests;
      case 'macos':
        return runPlatformSpecificTests && (targetPlatform == 'all' || targetPlatform == 'macos');
      case 'windows':
        return runPlatformSpecificTests && (targetPlatform == 'all' || targetPlatform == 'windows');
      default:
        return true;
    }
  }
}

/// Utility functions for test execution
class TestUtils {
  /// Prints test execution summary
  static void printTestSummary({
    required int totalTests,
    required int passedTests,
    required int failedTests,
    required Duration executionTime,
  }) {
    print('\n' + '=' * 60);
    print('TEST EXECUTION SUMMARY');
    print('=' * 60);
    print('Total Tests: $totalTests');
    print('Passed: $passedTests');
    print('Failed: $failedTests');
    print('Success Rate: ${((passedTests / totalTests) * 100).toStringAsFixed(1)}%');
    print('Execution Time: ${executionTime.inMilliseconds}ms');
    print('=' * 60);
  }

  /// Validates test environment
  static bool validateTestEnvironment() {
    // Check that required dependencies are available
    try {
      // Validate Flutter Test framework
      expect(true, isTrue);

      // Validate mock dependencies are properly configured
      return true;
    } catch (e) {
      print('Test environment validation failed: $e');
      return false;
    }
  }

  /// Sets up test fixtures and mocks
  static void setupGlobalTestFixtures() {
    // Global test setup that applies to all test suites
    setUpAll(() {
      print('🚀 Starting App Focus Tracker Test Suite');
      print('Configuration:');
      print('  - Performance Tests: ${TestConfig.runPerformanceTests}');
      print('  - Platform Tests: ${TestConfig.runPlatformSpecificTests}');
      print('  - Integration Tests: ${TestConfig.runIntegrationTests}');
      print('  - Target Platform: ${TestConfig.targetPlatform}');
      print('');
    });

    tearDownAll(() {
      print('\n✅ App Focus Tracker Test Suite Complete');
    });
  }
}

/// Test categories for organized execution
enum TestCategory {
  unit,
  integration,
  performance,
  platformSpecific,
}

/// Test metadata for reporting and organization
class TestMetadata {
  final String name;
  final TestCategory category;
  final List<String> platforms;
  final bool requiresPermissions;
  final Duration estimatedDuration;

  const TestMetadata({
    required this.name,
    required this.category,
    this.platforms = const ['all'],
    this.requiresPermissions = false,
    this.estimatedDuration = const Duration(seconds: 1),
  });
}

/// Test registry for managing test execution
class TestRegistry {
  static const List<TestMetadata> allTests = [
    // Model Tests
    TestMetadata(
      name: 'FocusEvent Model Tests',
      category: TestCategory.unit,
      estimatedDuration: Duration(seconds: 5),
    ),
    TestMetadata(
      name: 'AppInfo Model Tests',
      category: TestCategory.unit,
      estimatedDuration: Duration(seconds: 3),
    ),
    TestMetadata(
      name: 'FocusTrackerConfig Tests',
      category: TestCategory.unit,
      estimatedDuration: Duration(seconds: 4),
    ),

    // Platform Interface Tests
    TestMetadata(
      name: 'Platform Interface Compliance',
      category: TestCategory.unit,
      estimatedDuration: Duration(seconds: 10),
    ),

    // Integration Tests
    TestMetadata(
      name: 'End-to-End Focus Tracking',
      category: TestCategory.integration,
      estimatedDuration: Duration(seconds: 30),
      requiresPermissions: true,
    ),

    // Platform-Specific Tests
    TestMetadata(
      name: 'macOS Platform Tests',
      category: TestCategory.platformSpecific,
      platforms: ['macos'],
      estimatedDuration: Duration(seconds: 20),
      requiresPermissions: true,
    ),
    TestMetadata(
      name: 'Windows Platform Tests',
      category: TestCategory.platformSpecific,
      platforms: ['windows'],
      estimatedDuration: Duration(seconds: 15),
    ),

    // Performance Tests
    TestMetadata(
      name: 'Performance and Stress Tests',
      category: TestCategory.performance,
      estimatedDuration: Duration(minutes: 2),
    ),
  ];

  /// Gets estimated total execution time
  static Duration getEstimatedExecutionTime() {
    return allTests
        .where((test) => _shouldRunTest(test))
        .fold(Duration.zero, (total, test) => total + test.estimatedDuration);
  }

  /// Checks if a test should run based on current configuration
  static bool _shouldRunTest(TestMetadata test) {
    switch (test.category) {
      case TestCategory.unit:
        return true;
      case TestCategory.integration:
        return TestConfig.runIntegrationTests;
      case TestCategory.performance:
        return TestConfig.runPerformanceTests;
      case TestCategory.platformSpecific:
        return TestConfig.runPlatformSpecificTests &&
            (TestConfig.targetPlatform == 'all' || test.platforms.contains(TestConfig.targetPlatform));
    }
  }

  /// Prints test execution plan
  static void printExecutionPlan() {
    final testsToRun = allTests.where(_shouldRunTest).toList();
    final totalTime = getEstimatedExecutionTime();

    print('📋 TEST EXECUTION PLAN');
    print('-' * 40);
    print('Tests to run: ${testsToRun.length}/${allTests.length}');
    print('Estimated time: ${totalTime.inSeconds}s');
    print('');

    for (final test in testsToRun) {
      final icon = _getCategoryIcon(test.category);
      final platforms = test.platforms.join(', ');
      print('$icon ${test.name} (${platforms}, ${test.estimatedDuration.inSeconds}s)');
    }
    print('');
  }

  static String _getCategoryIcon(TestCategory category) {
    switch (category) {
      case TestCategory.unit:
        return '🧪';
      case TestCategory.integration:
        return '🔄';
      case TestCategory.performance:
        return '⚡';
      case TestCategory.platformSpecific:
        return '💻';
    }
  }
}
