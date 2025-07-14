/// Configuration options for the focus tracker.
///
/// This class allows customization of how focus tracking behaves,
/// including performance settings and privacy options.
class FocusTrackerConfig {
  /// How frequently to update duration for the currently focused app (in milliseconds)
  /// Default is 1000ms (1 second)
  final int updateIntervalMs;

  /// Whether to include detailed app metadata in events
  /// This may impact performance but provides richer information
  final bool includeMetadata;

  /// Whether to track system applications (like Finder, Desktop, etc.)
  /// Default is false to focus on user applications
  final bool includeSystemApps;

  /// List of app identifiers to exclude from tracking
  /// Useful for privacy or performance reasons
  final Set<String> excludedApps;

  /// List of app identifiers to exclusively track
  /// When non-empty, only these apps will be tracked
  final Set<String> includedApps;

  /// Whether to batch events for better performance
  /// When true, multiple events may be combined before sending
  final bool enableBatching;

  /// Maximum number of events to batch before sending
  /// Only applies when enableBatching is true
  final int maxBatchSize;

  /// Maximum time to wait before sending a batch (in milliseconds)
  /// Only applies when enableBatching is true
  final int maxBatchWaitMs;

  /// Creates a new [FocusTrackerConfig] instance.
  const FocusTrackerConfig({
    this.updateIntervalMs = 1000,
    this.includeMetadata = false,
    this.includeSystemApps = false,
    this.excludedApps = const {},
    this.includedApps = const {},
    this.enableBatching = false,
    this.maxBatchSize = 10,
    this.maxBatchWaitMs = 5000,
  });

  /// Creates a default configuration for optimal performance.
  factory FocusTrackerConfig.performance() {
    return const FocusTrackerConfig(
      updateIntervalMs: 2000,
      includeMetadata: false,
      includeSystemApps: false,
      enableBatching: true,
      maxBatchSize: 20,
      maxBatchWaitMs: 3000,
    );
  }

  /// Creates a default configuration for detailed tracking.
  factory FocusTrackerConfig.detailed() {
    return const FocusTrackerConfig(
      updateIntervalMs: 500,
      includeMetadata: true,
      includeSystemApps: true,
      enableBatching: false,
    );
  }

  /// Creates a privacy-focused configuration that excludes common system apps.
  factory FocusTrackerConfig.privacy() {
    return const FocusTrackerConfig(
      updateIntervalMs: 1000,
      includeMetadata: false,
      includeSystemApps: false,
      excludedApps: {
        'com.apple.finder', // macOS Finder
        'com.apple.dock', // macOS Dock
        'com.apple.systempreferences', // macOS System Preferences
        'explorer.exe', // Windows Explorer
        'dwm.exe', // Windows Desktop Window Manager
      },
      enableBatching: true,
    );
  }

  /// Creates a [FocusTrackerConfig] from a JSON map.
  factory FocusTrackerConfig.fromJson(Map<String, dynamic> json) {
    return FocusTrackerConfig(
      updateIntervalMs: json['updateIntervalMs'] as int? ?? 1000,
      includeMetadata: json['includeMetadata'] as bool? ?? false,
      includeSystemApps: json['includeSystemApps'] as bool? ?? false,
      excludedApps: (json['excludedApps'] as List<dynamic>?)?.map((e) => e as String).toSet() ?? const {},
      includedApps: (json['includedApps'] as List<dynamic>?)?.map((e) => e as String).toSet() ?? const {},
      enableBatching: json['enableBatching'] as bool? ?? false,
      maxBatchSize: json['maxBatchSize'] as int? ?? 10,
      maxBatchWaitMs: json['maxBatchWaitMs'] as int? ?? 5000,
    );
  }

  /// Converts this [FocusTrackerConfig] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'updateIntervalMs': updateIntervalMs,
      'includeMetadata': includeMetadata,
      'includeSystemApps': includeSystemApps,
      'excludedApps': excludedApps.toList(),
      'includedApps': includedApps.toList(),
      'enableBatching': enableBatching,
      'maxBatchSize': maxBatchSize,
      'maxBatchWaitMs': maxBatchWaitMs,
    };
  }

  /// Creates a copy of this config with updated values.
  FocusTrackerConfig copyWith({
    int? updateIntervalMs,
    bool? includeMetadata,
    bool? includeSystemApps,
    Set<String>? excludedApps,
    Set<String>? includedApps,
    bool? enableBatching,
    int? maxBatchSize,
    int? maxBatchWaitMs,
  }) {
    return FocusTrackerConfig(
      updateIntervalMs: updateIntervalMs ?? this.updateIntervalMs,
      includeMetadata: includeMetadata ?? this.includeMetadata,
      includeSystemApps: includeSystemApps ?? this.includeSystemApps,
      excludedApps: excludedApps ?? this.excludedApps,
      includedApps: includedApps ?? this.includedApps,
      enableBatching: enableBatching ?? this.enableBatching,
      maxBatchSize: maxBatchSize ?? this.maxBatchSize,
      maxBatchWaitMs: maxBatchWaitMs ?? this.maxBatchWaitMs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FocusTrackerConfig) return false;
    return updateIntervalMs == other.updateIntervalMs &&
        includeMetadata == other.includeMetadata &&
        includeSystemApps == other.includeSystemApps &&
        excludedApps == other.excludedApps &&
        includedApps == other.includedApps &&
        enableBatching == other.enableBatching &&
        maxBatchSize == other.maxBatchSize &&
        maxBatchWaitMs == other.maxBatchWaitMs;
  }

  @override
  int get hashCode {
    return Object.hash(
      updateIntervalMs,
      includeMetadata,
      includeSystemApps,
      excludedApps,
      includedApps,
      enableBatching,
      maxBatchSize,
      maxBatchWaitMs,
    );
  }

  @override
  String toString() {
    return 'FocusTrackerConfig(updateIntervalMs: $updateIntervalMs, '
        'includeMetadata: $includeMetadata, includeSystemApps: $includeSystemApps, '
        'enableBatching: $enableBatching)';
  }
}
