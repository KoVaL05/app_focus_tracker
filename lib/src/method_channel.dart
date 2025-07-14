import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_interface.dart';
import 'models/focus_event.dart';
import 'models/focus_tracker_config.dart';
import 'models/app_info.dart';
import 'exceptions/app_focus_tracker_exception.dart';
import 'stream_manager.dart';
import 'utils/map_conversion.dart';

/// An implementation of [AppFocusTrackerPlatform] that uses method channels
/// with advanced stream management, retry mechanisms, and graceful degradation.
class MethodChannelAppFocusTracker extends AppFocusTrackerPlatform {
  /// Registers this implementation as the default platform instance.
  static void registerWith() {
    AppFocusTrackerPlatform.instance = MethodChannelAppFocusTracker();
  }

  /// The method channel used to interact with the native platform.
  @visibleForTesting
  static const MethodChannel methodChannel = MethodChannel('app_focus_tracker_method');

  /// The event channel used to receive focus events from the native platform.
  @visibleForTesting
  static const EventChannel eventChannel = EventChannel('app_focus_tracker_events');

  FocusStreamManager? _streamManager;
  StreamSubscription<dynamic>? _eventSubscription;
  bool _isTracking = false;
  FocusTrackerConfig? _currentConfig;

  // Retry and degradation state
  int _retryCount = 0;
  final int _maxRetries = 3;
  final Duration _retryDelay = const Duration(seconds: 1);
  bool _degradedMode = false;
  Timer? _recoveryTimer;

  // Performance monitoring
  DateTime? _lastSuccessfulOperation;
  int _errorCount = 0;
  final Map<String, int> _errorCounts = {};

  // Session management
  String? _currentSessionId;
  DateTime? _sessionStartTime;

  @override
  Future<String> getPlatformName() async {
    return _withRetry('getPlatformName', () async {
      try {
        final result = await methodChannel.invokeMethod<String>('getPlatformName');
        return result ?? _inferPlatformName();
      } on PlatformException catch (e) {
        throw PlatformChannelException(
          'Failed to get platform name: ${e.message}',
          channelName: 'getPlatformName',
          platformDetails: {'code': e.code, 'details': e.details},
          cause: e,
        );
      }
    });
  }

  @override
  Future<bool> isSupported() async {
    return _withRetry('isSupported', () async {
      try {
        final result = await methodChannel.invokeMethod<bool>('isSupported');
        return result ?? _inferPlatformSupport();
      } on PlatformException catch (e) {
        // If the method doesn't exist, fall back to platform detection
        if (e.code == 'unimplemented') {
          return _inferPlatformSupport();
        }
        throw PlatformChannelException(
          'Failed to check platform support: ${e.message}',
          channelName: 'isSupported',
          platformDetails: {'code': e.code, 'details': e.details},
          cause: e,
        );
      }
    });
  }

  @override
  Future<bool> hasPermissions() async {
    return _withRetry('hasPermissions', () async {
      try {
        final result = await methodChannel.invokeMethod<bool>('hasPermissions');
        return result ?? false;
      } on PlatformException catch (e) {
        if (e.code == 'permission_denied') {
          return false;
        }
        throw PlatformChannelException(
          'Failed to check permissions: ${e.message}',
          channelName: 'hasPermissions',
          platformDetails: {'code': e.code, 'details': e.details},
          cause: e,
        );
      }
    });
  }

  @override
  Future<bool> requestPermissions() async {
    return _withRetry('requestPermissions', () async {
      try {
        final result = await methodChannel.invokeMethod<bool>('requestPermissions');
        return result ?? false;
      } on PlatformException catch (e) {
        if (e.code == 'permission_denied') {
          final platform = await getPlatformName();
          if (platform.toLowerCase().contains('macos')) {
            throw PermissionDeniedException.macOSAccessibility();
          } else if (platform.toLowerCase().contains('windows')) {
            throw PermissionDeniedException.windowsPrivileges();
          }
          throw PermissionDeniedException(
            'Permission denied: ${e.message}',
            permissionType: 'unknown',
            code: e.code,
            cause: e,
          );
        }
        throw PlatformChannelException(
          'Failed to request permissions: ${e.message}',
          channelName: 'requestPermissions',
          platformDetails: {'code': e.code, 'details': e.details},
          cause: e,
        );
      }
    });
  }

  @override
  Future<void> openSystemSettings() async {
    return _withRetry('openSystemSettings', () async {
      try {
        await methodChannel.invokeMethod<void>('openSystemSettings');
      } on PlatformException catch (e) {
        throw PlatformChannelException(
          'Failed to open system settings: ${e.message}',
          channelName: 'openSystemSettings',
          platformDetails: {'code': e.code, 'details': e.details},
          cause: e,
        );
      }
    });
  }

  @override
  Future<void> startTracking(FocusTrackerConfig config) async {
    // Validate configuration
    _validateConfiguration(config);

    // Check platform support
    if (!await isSupported()) {
      final platform = await getPlatformName();
      throw PlatformNotSupportedException.create(platform);
    }

    // Check permissions
    if (!await hasPermissions()) {
      final granted = await requestPermissions();
      if (!granted) {
        final platform = await getPlatformName();
        if (platform.toLowerCase().contains('macos')) {
          throw PermissionDeniedException.macOSAccessibility();
        } else if (platform.toLowerCase().contains('windows')) {
          throw PermissionDeniedException.windowsPrivileges();
        }
        throw const PermissionDeniedException(
          'Permissions are required for focus tracking',
          permissionType: 'focus_tracking',
        );
      }
    }

    // Initialize stream manager
    _streamManager = _createStreamManager(config);
    await _streamManager!.start();

    // Start new session
    _currentSessionId = _generateSessionId();
    _sessionStartTime = DateTime.now();

    return _withRetry('startTracking', () async {
      try {
        await methodChannel.invokeMethod('startTracking', {
          'config': config.toJson(),
        });
        _currentConfig = config;
        _isTracking = true;
        _retryCount = 0;
        _degradedMode = false;
        _lastSuccessfulOperation = DateTime.now();

        _setupEventStream();
        _startRecoveryMonitoring();
      } on PlatformException catch (e) {
        throw PlatformChannelException(
          'Failed to start tracking: ${e.message}',
          channelName: 'startTracking',
          platformDetails: {'code': e.code, 'details': e.details},
          cause: e,
        );
      }
    });
  }

  @override
  Future<void> stopTracking() async {
    return _withRetry('stopTracking', () async {
      try {
        await methodChannel.invokeMethod('stopTracking');
        _isTracking = false;
        _currentConfig = null;
        _currentSessionId = null;
        _sessionStartTime = null;
        _degradedMode = false;

        await _closeEventStream();
        _stopRecoveryMonitoring();
      } on PlatformException catch (e) {
        throw PlatformChannelException(
          'Failed to stop tracking: ${e.message}',
          channelName: 'stopTracking',
          platformDetails: {'code': e.code, 'details': e.details},
          cause: e,
        );
      }
    });
  }

  @override
  Future<bool> isTracking() async {
    return _isTracking;
  }

  @override
  Stream<FocusEvent> getFocusStream() {
    if (_streamManager == null) {
      throw StateError('Tracking must be started before accessing the focus stream');
    }
    return _streamManager!.eventStream;
  }

  /// Gets a stream of batched focus events for performance optimization.
  Stream<List<FocusEvent>> getBatchStream() {
    if (_streamManager == null) {
      throw StateError('Tracking must be started before accessing the batch stream');
    }
    return _streamManager!.batchStream;
  }

  /// Gets a stream of events for a specific application.
  Stream<FocusEvent> getAppStream(String appName) {
    if (_streamManager == null) {
      throw StateError('Tracking must be started before accessing app streams');
    }
    return _streamManager!.getAppStream(appName);
  }

  @override
  Future<AppInfo?> getCurrentFocusedApp() async {
    return _withRetry('getCurrentFocusedApp', () async {
      try {
        final result = await methodChannel.invokeMethod('getCurrentFocusedApp');
        if (result != null) {
          // Safely convert the result to Map<String, dynamic>
          final appMap = safeMapConversion(result);
          if (appMap != null) {
            return AppInfo.fromJson(appMap);
          } else {
            throw PlatformChannelException(
              'Invalid app data format from platform channel',
              channelName: 'getCurrentFocusedApp',
              platformDetails: {'resultType': result.runtimeType.toString()},
            );
          }
        }
        return null;
      } on PlatformException catch (e) {
        throw PlatformChannelException(
          'Failed to get current focused app: ${e.message}',
          channelName: 'getCurrentFocusedApp',
          platformDetails: {'code': e.code, 'details': e.details},
          cause: e,
        );
      }
    });
  }

  @override
  Future<List<AppInfo>> getRunningApplications({bool includeSystemApps = false}) async {
    return _withRetry('getRunningApplications', () async {
      try {
        final result = await methodChannel.invokeMethod(
          'getRunningApplications',
          {'includeSystemApps': includeSystemApps},
        ) as List<dynamic>?;
        return result?.map((app) {
              // Safely convert each app data to Map<String, dynamic>
              final appMap = safeMapConversion(app);
              if (appMap != null) {
                return AppInfo.fromJson(appMap);
              } else {
                throw PlatformChannelException(
                  'Invalid app data format: expected Map, got ${app.runtimeType}',
                  channelName: 'getRunningApplications',
                  platformDetails: {'dataType': app.runtimeType.toString()},
                );
              }
            }).toList() ??
            [];
      } on PlatformException catch (e) {
        throw PlatformChannelException(
          'Failed to get running applications: ${e.message}',
          channelName: 'getRunningApplications',
          platformDetails: {'code': e.code, 'details': e.details},
          cause: e,
        );
      }
    });
  }

  @override
  Future<bool> updateConfiguration(FocusTrackerConfig config) async {
    _validateConfiguration(config);

    return _withRetry('updateConfiguration', () async {
      try {
        final result = await methodChannel.invokeMethod<bool>('updateConfiguration', {
          ...config.toJson(),
          'sessionId': _currentSessionId,
        });
        if (result == true) {
          _currentConfig = config;
          // Update stream manager configuration
          await _streamManager?.stop();
          _streamManager = _createStreamManager(config);
          await _streamManager?.start();
          _setupEventStream();
        }
        return result ?? false;
      } on PlatformException catch (e) {
        throw PlatformChannelException(
          'Failed to update configuration: ${e.message}',
          channelName: 'updateConfiguration',
          platformDetails: {'code': e.code, 'details': e.details},
          cause: e,
        );
      }
    });
  }

  @override
  Future<Map<String, dynamic>> getDiagnosticInfo() async {
    return _withRetry('getDiagnosticInfo', () async {
      try {
        final result = await methodChannel.invokeMethod('getDiagnosticInfo');
        final diagnosticMap = safeMapConversion(result) ?? <String, dynamic>{};
        return {
          ...diagnosticMap,
          'dartSide': {
            'isTracking': _isTracking,
            'currentConfig': _currentConfig?.toJson(),
            'sessionId': _currentSessionId,
            'sessionStartTime': _sessionStartTime?.toIso8601String(),
            'degradedMode': _degradedMode,
            'retryCount': _retryCount,
            'errorCount': _errorCount,
            'errorCounts': Map.from(_errorCounts),
            'lastSuccessfulOperation': _lastSuccessfulOperation?.toIso8601String(),
          },
          'streamManager': _streamManager?.getDiagnosticInfo(),
        };
      } on PlatformException catch (e) {
        throw PlatformChannelException(
          'Failed to get diagnostic info: ${e.message}',
          channelName: 'getDiagnosticInfo',
          platformDetails: {'code': e.code, 'details': e.details},
          cause: e,
        );
      }
    });
  }

  /// Sets up the event stream to listen for focus events from the platform.
  void _setupEventStream() {
    _eventSubscription?.cancel();
    _eventSubscription = eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        try {
          // Safely convert the event data to Map<String, dynamic>
          final eventMap = safeMapConversion(event);
          if (eventMap == null) {
            _handleError('eventChannel', 'Invalid event data format: expected Map, got ${event.runtimeType}');
            return;
          }

          // Add session ID if not present
          if (!eventMap.containsKey('sessionId')) {
            eventMap['sessionId'] = _currentSessionId;
          }

          // Convert to microsecond precision if needed
          if (eventMap.containsKey('timestamp') && eventMap['timestamp'] is int) {
            final timestamp = eventMap['timestamp'] as int;
            // If timestamp is in milliseconds, convert to microseconds
            if (timestamp < 1000000000000000) {
              eventMap['timestamp'] = timestamp * 1000;
            }
          }

          final focusEvent = FocusEvent.fromJson(eventMap);
          _streamManager?.addEvent(focusEvent);

          // Update success indicators
          _lastSuccessfulOperation = DateTime.now();
          _retryCount = 0;

          // Exit degraded mode if we're receiving events
          if (_degradedMode) {
            _degradedMode = false;
            _scheduleRecovery();
          }
        } catch (e) {
          _handleError('eventChannel', e);
        }
      },
      onError: (dynamic error) {
        _handleError('eventChannel', error);
      },
    );
  }

  /// Closes the event stream and cleans up resources.
  Future<void> _closeEventStream() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _streamManager?.stop();
    await _streamManager?.dispose();
    _streamManager = null;
  }

  /// Handles errors with retry logic and graceful degradation.
  void _handleError(String operation, dynamic error) {
    _errorCount++;
    _errorCounts[operation] = (_errorCounts[operation] ?? 0) + 1;

    // Log error (in production, use proper logging)
    if (kDebugMode) {
      print('Error in $operation: $error');
    }

    // Add error to stream
    _streamManager?.addEvent(FocusEvent(
      appName: 'System Error',
      durationMicroseconds: 0,
      eventType: FocusEventType.lost,
      metadata: {
        'error': error.toString(),
        'operation': operation,
        'timestamp': DateTime.now().toIso8601String(),
      },
    ));

    // Check if we should enter degraded mode
    if (_errorCount > 5 && !_degradedMode) {
      _enterDegradedMode();
    }

    // Schedule recovery attempt
    _scheduleRecovery();
  }

  /// Enters degraded mode with reduced functionality.
  void _enterDegradedMode() {
    _degradedMode = true;

    // Reduce update frequency
    if (_currentConfig != null) {
      final degradedConfig = _currentConfig!.copyWith(
        updateIntervalMs: math.max(_currentConfig!.updateIntervalMs * 2, 5000),
        enableBatching: true,
        maxBatchSize: math.max(_currentConfig!.maxBatchSize * 2, 20),
      );

      // Apply degraded configuration
      updateConfiguration(degradedConfig).catchError((error) {
        // If we can't update configuration, continue with current settings
        if (kDebugMode) {
          print('Failed to apply degraded configuration: $error');
        }
      });
    }
  }

  /// Schedules a recovery attempt.
  void _scheduleRecovery() {
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(const Duration(seconds: 30), () {
      _attemptRecovery();
    });
  }

  /// Attempts to recover from errors.
  void _attemptRecovery() {
    if (!_isTracking || _streamManager == null) return;

    // Flush any pending events
    _streamManager!.flush();

    // Reset error counts if we've been stable for a while
    if (_lastSuccessfulOperation != null) {
      final timeSinceSuccess = DateTime.now().difference(_lastSuccessfulOperation!);
      if (timeSinceSuccess.inMinutes > 5) {
        _errorCount = 0;
        _errorCounts.clear();
      }
    }

    // Try to restart event stream if it's been problematic
    if (_errorCounts['eventChannel'] != null && _errorCounts['eventChannel']! > 3) {
      _setupEventStream();
    }
  }

  /// Starts recovery monitoring.
  void _startRecoveryMonitoring() {
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!_isTracking) {
        timer.cancel();
        return;
      }

      // Check if we need recovery
      if (_lastSuccessfulOperation != null) {
        final timeSinceSuccess = DateTime.now().difference(_lastSuccessfulOperation!);
        if (timeSinceSuccess.inMinutes > 2) {
          _attemptRecovery();
        }
      }
    });
  }

  /// Stops recovery monitoring.
  void _stopRecoveryMonitoring() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
  }

  /// Executes an operation with retry logic.
  Future<T> _withRetry<T>(String operation, Future<T> Function() fn) async {
    int attempts = 0;

    while (attempts < _maxRetries) {
      try {
        final result = await fn();
        _lastSuccessfulOperation = DateTime.now();
        return result;
      } catch (e) {
        attempts++;
        _handleError(operation, e);

        if (attempts >= _maxRetries) {
          rethrow;
        }

        // Wait before retry with exponential backoff
        await Future.delayed(Duration(milliseconds: _retryDelay.inMilliseconds * attempts));
      }
    }

    throw StateError('Maximum retries exceeded for operation: $operation');
  }

  /// Creates an appropriate stream manager based on configuration.
  FocusStreamManager _createStreamManager(FocusTrackerConfig config) {
    if (config.enableBatching && config.maxBatchSize > 15) {
      return HighPerformanceStreamManager(config);
    }
    return FocusStreamManager(config);
  }

  /// Validates the configuration and throws [ConfigurationException] if invalid.
  void _validateConfiguration(FocusTrackerConfig config) {
    if (config.updateIntervalMs <= 0) {
      throw ConfigurationException(
        'Update interval must be positive',
        parameterName: 'updateIntervalMs',
        invalidValue: config.updateIntervalMs,
        expectedValue: 'positive integer',
      );
    }

    if (config.updateIntervalMs < 100) {
      throw ConfigurationException(
        'Update interval too low, may cause performance issues',
        parameterName: 'updateIntervalMs',
        invalidValue: config.updateIntervalMs,
        expectedValue: '>=100ms',
      );
    }

    if (config.maxBatchSize <= 0) {
      throw ConfigurationException(
        'Batch size must be positive',
        parameterName: 'maxBatchSize',
        invalidValue: config.maxBatchSize,
        expectedValue: 'positive integer',
      );
    }

    if (config.maxBatchWaitMs <= 0) {
      throw ConfigurationException(
        'Batch wait time must be positive',
        parameterName: 'maxBatchWaitMs',
        invalidValue: config.maxBatchWaitMs,
        expectedValue: 'positive integer',
      );
    }
  }

  /// Generates a unique session ID.
  String _generateSessionId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = math.Random().nextInt(999999);
    return 'session_${timestamp}_$random';
  }

  /// Infers the platform name from the current platform.
  String _inferPlatformName() {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Unknown';
  }

  /// Infers platform support based on the current platform.
  bool _inferPlatformSupport() {
    return Platform.isMacOS || Platform.isWindows;
  }
}
