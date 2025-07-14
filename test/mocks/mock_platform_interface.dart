import 'dart:async';
import 'package:app_focus_tracker/src/platform_interface.dart';
import 'package:app_focus_tracker/src/models/models.dart';
import 'package:app_focus_tracker/src/exceptions/app_focus_tracker_exception.dart';

/// Mock platform implementation for testing
class MockAppFocusTrackerPlatform extends AppFocusTrackerPlatform {
  MockAppFocusTrackerPlatform({
    this.platformName = 'MockPlatform',
    bool isSupported = true,
    bool hasPermissions = true,
    this.simulatePermissionRequest = true,
    this.simulateErrors = false,
    this.simulateSlowResponses = false,
    this.enableAutomaticEvents = false, // Disable by default for cleaner test behavior
  })  : _isSupported = isSupported,
        _hasPermissions = hasPermissions;

  final String platformName;
  final bool _isSupported;
  final bool _hasPermissions;
  final bool simulatePermissionRequest;
  final bool simulateErrors;
  final bool simulateSlowResponses;
  final bool enableAutomaticEvents;

  bool _isTracking = false;
  FocusTrackerConfig? _currentConfig;
  StreamController<FocusEvent>? _eventStreamController;
  Timer? _eventTimer;
  String? _currentSessionId;
  int _eventCounter = 0;

  // Mock app data
  final List<AppInfo> _mockRunningApps = [
    const AppInfo(
      name: 'Mock App 1',
      identifier: 'com.mock.app1',
      processId: 1001,
      version: '1.0.0',
      executablePath: '/mock/path/app1',
      metadata: {'category': 'productivity'},
    ),
    const AppInfo(
      name: 'Mock App 2',
      identifier: 'com.mock.app2',
      processId: 1002,
      version: '2.1.0',
      executablePath: '/mock/path/app2',
      metadata: {'category': 'entertainment'},
    ),
    const AppInfo(
      name: 'System App',
      identifier: 'com.system.app',
      processId: 2001,
      version: '1.0.0',
      executablePath: '/system/app',
      metadata: {'category': 'system'},
    ),
  ];

  int _currentAppIndex = 0;
  DateTime _focusStartTime = DateTime.now();

  // Mock diagnostic data
  final Map<String, dynamic> _diagnosticInfo = {
    'platform': 'MockPlatform',
    'version': '1.0.0-mock',
    'capabilities': ['focus_tracking', 'app_enumeration'],
    'performance': {
      'cpu_usage': 0.5,
      'memory_usage': 1024 * 1024, // 1MB
    },
  };

  // Override in subclasses
  Map<String, dynamic> get diagnosticInfo => _diagnosticInfo;

  @override
  Future<String> getPlatformName() async {
    await _simulateDelay();
    _throwIfSimulatingErrors('getPlatformName');
    return platformName;
  }

  @override
  Future<bool> isSupported() async {
    await _simulateDelay();
    _throwIfSimulatingErrors('isSupported');
    return _isSupported;
  }

  @override
  Future<bool> hasPermissions() async {
    await _simulateDelay();
    _throwIfSimulatingErrors('hasPermissions');
    return _hasPermissions;
  }

  @override
  Future<bool> requestPermissions() async {
    await _simulateDelay();
    _throwIfSimulatingErrors('requestPermissions');

    if (!simulatePermissionRequest) {
      throw const PermissionDeniedException(
        'Permission request denied by user',
        permissionType: 'focus_tracking',
      );
    }

    return simulatePermissionRequest;
  }

  @override
  Future<void> startTracking(FocusTrackerConfig config) async {
    await _simulateDelay();
    _throwIfSimulatingErrors('startTracking');

    if (!_isSupported) {
      throw PlatformNotSupportedException.create(platformName);
    }

    if (!_hasPermissions) {
      throw const PermissionDeniedException(
        'Permissions not granted',
        permissionType: 'focus_tracking',
      );
    }

    if (_isTracking) {
      throw const PlatformChannelException(
        'Tracking is already active',
        code: 'ALREADY_TRACKING',
      );
    }

    _currentConfig = config;
    _isTracking = true;
    _currentSessionId = _generateSessionId();
    _focusStartTime = DateTime.now();

    // Set up event stream
    _eventStreamController = StreamController<FocusEvent>.broadcast();
    _startMockEventGeneration();
  }

  @override
  Future<void> stopTracking() async {
    await _simulateDelay();
    _throwIfSimulatingErrors('stopTracking');

    if (!_isTracking) {
      return; // Already stopped
    }

    _isTracking = false;
    _currentConfig = null;
    _currentSessionId = null;

    _eventTimer?.cancel();
    _eventTimer = null;

    await _eventStreamController?.close();
    _eventStreamController = null;
  }

  @override
  Future<bool> isTracking() async {
    await _simulateDelay();
    _throwIfSimulatingErrors('isTracking');
    return _isTracking;
  }

  @override
  Stream<FocusEvent> getFocusStream() {
    if (_eventStreamController == null) {
      throw StateError('Tracking must be started before accessing the focus stream');
    }
    return _eventStreamController!.stream;
  }

  @override
  Future<AppInfo?> getCurrentFocusedApp() async {
    await _simulateDelay();
    _throwIfSimulatingErrors('getCurrentFocusedApp');

    if (_mockRunningApps.isEmpty) return null;
    return _mockRunningApps[_currentAppIndex % _mockRunningApps.length];
  }

  @override
  Future<List<AppInfo>> getRunningApplications({bool includeSystemApps = false}) async {
    await _simulateDelay();
    _throwIfSimulatingErrors('getRunningApplications');

    List<AppInfo> apps = List.from(_mockRunningApps);

    if (!includeSystemApps) {
      apps = apps.where((app) => app.metadata?['category'] != 'system').toList();
    }

    return apps;
  }

  @override
  Future<bool> updateConfiguration(FocusTrackerConfig config) async {
    await _simulateDelay();
    _throwIfSimulatingErrors('updateConfiguration');

    if (!_isTracking) {
      throw const PlatformChannelException(
        'Cannot update configuration while tracking is not active',
        code: 'NOT_TRACKING',
      );
    }

    _currentConfig = config;

    // Restart event generation with new config
    _eventTimer?.cancel();
    _startMockEventGeneration();

    return true; // Mock always supports dynamic updates
  }

  @override
  Future<Map<String, dynamic>> getDiagnosticInfo() async {
    await _simulateDelay();
    _throwIfSimulatingErrors('getDiagnosticInfo');

    final diagnostics = Map<String, dynamic>.from(diagnosticInfo);
    diagnostics['platform'] = platformName; // Use the actual platform name
    diagnostics['isTracking'] = _isTracking;
    diagnostics['hasPermissions'] = _hasPermissions;
    diagnostics['sessionId'] = _currentSessionId;
    diagnostics['config'] = _currentConfig?.toJson();
    diagnostics['eventCount'] = _eventCounter;
    diagnostics['uptime'] = _isTracking ? DateTime.now().difference(_focusStartTime).inMilliseconds : 0;

    return diagnostics;
  }

  // Mock-specific methods for testing

  /// Simulates an app gaining focus
  void simulateAppFocus(String appName, {String? appIdentifier, int? processId}) {
    if (!_isTracking || _eventStreamController == null) return;

    final event = FocusEvent(
      appName: appName,
      appIdentifier: appIdentifier ?? 'com.mock.$appName',
      durationMicroseconds: 0,
      processId: processId ?? 9999,
      eventType: FocusEventType.gained,
      sessionId: _currentSessionId,
      metadata: _currentConfig?.includeMetadata == true
          ? {
              'mockEvent': true,
              'simulatedAt': DateTime.now().toIso8601String(),
            }
          : null,
    );

    _eventStreamController!.add(event);
    _eventCounter++;
  }

  /// Simulates an app losing focus with duration
  void simulateAppBlur(String appName, Duration duration, {String? appIdentifier, int? processId}) {
    if (!_isTracking || _eventStreamController == null) return;

    final event = FocusEvent(
      appName: appName,
      appIdentifier: appIdentifier ?? 'com.mock.$appName',
      durationMicroseconds: duration.inMicroseconds,
      processId: processId ?? 9999,
      eventType: FocusEventType.lost,
      sessionId: _currentSessionId,
      metadata: _currentConfig?.includeMetadata == true
          ? {
              'mockEvent': true,
              'simulatedAt': DateTime.now().toIso8601String(),
            }
          : null,
    );

    _eventStreamController!.add(event);
    _eventCounter++;
  }

  /// Simulates a duration update for currently focused app
  void simulateDurationUpdate(String appName, Duration duration, {String? appIdentifier, int? processId}) {
    if (!_isTracking || _eventStreamController == null) return;

    final event = FocusEvent(
      appName: appName,
      appIdentifier: appIdentifier ?? 'com.mock.$appName',
      durationMicroseconds: duration.inMicroseconds,
      processId: processId ?? 9999,
      eventType: FocusEventType.durationUpdate,
      sessionId: _currentSessionId,
      metadata: _currentConfig?.includeMetadata == true
          ? {
              'mockEvent': true,
              'simulatedAt': DateTime.now().toIso8601String(),
            }
          : null,
    );

    _eventStreamController!.add(event);
    _eventCounter++;
  }

  /// Adds a mock app to the running applications list
  void addMockApp(AppInfo appInfo) {
    _mockRunningApps.add(appInfo);
  }

  /// Removes a mock app from the running applications list
  void removeMockApp(String identifier) {
    _mockRunningApps.removeWhere((app) => app.identifier == identifier);
  }

  /// Simulates an error on the next method call
  void simulateError(String method, AppFocusTrackerException error) {
    _pendingErrors[method] = error;
  }

  /// Resets the mock to initial state
  void reset() {
    _isTracking = false;
    _currentConfig = null;
    _currentSessionId = null;
    _eventCounter = 0;
    _eventTimer?.cancel();
    _eventTimer = null;
    _eventStreamController?.close();
    _eventStreamController = null;
    _pendingErrors.clear();
    _currentAppIndex = 0;
    _focusStartTime = DateTime.now();
  }

  // Private helper methods

  final Map<String, AppFocusTrackerException> _pendingErrors = {};

  void _throwIfSimulatingErrors(String methodName) {
    if (_pendingErrors.containsKey(methodName)) {
      final error = _pendingErrors.remove(methodName)!;
      throw error;
    }

    if (simulateErrors) {
      throw PlatformChannelException(
        'Simulated error in $methodName',
        code: 'MOCK_ERROR',
      );
    }
  }

  Future<void> _simulateDelay() async {
    if (simulateSlowResponses) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _startMockEventGeneration() {
    if (_currentConfig == null || !enableAutomaticEvents) return;

    final interval = Duration(milliseconds: _currentConfig!.updateIntervalMs);

    _eventTimer = Timer.periodic(interval, (timer) {
      if (!_isTracking || _eventStreamController == null) {
        timer.cancel();
        return;
      }

      // Randomly switch apps or send duration updates
      if (_eventCounter % 5 == 0) {
        // Switch to a different app
        _currentAppIndex = (_currentAppIndex + 1) % _mockRunningApps.length;
        final newApp = _mockRunningApps[_currentAppIndex];
        simulateAppFocus(
          newApp.name,
          appIdentifier: newApp.identifier,
          processId: newApp.processId,
        );
        _focusStartTime = DateTime.now();
      } else {
        // Send duration update for current app
        final currentApp = _mockRunningApps[_currentAppIndex];
        final duration = DateTime.now().difference(_focusStartTime);
        simulateDurationUpdate(
          currentApp.name,
          duration,
          appIdentifier: currentApp.identifier,
          processId: currentApp.processId,
        );
      }
    });
  }

  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'mock_session_${timestamp}_${_eventCounter}';
  }
}

/// Factory for creating mock platforms with specific configurations
class MockPlatformFactory {
  /// Creates a mock platform that simulates macOS
  static MockAppFocusTrackerPlatform createMacOSMock({
    bool hasPermissions = true, // Default to true for most tests
    bool simulatePermissionRequest = true,
  }) {
    return _MacOSMockPlatform(
      platformName: 'macOS',
      hasPermissions: hasPermissions,
      simulatePermissionRequest: simulatePermissionRequest,
    );
  }

  /// Creates a mock platform that simulates Windows
  static MockAppFocusTrackerPlatform createWindowsMock({
    bool hasPermissions = true,
  }) {
    return _WindowsMockPlatform(
      platformName: 'Windows',
      hasPermissions: hasPermissions,
      simulatePermissionRequest: true,
    );
  }

  /// Creates a mock platform that simulates an unsupported platform
  static MockAppFocusTrackerPlatform createUnsupportedMock() {
    return MockAppFocusTrackerPlatform(
      platformName: 'Unsupported Platform',
      isSupported: false,
      hasPermissions: false,
      simulatePermissionRequest: false,
    );
  }

  /// Creates a mock platform that simulates various errors
  static MockAppFocusTrackerPlatform createErrorMock() {
    return MockAppFocusTrackerPlatform(
      platformName: 'Error Platform',
      simulateErrors: true,
    );
  }

  /// Creates a mock platform with slow responses for performance testing
  static MockAppFocusTrackerPlatform createSlowMock() {
    return MockAppFocusTrackerPlatform(
      platformName: 'Slow Platform',
      simulateSlowResponses: true,
    );
  }
}

/// Specialized macOS mock that can change permissions after requests
class _MacOSMockPlatform extends MockAppFocusTrackerPlatform {
  _MacOSMockPlatform({
    required String platformName,
    required bool hasPermissions,
    required bool simulatePermissionRequest,
  }) : _currentPermissions = hasPermissions,
       super(
         platformName: platformName,
         hasPermissions: hasPermissions,
         simulatePermissionRequest: simulatePermissionRequest,
       );

  bool _currentPermissions;

  @override
  Future<bool> hasPermissions() async {
    await _simulateDelay();
    _throwIfSimulatingErrors('hasPermissions');
    return _currentPermissions;
  }

  @override
  Future<bool> requestPermissions() async {
    await _simulateDelay();
    _throwIfSimulatingErrors('requestPermissions');

    if (!simulatePermissionRequest) {
      throw const PermissionDeniedException(
        'Permission request denied by user',
        permissionType: 'focus_tracking',
      );
    }

    // Grant permissions after successful request
    _currentPermissions = true;
    return true;
  }

  @override
  Future<void> startTracking(FocusTrackerConfig config) async {
    await _simulateDelay();
    _throwIfSimulatingErrors('startTracking');

    if (!_isSupported) {
      throw PlatformNotSupportedException.create(platformName);
    }

    if (!_currentPermissions) {
      throw const PermissionDeniedException(
        'Permissions not granted',
        permissionType: 'focus_tracking',
      );
    }

    if (_isTracking) {
      throw const PlatformChannelException(
        'Tracking is already active',
        code: 'ALREADY_TRACKING',
      );
    }

    _currentConfig = config;
    _isTracking = true;
    _currentSessionId = _generateSessionId();
    _focusStartTime = DateTime.now();

    // Set up event stream
    _eventStreamController = StreamController<FocusEvent>.broadcast();
    _startMockEventGeneration();
  }
}

/// Specialized Windows mock that handles Windows-specific behavior
class _WindowsMockPlatform extends MockAppFocusTrackerPlatform {
  _WindowsMockPlatform({
    required String platformName,
    required bool hasPermissions,
    required bool simulatePermissionRequest,
  }) : super(
         platformName: platformName,
         hasPermissions: hasPermissions,
         simulatePermissionRequest: simulatePermissionRequest,
       );

  @override
  Map<String, dynamic> get diagnosticInfo => {
    'platform': platformName,
    'version': '1.0.0-windows-mock',
    'systemVersion': 'Windows 10.0.19041',
    'capabilities': ['focus_tracking', 'app_enumeration', 'win32_api'],
    'performance': {
      'cpu_usage': 0.3,
      'memory_usage': 2048 * 1024, // 2MB
    },
  };

  @override
  Future<List<AppInfo>> getRunningApplications({bool includeSystemApps = false}) async {
    await _simulateDelay();
    _throwIfSimulatingErrors('getRunningApplications');

    // Check if we have errors queued - if so, throw them
    if (_pendingErrors.containsKey('getRunningApplications')) {
      final error = _pendingErrors.remove('getRunningApplications')!;
      throw error;
    }

    List<AppInfo> apps = List.from(_mockRunningApps);

    if (!includeSystemApps) {
      apps = apps.where((app) => app.metadata?['category'] != 'system').toList();
    }

    return apps;
  }
}
