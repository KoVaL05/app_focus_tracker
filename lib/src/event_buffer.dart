import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'models/focus_event.dart';
import 'models/focus_tracker_config.dart';

/// An intelligent event buffer that batches and optimizes focus events
/// for better performance and reduced resource usage.
class FocusEventBuffer {
  final FocusTrackerConfig _config;
  final StreamController<List<FocusEvent>> _batchController;
  final Queue<FocusEvent> _eventQueue = Queue<FocusEvent>();
  final Map<String, FocusEvent> _latestEventsByApp = {};
  final Map<String, int> _eventCounts = {};

  Timer? _batchTimer;
  bool _isDisposed = false;

  // Performance metrics
  int _totalEventsReceived = 0;
  int _totalEventsSent = 0;
  int _batchesSent = 0;
  int _duplicatesFiltered = 0;
  DateTime? _lastFlushTime;

  /// Creates a new [FocusEventBuffer] with the given configuration.
  FocusEventBuffer(this._config) : _batchController = StreamController<List<FocusEvent>>.broadcast();

  /// Gets the stream of batched events.
  Stream<List<FocusEvent>> get batchStream => _batchController.stream;

  /// Adds a new event to the buffer.
  void addEvent(FocusEvent event) {
    if (_isDisposed) return;

    _totalEventsReceived++;

    // Apply intelligent filtering
    if (_shouldFilterEvent(event)) {
      _duplicatesFiltered++;
      return;
    }

    // Add to queue and update latest events tracking
    _eventQueue.add(event);
    _latestEventsByApp[event.appName] = event;
    _eventCounts[event.appName] = (_eventCounts[event.appName] ?? 0) + 1;

    // Check if we should flush immediately
    if (_shouldFlushImmediately(event)) {
      _flushEvents();
    } else if (_config.enableBatching) {
      _scheduleBatchFlush();
    } else {
      // Send individual events immediately if batching is disabled
      _sendBatch([event]);
    }
  }

  /// Forces an immediate flush of all buffered events.
  void flush() {
    if (_isDisposed) return;
    _flushEvents();
  }

  /// Clears all buffered events without sending them.
  void clear() {
    if (_isDisposed) return;

    _eventQueue.clear();
    _latestEventsByApp.clear();
    _eventCounts.clear();
    _cancelTimers();
  }

  /// Gets performance metrics for the buffer.
  Map<String, dynamic> getMetrics() {
    return {
      'totalEventsReceived': _totalEventsReceived,
      'totalEventsSent': _totalEventsSent,
      'batchesSent': _batchesSent,
      'duplicatesFiltered': _duplicatesFiltered,
      'currentQueueSize': _eventQueue.length,
      'trackedApps': _latestEventsByApp.length,
      'lastFlushTime': _lastFlushTime?.toIso8601String(),
      'eventsPerApp': Map.from(_eventCounts),
      'compressionRatio': _totalEventsReceived > 0 ? _totalEventsSent / _totalEventsReceived : 0.0,
    };
  }

  /// Disposes the buffer and cleans up resources.
  void dispose() {
    if (_isDisposed) return;

    _isDisposed = true;
    _cancelTimers();

    // Flush any remaining events
    if (_eventQueue.isNotEmpty) {
      _flushEvents();
    }

    _batchController.close();
  }

  /// Determines if an event should be filtered out to reduce noise.
  bool _shouldFilterEvent(FocusEvent event) {
    // Don't filter significant events
    if (event.isSignificantEvent) return false;

    // Filter out rapid duplicate events for the same app
    final lastEvent = _latestEventsByApp[event.appName];
    if (lastEvent != null) {
      final timeDiff = event.timestamp.difference(lastEvent.timestamp);

      // Filter out events that are too close together (less than 100ms)
      if (timeDiff.inMicroseconds < 100000) {
        return true;
      }

      // Filter out duration updates that haven't changed significantly
      if (event.eventType == FocusEventType.durationUpdate && lastEvent.eventType == FocusEventType.durationUpdate) {
        final durationDiff = (event.durationMicroseconds - lastEvent.durationMicroseconds).abs();
        if (durationDiff < 500000) {
          // Less than 0.5 seconds difference
          return true;
        }
      }
    }

    return false;
  }

  /// Determines if events should be flushed immediately.
  bool _shouldFlushImmediately(FocusEvent event) {
    // Always flush significant events immediately
    if (event.isSignificantEvent) return true;

    // Flush if queue is full
    if (_eventQueue.length >= _config.maxBatchSize) return true;

    // Flush if we haven't sent anything recently and have events
    if (_lastFlushTime != null) {
      final timeSinceLastFlush = DateTime.now().difference(_lastFlushTime!);
      if (timeSinceLastFlush.inMilliseconds > _config.maxBatchWaitMs) {
        return true;
      }
    }

    return false;
  }

  /// Schedules a batch flush if one isn't already scheduled.
  void _scheduleBatchFlush() {
    if (_batchTimer?.isActive == true) return;

    _batchTimer = Timer(Duration(milliseconds: _config.maxBatchWaitMs), () {
      _flushEvents();
    });
  }

  /// Flushes all buffered events.
  void _flushEvents() {
    if (_isDisposed || _eventQueue.isEmpty) return;

    _cancelTimers();

    // Create optimized batch
    final batch = _createOptimizedBatch();
    if (batch.isNotEmpty) {
      _sendBatch(batch);
    }
  }

  /// Creates an optimized batch of events by deduplicating and merging where possible.
  List<FocusEvent> _createOptimizedBatch() {
    if (_eventQueue.isEmpty) return [];

    final events = List<FocusEvent>.from(_eventQueue);
    _eventQueue.clear();

    // Group events by app
    final eventsByApp = <String, List<FocusEvent>>{};
    for (final event in events) {
      eventsByApp.putIfAbsent(event.appName, () => []).add(event);
    }

    // Optimize each app's events
    final optimizedEvents = <FocusEvent>[];
    for (final appEvents in eventsByApp.values) {
      optimizedEvents.addAll(_optimizeAppEvents(appEvents));
    }

    // Sort by timestamp
    optimizedEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return optimizedEvents;
  }

  /// Optimizes events for a single application.
  List<FocusEvent> _optimizeAppEvents(List<FocusEvent> events) {
    if (events.isEmpty) return [];
    if (events.length == 1) return events;

    // Sort by timestamp
    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final optimized = <FocusEvent>[];
    FocusEvent? lastEvent;

    for (final event in events) {
      if (lastEvent == null) {
        optimized.add(event);
        lastEvent = event;
        continue;
      }

      // Merge consecutive duration updates
      if (event.eventType == FocusEventType.durationUpdate && lastEvent.eventType == FocusEventType.durationUpdate) {
        // Replace the last event with the current one (keeping the latest duration)
        optimized.removeLast();
        optimized.add(event);
        lastEvent = event;
      } else {
        optimized.add(event);
        lastEvent = event;
      }
    }

    return optimized;
  }

  /// Sends a batch of events to the stream.
  void _sendBatch(List<FocusEvent> batch) {
    if (_isDisposed || batch.isEmpty) return;

    _totalEventsSent += batch.length;
    _batchesSent++;
    _lastFlushTime = DateTime.now();

    _batchController.add(batch);
  }

  /// Cancels all active timers.
  void _cancelTimers() {
    _batchTimer?.cancel();
    _batchTimer = null;
  }
}

/// A specialized event buffer that implements intelligent event compression
/// and performance optimization strategies.
class IntelligentEventBuffer extends FocusEventBuffer {
  final Map<String, EventSeries> _eventSeries = {};

  IntelligentEventBuffer(super.config);

  @override
  bool _shouldFilterEvent(FocusEvent event) {
    // First apply standard filtering
    if (super._shouldFilterEvent(event)) return true;

    // Apply series-based filtering
    return _shouldFilterBySeries(event);
  }

  /// Applies series-based filtering to detect patterns and reduce redundancy.
  bool _shouldFilterBySeries(FocusEvent event) {
    final series = _eventSeries.putIfAbsent(event.appName, () => EventSeries());

    // Check if this event follows a predictable pattern
    if (series.isEventPredictable(event)) {
      // Only send every nth event in a predictable series
      return series.length % 5 != 0;
    }

    series.addEvent(event);
    return false;
  }

  @override
  void dispose() {
    _eventSeries.clear();
    super.dispose();
  }
}

/// Represents a series of events for pattern detection.
class EventSeries {
  final Queue<FocusEvent> _events = Queue<FocusEvent>();
  final int _maxLength = 10;

  int get length => _events.length;

  void addEvent(FocusEvent event) {
    _events.add(event);
    if (_events.length > _maxLength) {
      _events.removeFirst();
    }
  }

  /// Checks if an event follows a predictable pattern based on the series.
  bool isEventPredictable(FocusEvent event) {
    if (_events.length < 3) return false;

    // Check for regular duration update patterns
    if (event.eventType == FocusEventType.durationUpdate) {
      final recentEvents = _events.where((e) => e.eventType == FocusEventType.durationUpdate).toList();
      if (recentEvents.length >= 3) {
        // Calculate average time between events
        final intervals = <int>[];
        for (int i = 1; i < recentEvents.length; i++) {
          intervals.add(recentEvents[i].timestamp.difference(recentEvents[i - 1].timestamp).inMicroseconds);
        }

        // Check if intervals are consistent (within 20% variance)
        final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
        final variance = intervals.map((i) => (i - avgInterval).abs()).reduce(math.max) / avgInterval;

        return variance < 0.2; // Less than 20% variance indicates predictable pattern
      }
    }

    return false;
  }

  void clear() {
    _events.clear();
  }
}
