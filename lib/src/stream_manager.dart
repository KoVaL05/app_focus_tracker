import 'dart:async';
import 'dart:collection';

import 'models/focus_event.dart';
import 'models/focus_tracker_config.dart';
import 'event_buffer.dart';
import 'exceptions/app_focus_tracker_exception.dart';

/// A sophisticated stream manager that handles focus events with memory efficiency,
/// proper lifecycle management, and performance monitoring.
class FocusStreamManager {
  final FocusEventBuffer _eventBuffer;

  StreamController<FocusEvent>? _primaryController;
  StreamController<List<FocusEvent>>? _batchController;
  StreamSubscription<List<FocusEvent>>? _batchSubscription;

  final Set<StreamSubscription> _activeSubscriptions = {};
  final Map<String, StreamController<FocusEvent>> _appSpecificControllers = {};
  final Queue<FocusEvent> _recentEvents = Queue<FocusEvent>();

  bool _isActive = false;
  bool _isDisposed = false;
  Timer? _healthCheckTimer;
  Timer? _cleanupTimer;

  // Performance monitoring
  int _totalEventsProcessed = 0;
  int _activeSubscriptionCount = 0;
  DateTime? _lastEventTime;
  final Map<String, int> _subscriptionCounts = {};

  /// Creates a new [FocusStreamManager] with the given configuration.
  FocusStreamManager(FocusTrackerConfig config) : _eventBuffer = _createEventBuffer(config);

  /// Gets the primary stream of focus events.
  Stream<FocusEvent> get eventStream {
    _ensureInitialized();
    return _primaryController!.stream;
  }

  /// Gets a stream of batched focus events.
  Stream<List<FocusEvent>> get batchStream {
    _ensureInitialized();
    return _batchController!.stream;
  }

  /// Gets a stream of events filtered by application name.
  Stream<FocusEvent> getAppStream(String appName) {
    _ensureInitialized();

    final controller = _appSpecificControllers.putIfAbsent(
      appName,
      () => StreamController<FocusEvent>.broadcast(
        onListen: () => _subscriptionCounts[appName] = (_subscriptionCounts[appName] ?? 0) + 1,
        onCancel: () {
          _subscriptionCounts[appName] = (_subscriptionCounts[appName] ?? 1) - 1;
          if (_subscriptionCounts[appName]! <= 0) {
            _cleanupAppController(appName);
          }
        },
      ),
    );

    return controller.stream;
  }

  /// Starts the stream manager.
  Future<void> start() async {
    if (_isActive || _isDisposed) return;

    _ensureInitialized();
    _isActive = true;

    // Start health monitoring
    _startHealthMonitoring();

    // Start cleanup routine
    _startCleanupRoutine();
  }

  /// Stops the stream manager.
  Future<void> stop() async {
    if (!_isActive || _isDisposed) return;

    _isActive = false;

    // Stop timers
    _healthCheckTimer?.cancel();
    _cleanupTimer?.cancel();

    // Flush any remaining events
    _eventBuffer.flush();

    // Close all app-specific controllers
    for (final controller in _appSpecificControllers.values) {
      await controller.close();
    }
    _appSpecificControllers.clear();

    // Cancel subscriptions
    for (final subscription in _activeSubscriptions) {
      await subscription.cancel();
    }
    _activeSubscriptions.clear();

    _batchSubscription?.cancel();
    _batchSubscription = null;
  }

  /// Adds a new event to the stream.
  void addEvent(FocusEvent event) {
    if (_isDisposed || !_isActive) return;

    _totalEventsProcessed++;
    _lastEventTime = DateTime.now();

    // Add to recent events for health monitoring
    _recentEvents.add(event);
    if (_recentEvents.length > 100) {
      _recentEvents.removeFirst();
    }

    // Send to event buffer for processing
    _eventBuffer.addEvent(event);
  }

  /// Forces a flush of all buffered events.
  void flush() {
    if (_isDisposed) return;
    _eventBuffer.flush();
  }

  /// Gets performance metrics for the stream manager.
  Map<String, dynamic> getMetrics() {
    return {
      'streamManager': {
        'isActive': _isActive,
        'isDisposed': _isDisposed,
        'totalEventsProcessed': _totalEventsProcessed,
        'activeSubscriptionCount': _activeSubscriptionCount,
        'lastEventTime': _lastEventTime?.toIso8601String(),
        'recentEventsCount': _recentEvents.length,
        'appSpecificStreams': _appSpecificControllers.length,
        'subscriptionCounts': Map.from(_subscriptionCounts),
      },
      'eventBuffer': _eventBuffer.getMetrics(),
    };
  }

  /// Gets diagnostic information about stream health.
  Map<String, dynamic> getDiagnosticInfo() {
    final now = DateTime.now();
    final metrics = getMetrics();

    // Calculate event rates
    double eventsPerSecond = 0.0;
    if (_recentEvents.isNotEmpty) {
      final timeSpan = now.difference(_recentEvents.first.timestamp);
      if (timeSpan.inSeconds > 0) {
        eventsPerSecond = _recentEvents.length / timeSpan.inSeconds;
      }
    }

    // Check for potential issues
    final issues = <String>[];
    if (_activeSubscriptionCount > 20) {
      issues.add('High subscription count may impact performance');
    }
    if (eventsPerSecond > 100) {
      issues.add('High event rate detected');
    }
    if (_lastEventTime != null && now.difference(_lastEventTime!).inMinutes > 5) {
      issues.add('No recent events - stream may be stalled');
    }

    return {
      ...metrics,
      'health': {
        'eventsPerSecond': eventsPerSecond,
        'issues': issues,
        'lastHealthCheck': now.toIso8601String(),
      },
    };
  }

  /// Disposes the stream manager and cleans up all resources.
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;

    // Stop if still active
    if (_isActive) {
      await stop();
    }

    // Dispose event buffer
    _eventBuffer.dispose();

    // Close controllers
    await _primaryController?.close();
    await _batchController?.close();

    _primaryController = null;
    _batchController = null;
  }

  /// Ensures the stream manager is properly initialized.
  void _ensureInitialized() {
    if (_isDisposed) {
      throw StateError('StreamManager has been disposed');
    }

    _primaryController ??= StreamController<FocusEvent>.broadcast(
      onListen: () => _activeSubscriptionCount++,
      onCancel: () => _activeSubscriptionCount--,
    );

    if (_batchController == null) {
      _batchController = StreamController<List<FocusEvent>>.broadcast();

      // Subscribe to batch events from the buffer
      _batchSubscription = _eventBuffer.batchStream.listen(
        _processBatch,
        onError: (error) => _handleStreamError(error),
      );
      _activeSubscriptions.add(_batchSubscription!);
    }
  }

  /// Processes a batch of events from the event buffer.
  void _processBatch(List<FocusEvent> batch) {
    if (_isDisposed || !_isActive) return;

    // Send batch to batch stream
    _batchController?.add(batch);

    // Send individual events to primary stream and app-specific streams
    for (final event in batch) {
      // Send to primary stream
      _primaryController?.add(event);

      // Send to app-specific stream if it exists
      final appController = _appSpecificControllers[event.appName];
      if (appController != null) {
        appController.add(event);
      }
    }
  }

  /// Handles stream errors with appropriate recovery strategies.
  void _handleStreamError(dynamic error) {
    if (_isDisposed) return;

    // Log error (in a real implementation, you'd use a proper logger)
    print('Stream error: $error');

    // Add error to streams
    _primaryController?.addError(error);
    _batchController?.addError(error);

    // Notify app-specific streams
    for (final controller in _appSpecificControllers.values) {
      controller.addError(error);
    }

    // Implement retry logic if needed
    if (error is PlatformChannelException) {
      _scheduleRetry();
    }
  }

  /// Schedules a retry after a stream error.
  void _scheduleRetry() {
    // Simple retry logic - in a real implementation, you'd want exponential backoff
    Timer(const Duration(seconds: 5), () {
      if (_isActive && !_isDisposed) {
        // Attempt to recover by flushing the buffer
        _eventBuffer.flush();
      }
    });
  }

  /// Starts health monitoring to detect and resolve issues.
  void _startHealthMonitoring() {
    _healthCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }

      _performHealthCheck();
    });
  }

  /// Performs a health check on the stream manager.
  void _performHealthCheck() {
    final now = DateTime.now();

    // Check for stalled streams
    if (_lastEventTime != null && now.difference(_lastEventTime!).inMinutes > 10) {
      // Stream might be stalled, attempt to recover
      _eventBuffer.flush();
    }

    // Check memory usage
    if (_recentEvents.length > 1000) {
      // Clear old events to prevent memory issues
      while (_recentEvents.length > 500) {
        _recentEvents.removeFirst();
      }
    }
  }

  /// Starts the cleanup routine for unused resources.
  void _startCleanupRoutine() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }

      _performCleanup();
    });
  }

  /// Performs cleanup of unused resources.
  void _performCleanup() {
    // Clean up app-specific controllers with no listeners
    final toRemove = <String>[];
    for (final entry in _appSpecificControllers.entries) {
      if ((_subscriptionCounts[entry.key] ?? 0) <= 0 && !entry.value.hasListener) {
        toRemove.add(entry.key);
      }
    }

    for (final appName in toRemove) {
      _cleanupAppController(appName);
    }
  }

  /// Cleans up an app-specific controller.
  void _cleanupAppController(String appName) {
    final controller = _appSpecificControllers.remove(appName);
    controller?.close();
    _subscriptionCounts.remove(appName);
  }

  /// Creates an appropriate event buffer based on configuration.
  static FocusEventBuffer _createEventBuffer(FocusTrackerConfig config) {
    // Use intelligent buffer if performance mode is enabled
    if (config.enableBatching && config.maxBatchSize > 10) {
      return IntelligentEventBuffer(config);
    }

    return FocusEventBuffer(config);
  }
}

/// A specialized stream manager for high-performance scenarios.
class HighPerformanceStreamManager extends FocusStreamManager {
  final Map<String, Timer> _debounceTimers = {};
  final int _maxConcurrentStreams = 10;

  HighPerformanceStreamManager(super.config);

  @override
  Stream<FocusEvent> getAppStream(String appName) {
    // Limit concurrent streams to prevent resource exhaustion
    if (_appSpecificControllers.length >= _maxConcurrentStreams) {
      throw StateError('Maximum concurrent streams reached');
    }

    return super.getAppStream(appName);
  }

  @override
  void addEvent(FocusEvent event) {
    // Implement debouncing for rapid events
    final existingTimer = _debounceTimers[event.appName];
    if (existingTimer != null) {
      existingTimer.cancel();
    }

    _debounceTimers[event.appName] = Timer(const Duration(milliseconds: 50), () {
      super.addEvent(event);
      _debounceTimers.remove(event.appName);
    });
  }

  @override
  Future<void> dispose() async {
    // Cancel debounce timers
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();

    await super.dispose();
  }
}
