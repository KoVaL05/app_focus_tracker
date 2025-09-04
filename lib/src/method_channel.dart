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

  // Title-change segmentation state (Dart-side synthetic segmentation for non-browser apps)
  String? _lastAppKey;
  String? _lastWindowTitle;
  int _titleSegmentOffsetMicros = 0;
  bool _suppressNextEvent = false;
  String? _lastBrowserTabKey;
  Map<String, dynamic>? _lastBrowserTabMap;
  int? _pendingBrowserLostDurationMicros;
  FocusEvent? _pendingBrowserLostEvent;

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

    return _withRetry('startTracking', () async {
      try {
        await methodChannel.invokeMethod('startTracking', {
          'config': config.toJson(),
        });
        _currentConfig = config;
        _isTracking = true;
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
      } on MissingPluginException {
        // Native side does not implement this optional method. Fall back to
        // Dart-side only update so that callers do not crash on older plugin
        // versions.
        _currentConfig = config;
        await _streamManager?.stop();
        _streamManager = _createStreamManager(config);
        await _streamManager?.start();
        _setupEventStream();
        return true;
      } on PlatformException catch (e) {
        if (e.code == 'unimplemented') {
          // Graceful degradation if the native layer hasn't yet implemented
          // this optional method.
          _currentConfig = config;
          await _streamManager?.stop();
          _streamManager = _createStreamManager(config);
          await _streamManager?.start();
          _setupEventStream();
          return true;
        }
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
        final diagnostics = safeMapConversion(result);
        if (diagnostics == null) {
          throw const PlatformChannelException(
            'Invalid diagnostic data format',
            channelName: 'getDiagnosticInfo',
          );
        }
        return diagnostics;
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

  /// Debug method to test URL extraction on the currently focused browser.
  ///
  /// This method provides detailed information about URL extraction attempts
  /// and can help identify why URLs might be showing as "unknown".
  ///
  /// Returns a map containing:
  /// - Platform-specific extraction results (AppleScript, UIAutomation, etc.)
  /// - Window title information
  /// - Browser detection results
  /// - Extracted domain/URL information
  /// - Any error messages from the extraction process
  ///
  /// This method is intended for debugging purposes only.
  Future<Map<String, dynamic>> debugUrlExtraction() async {
    return _withRetry('debugUrlExtraction', () async {
      try {
        final result = await methodChannel.invokeMethod('debugUrlExtraction');
        final debugInfo = safeMapConversion(result);
        if (debugInfo == null) {
          throw const PlatformChannelException(
            'Invalid debug data format',
            channelName: 'debugUrlExtraction',
          );
        }
        return debugInfo;
      } on PlatformException catch (e) {
        throw PlatformChannelException(
          'Failed to debug URL extraction: ${e.message}',
          channelName: 'debugUrlExtraction',
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

          // Build the base event first for easier property access
          final incomingEvent = FocusEvent.fromJson(eventMap);

          // Initialize/reset segmentation state when stream begins or app switches
          final currentAppKey = _buildAppKey(incomingEvent);

          // Helper: extract window title if available
          final currentWindowTitle = _extractWindowTitle(incomingEvent);

          // If app changed, reset segmentation state and forward event as-is
          if (_lastAppKey == null || currentAppKey != _lastAppKey) {
            // If we had a pending browser lost (we were waiting to see if it was a tab switch),
            // flush it now because this is a true app switch.
            if (_pendingBrowserLostEvent != null) {
              _streamManager?.addEvent(_pendingBrowserLostEvent!);
              _pendingBrowserLostEvent = null;
              _pendingBrowserLostDurationMicros = null;
            }
            _lastAppKey = currentAppKey;
            _titleSegmentOffsetMicros = 0;
            _lastWindowTitle = currentWindowTitle;
            _suppressNextEvent = false;
            // Initialize browser tab state if available
            _lastBrowserTabMap = _extractBrowserTab(incomingEvent);
            _lastBrowserTabKey = _buildBrowserTabKey(incomingEvent);
            _streamManager?.addEvent(incomingEvent);
          } else {
            // Same app: handle title-change segmentation for NON-browser apps only
            final includeMetadata = _currentConfig?.includeMetadata == true;
            final isNonBrowser = !incomingEvent.isBrowser;

            // Normalize browser tab change pair into a single tabChange event
            if (includeMetadata && !isNonBrowser) {
              final currentTabMap = _extractBrowserTab(incomingEvent);
              final currentTabKey = _buildBrowserTabKey(incomingEvent);

              if (incomingEvent.eventType == FocusEventType.lost) {
                // Record the lost event and duration to decide after we see the next gained
                _pendingBrowserLostDurationMicros = incomingEvent.durationMicroseconds;
                _pendingBrowserLostEvent = incomingEvent;
                return;
              }

              if (incomingEvent.eventType == FocusEventType.gained) {
                // Compare previous vs current and emit a single tabChange
                final prevKey = _lastBrowserTabKey;
                final prevMap = _lastBrowserTabMap;
                final lossDuration = _pendingBrowserLostDurationMicros ?? 0;

                if (prevKey != null && currentTabKey != null && prevKey != currentTabKey) {
                  final tabChangeEvent = FocusEvent(
                    appName: incomingEvent.appName,
                    appIdentifier: incomingEvent.appIdentifier,
                    timestamp: incomingEvent.timestamp,
                    durationMicroseconds: lossDuration,
                    processId: incomingEvent.processId,
                    eventType: FocusEventType.tabChange,
                    sessionId: incomingEvent.sessionId,
                    metadata: _augmentMetadataWithTabChange(incomingEvent.metadata, prevMap, currentTabMap),
                    input: incomingEvent.input,
                  );
                  _streamManager?.addEvent(tabChangeEvent);
                  // Update last tab to current
                  _lastBrowserTabKey = currentTabKey;
                  _lastBrowserTabMap = currentTabMap;
                  _pendingBrowserLostDurationMicros = null;
                  _pendingBrowserLostEvent = null;
                  return; // swallow gained
                }

                // No change detected; forward gained
                _streamManager?.addEvent(incomingEvent);
                if (currentTabKey != null) {
                  _lastBrowserTabKey = currentTabKey;
                  _lastBrowserTabMap = currentTabMap;
                }
                _pendingBrowserLostDurationMicros = null;
                _pendingBrowserLostEvent = null;
                return;
              }

              // For duration updates or other events, forward and update last tab state
              // If we had a pending browser lost but the next event wasn't the gained pair,
              // flush the pending lost now.
              if (_pendingBrowserLostEvent != null) {
                _streamManager?.addEvent(_pendingBrowserLostEvent!);
                _pendingBrowserLostEvent = null;
                _pendingBrowserLostDurationMicros = null;
              }
              _streamManager?.addEvent(incomingEvent);
              if (currentTabKey != null) {
                _lastBrowserTabKey = currentTabKey;
                _lastBrowserTabMap = currentTabMap;
              }
              return;
            }

            if (includeMetadata && isNonBrowser && incomingEvent.eventType == FocusEventType.durationUpdate) {
              final prevTitle = _lastWindowTitle;
              final nextTitle = currentWindowTitle;

              final titleChanged = (prevTitle != null && nextTitle != null && prevTitle != nextTitle);

              if (titleChanged) {
                // Emit a single tabChange event representing the title switch
                final elapsedSinceFocusStart = incomingEvent.durationMicroseconds;
                final segmentElapsed = math.max(0, elapsedSinceFocusStart - _titleSegmentOffsetMicros);
                final tabChangeEvent = FocusEvent(
                  appName: incomingEvent.appName,
                  appIdentifier: incomingEvent.appIdentifier,
                  timestamp: incomingEvent.timestamp,
                  durationMicroseconds: segmentElapsed,
                  processId: incomingEvent.processId,
                  eventType: FocusEventType.tabChange,
                  sessionId: incomingEvent.sessionId,
                  metadata: _augmentMetadataWithTitleChange(incomingEvent.metadata, prevTitle, nextTitle),
                  input: incomingEvent.input,
                );
                _streamManager?.addEvent(tabChangeEvent);

                // Update segmentation baseline to the current elapsed time and title
                _titleSegmentOffsetMicros = elapsedSinceFocusStart;
                _lastWindowTitle = nextTitle;
                return; // handled
              }

              // If in a segmented window (offset set), adjust durations to start from split
              if (_titleSegmentOffsetMicros > 0) {
                final adjustedDuration = math.max(0, incomingEvent.durationMicroseconds - _titleSegmentOffsetMicros);
                final adjustedEvent = FocusEvent(
                  appName: incomingEvent.appName,
                  appIdentifier: incomingEvent.appIdentifier,
                  timestamp: incomingEvent.timestamp,
                  durationMicroseconds: adjustedDuration,
                  processId: incomingEvent.processId,
                  eventType: incomingEvent.eventType,
                  sessionId: incomingEvent.sessionId,
                  metadata: incomingEvent.metadata,
                  input: incomingEvent.input,
                );
                _streamManager?.addEvent(adjustedEvent);
              } else {
                _streamManager?.addEvent(incomingEvent);
              }
            } else if (includeMetadata &&
                isNonBrowser &&
                incomingEvent.eventType == FocusEventType.lost &&
                _titleSegmentOffsetMicros > 0) {
              // Adjust the final lost duration to be relative to the last split
              final adjustedDuration = math.max(0, incomingEvent.durationMicroseconds - _titleSegmentOffsetMicros);
              final adjustedLost = FocusEvent(
                appName: incomingEvent.appName,
                appIdentifier: incomingEvent.appIdentifier,
                timestamp: incomingEvent.timestamp,
                durationMicroseconds: adjustedDuration,
                processId: incomingEvent.processId,
                eventType: FocusEventType.lost,
                sessionId: incomingEvent.sessionId,
                metadata: incomingEvent.metadata,
                input: incomingEvent.input,
              );
              _streamManager?.addEvent(adjustedLost);
              // Reset segmentation after app loses focus
              _titleSegmentOffsetMicros = 0;
              _lastWindowTitle = null;
            } else {
              // No special handling required
              if (_suppressNextEvent) {
                // Consume one event after a split to avoid duplicates in corner cases
                _suppressNextEvent = false;
                return;
              }
              _streamManager?.addEvent(incomingEvent);
              // Keep the latest title for future comparisons
              _lastWindowTitle = currentWindowTitle ?? _lastWindowTitle;
            }
          }

          // Update success indicators
          _lastSuccessfulOperation = DateTime.now();

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
    // Reset segmentation state
    _lastAppKey = null;
    _lastWindowTitle = null;
    _titleSegmentOffsetMicros = 0;
    _suppressNextEvent = false;
    _lastBrowserTabKey = null;
    _lastBrowserTabMap = null;
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
        return false; // recover with no-op result to satisfy Future<bool>
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

  String _buildAppKey(FocusEvent event) {
    final id = event.appIdentifier ?? event.appName;
    final pid = event.processId ?? -1;
    return '$id:$pid';
  }

  String? _extractWindowTitle(FocusEvent event) {
    final meta = event.metadata;
    if (meta == null) return null;
    final title = meta['windowTitle'];
    if (title is String && title.isNotEmpty) return title;
    // As a fallback, some platforms might provide a direct 'title'
    final fallback = meta['title'];
    if (fallback is String && fallback.isNotEmpty) return fallback;
    return null;
  }

  Map<String, dynamic>? _extractBrowserTab(FocusEvent event) {
    final meta = event.metadata;
    if (meta == null) return null;
    final tab = meta['browserTab'];
    if (tab is Map<String, dynamic>) return tab;
    return null;
  }

  String? _buildBrowserTabKey(FocusEvent event) {
    final tab = _extractBrowserTab(event);
    if (tab == null) return null;
    final title = tab['title'];
    final url = tab['url'];
    final domain = tab['domain'];
    return '${title ?? ''}|${url ?? ''}|${domain ?? ''}';
  }

  Map<String, dynamic> _augmentMetadataWithTitleChange(
    Map<String, dynamic>? original,
    String? fromTitle,
    String? toTitle,
  ) {
    final updated = <String, dynamic>{};
    if (original != null) {
      updated.addAll(original);
    }
    updated['changeType'] = 'title';
    updated['titleChange'] = {
      'from': fromTitle,
      'to': toTitle,
    };
    updated.removeWhere((key, value) => value == null);
    return updated;
  }

  Map<String, dynamic> _augmentMetadataWithTabChange(
    Map<String, dynamic>? original,
    Map<String, dynamic>? previousTab,
    Map<String, dynamic>? currentTab,
  ) {
    final updated = <String, dynamic>{};
    if (original != null) {
      updated.addAll(original);
    }
    updated['changeType'] = 'tab';
    if (previousTab != null) {
      updated['previousTab'] = previousTab;
    }
    if (currentTab != null) {
      updated['currentTab'] = currentTab;
    }
    updated.removeWhere((key, value) => value == null);
    return updated;
  }
}
