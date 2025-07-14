import 'browser_tab_info.dart';
import '../utils/map_conversion.dart';

/// Represents a single application focus event with timing information.
///
/// This immutable class contains all the data associated with an application
/// gaining or losing focus, including timestamps and duration calculations.
class FocusEvent {
  /// The name of the application that gained focus
  final String appName;

  /// The bundle identifier (macOS) or executable path (Windows) of the application
  final String? appIdentifier;

  /// The timestamp when this focus event occurred (microsecond precision)
  final DateTime timestamp;

  /// The duration this application has been in focus (in microseconds)
  /// This represents the cumulative time since the app gained focus
  final int durationMicroseconds;

  /// The process ID of the focused application
  final int? processId;

  /// The type of focus event (gained, lost, duration_update)
  final FocusEventType eventType;

  /// Unique identifier for this event to enable correlation and deduplication
  final String eventId;

  /// The session ID to group related events together
  final String? sessionId;

  /// Additional metadata about the application (version, icon path, etc.)
  final Map<String, dynamic>? metadata;

  /// Whether the focused application is a recognised web browser
  bool get isBrowser => (metadata?['isBrowser'] as bool?) ?? false;

  /// Parsed browser tab info when [isBrowser] is true and data available
  BrowserTabInfo? get browserTab {
    final tabJson = metadata?['browserTab'];
    if (tabJson is Map<String, dynamic>) {
      return BrowserTabInfo.fromJson(tabJson);
    }
    return null;
  }

  /// Creates a new [FocusEvent] instance.
  ///
  /// [appName] is required and represents the display name of the application.
  /// [timestamp] defaults to the current time if not provided.
  /// [durationMicroseconds] represents how long the app has been focused in microseconds.
  /// [eventType] defaults to [FocusEventType.gained] if not specified.
  /// [eventId] is auto-generated if not provided.
  FocusEvent({
    required this.appName,
    this.appIdentifier,
    DateTime? timestamp,
    required this.durationMicroseconds,
    this.processId,
    this.eventType = FocusEventType.gained,
    String? eventId,
    this.sessionId,
    this.metadata,
  })  : timestamp = timestamp ?? DateTime.now(),
        eventId = eventId ?? _generateEventId();

  /// Creates a [FocusEvent] from a JSON map.
  ///
  /// This is typically used when deserializing events from platform channels.
  factory FocusEvent.fromJson(Map<String, dynamic> json) {
    return FocusEvent(
      appName: json['appName'] as String,
      appIdentifier: json['appIdentifier'] as String?,
      timestamp:
          json['timestamp'] != null ? DateTime.fromMicrosecondsSinceEpoch(json['timestamp'] as int) : DateTime.now(),
      durationMicroseconds: json['durationMicroseconds'] as int? ?? _convertLegacyDuration(json),
      processId: json['processId'] as int?,
      eventType: FocusEventType.values.firstWhere(
        (type) => type.name == json['eventType'],
        orElse: () => FocusEventType.gained,
      ),
      eventId: json['eventId'] as String?,
      sessionId: json['sessionId'] as String?,
      metadata: safeMapConversion(json['metadata']),
    );
  }

  /// Converts this [FocusEvent] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'appName': appName,
      'appIdentifier': appIdentifier,
      'timestamp': timestamp.microsecondsSinceEpoch,
      'durationMicroseconds': durationMicroseconds,
      'processId': processId,
      'eventType': eventType.name,
      'eventId': eventId,
      'sessionId': sessionId,
      'metadata': metadata,
    };
  }

  /// Creates a copy of this [FocusEvent] with updated duration.
  ///
  /// This is useful for updating the duration as time progresses while
  /// the same application remains in focus.
  FocusEvent copyWithDuration(int newDurationMicroseconds) {
    return FocusEvent(
      appName: appName,
      appIdentifier: appIdentifier,
      timestamp: timestamp,
      durationMicroseconds: newDurationMicroseconds,
      processId: processId,
      eventType: FocusEventType.durationUpdate,
      eventId: _generateEventId(),
      sessionId: sessionId,
      metadata: metadata,
    );
  }

  /// Creates a copy of this [FocusEvent] with updated event type.
  FocusEvent copyWithEventType(FocusEventType newEventType) {
    return FocusEvent(
      appName: appName,
      appIdentifier: appIdentifier,
      timestamp: timestamp,
      durationMicroseconds: durationMicroseconds,
      processId: processId,
      eventType: newEventType,
      eventId: eventId,
      sessionId: sessionId,
      metadata: metadata,
    );
  }

  /// Gets the duration in milliseconds (for backward compatibility)
  int get durationMs => (durationMicroseconds / 1000).round();

  /// Gets the duration in seconds
  double get durationSeconds => durationMicroseconds / 1000000.0;

  /// Gets a human-readable duration string
  String get durationFormatted {
    final seconds = durationSeconds;
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(1)}s';
    } else if (seconds < 3600) {
      final minutes = (seconds / 60).floor();
      final remainingSeconds = (seconds % 60).floor();
      return '${minutes}m ${remainingSeconds}s';
    } else {
      final hours = (seconds / 3600).floor();
      final minutes = ((seconds % 3600) / 60).floor();
      return '${hours}h ${minutes}m';
    }
  }

  /// Checks if this event represents a significant focus change
  bool get isSignificantEvent {
    switch (eventType) {
      case FocusEventType.gained:
      case FocusEventType.lost:
        return true;
      case FocusEventType.durationUpdate:
        // Only consider duration updates significant if they represent substantial time
        return durationSeconds >= 5.0;
    }
  }

  /// Gets the age of this event in microseconds
  int get ageMicroseconds => DateTime.now().microsecondsSinceEpoch - timestamp.microsecondsSinceEpoch;

  /// Generates a unique event ID
  static String _generateEventId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = timestamp.hashCode;
    return 'evt_${timestamp}_$random';
  }

  /// Converts legacy duration format to microseconds
  static int _convertLegacyDuration(Map<String, dynamic> json) {
    // Support legacy 'duration' field in milliseconds
    final legacyDuration = json['duration'] as int?;
    if (legacyDuration != null) {
      return legacyDuration * 1000; // Convert ms to microseconds
    }

    // Support legacy 'durationMs' field
    final legacyDurationMs = json['durationMs'] as int?;
    if (legacyDurationMs != null) {
      return legacyDurationMs * 1000; // Convert ms to microseconds
    }

    return 0; // Default to 0 if no duration found
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FocusEvent) return false;
    return appName == other.appName &&
        appIdentifier == other.appIdentifier &&
        timestamp == other.timestamp &&
        durationMicroseconds == other.durationMicroseconds &&
        processId == other.processId &&
        eventType == other.eventType &&
        eventId == other.eventId &&
        sessionId == other.sessionId;
  }

  @override
  int get hashCode {
    return Object.hash(
      appName,
      appIdentifier,
      timestamp,
      durationMicroseconds,
      processId,
      eventType,
      eventId,
      sessionId,
    );
  }

  @override
  String toString() {
    return 'FocusEvent(appName: $appName, appIdentifier: $appIdentifier, '
        'timestamp: $timestamp, duration: $durationFormatted, '
        'eventType: $eventType, eventId: $eventId, processId: $processId)';
  }
}

/// Represents the type of focus event that occurred
enum FocusEventType {
  /// Application gained focus
  gained,

  /// Application lost focus
  lost,

  /// Duration update for currently focused application
  durationUpdate,
}
