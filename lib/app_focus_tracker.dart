import 'dart:async';

// Export public API
export 'src/models/models.dart';
export 'src/exceptions/app_focus_tracker_exception.dart';

// Internal imports
import 'src/platform_interface.dart';
import 'src/method_channel.dart';
import 'src/models/models.dart';
import 'src/exceptions/app_focus_tracker_exception.dart';

/// The main class for tracking application focus events.
///
/// This class provides a high-level API for monitoring when applications
/// gain or lose focus on the current system. It supports both macOS and Windows
/// platforms with appropriate permission handling and error management.
///
/// Example usage:
/// ```dart
/// final tracker = AppFocusTracker();
///
/// // Check platform support and permissions
/// if (await tracker.isSupported()) {
///   if (!await tracker.hasPermissions()) {
///     await tracker.requestPermissions();
///   }
///
///   // Start tracking with default configuration
///   await tracker.startTracking();
///
///   // Listen to focus events
///   tracker.focusStream.listen((event) {
///     print('App: ${event.appName}, Duration: ${event.durationMs}ms');
///   });
/// }
/// ```
class AppFocusTracker {
  static bool _initialized = false;

  /// The platform interface implementation.
  AppFocusTrackerPlatform get _platform {
    _ensureInitialized();
    return AppFocusTrackerPlatform.instance;
  }

  /// Ensures the platform implementation is properly initialized.
  static void _ensureInitialized() {
    if (!_initialized) {
      // Only register the method channel if no instance is set
      if (AppFocusTrackerPlatform.maybeInstance == null) {
        MethodChannelAppFocusTracker.registerWith();
      }
      _initialized = true;
    }
  }

  /// Returns the current platform name (e.g., 'macOS', 'Windows').
  Future<String> getPlatformName() => _platform.getPlatformName();

  /// Checks if the current platform supports focus tracking.
  ///
  /// Returns `true` if focus tracking is supported on the current platform,
  /// `false` otherwise. Currently supports macOS and Windows.
  Future<bool> isSupported() => _platform.isSupported();

  /// Checks if the necessary permissions are granted for focus tracking.
  ///
  /// On macOS, this checks for accessibility permissions.
  /// On Windows, this checks for appropriate process access rights.
  ///
  /// Returns `true` if all required permissions are granted.
  Future<bool> hasPermissions() => _platform.hasPermissions();

  /// Requests the necessary permissions for focus tracking.
  ///
  /// On macOS, this will prompt the user to grant accessibility permissions
  /// in System Preferences.
  /// On Windows, this may request elevated privileges if needed.
  ///
  /// Returns `true` if permissions were granted, `false` if denied.
  /// May throw [PermissionDeniedException] with platform-specific details.
  Future<bool> requestPermissions() => _platform.requestPermissions();

  /// Starts focus tracking with the given configuration.
  ///
  /// [config] - Optional configuration for tracking behavior.
  /// If not provided, uses default configuration.
  ///
  /// This begins monitoring application focus changes and enables
  /// the [focusStream] to emit events.
  ///
  /// Throws:
  /// - [PermissionDeniedException] if permissions are not granted
  /// - [PlatformNotSupportedException] if the platform is not supported
  /// - [ConfigurationException] if the configuration is invalid
  /// - [PlatformChannelException] if there are platform communication issues
  Future<void> startTracking([FocusTrackerConfig? config]) {
    return _platform.startTracking(config ?? const FocusTrackerConfig());
  }

  /// Stops focus tracking.
  ///
  /// This will stop monitoring application focus changes and close
  /// the focus event stream. No more events will be emitted after this call.
  Future<void> stopTracking() => _platform.stopTracking();

  /// Returns whether focus tracking is currently active.
  Future<bool> isTracking() => _platform.isTracking();

  /// Gets a stream of focus events.
  ///
  /// This stream emits [FocusEvent] objects whenever:
  /// - A different application gains focus
  /// - Duration updates are sent for the currently focused application
  ///
  /// The stream will automatically close when tracking is stopped.
  /// Listen to this stream to receive real-time focus tracking data.
  ///
  /// Example:
  /// ```dart
  /// tracker.focusStream.listen(
  ///   (event) => print('${event.appName}: ${event.durationMs}ms'),
  ///   onError: (error) => print('Error: $error'),
  ///   onDone: () => print('Tracking stopped'),
  /// );
  /// ```
  Stream<FocusEvent> get focusStream => _platform.getFocusStream();

  /// Gets information about the currently focused application.
  ///
  /// Returns [AppInfo] with details about the focused app, or `null`
  /// if no application is currently focused or if the information
  /// cannot be retrieved.
  Future<AppInfo?> getCurrentFocusedApp() => _platform.getCurrentFocusedApp();

  /// Gets a list of all running applications.
  ///
  /// [includeSystemApps] - Whether to include system applications
  /// (like Finder on macOS or Explorer on Windows) in the result.
  /// Defaults to `false`.
  ///
  /// This method can be resource-intensive and is primarily intended
  /// for configuration purposes (e.g., setting up app filters).
  Future<List<AppInfo>> getRunningApplications({bool includeSystemApps = false}) {
    return _platform.getRunningApplications(includeSystemApps: includeSystemApps);
  }

  /// Updates the tracking configuration without stopping and restarting.
  ///
  /// [config] - The new configuration to apply.
  ///
  /// Returns `true` if the configuration was successfully updated,
  /// `false` if tracking needs to be restarted for the changes to take effect.
  ///
  /// Note: Not all configuration changes can be applied dynamically.
  /// Check the platform implementation documentation for details.
  Future<bool> updateConfiguration(FocusTrackerConfig config) {
    return _platform.updateConfiguration(config);
  }

  /// Gets diagnostic information about the current state of the tracker.
  ///
  /// Returns a map containing:
  /// - Tracking status and configuration
  /// - Platform-specific details and capabilities
  /// - Performance metrics and resource usage
  /// - Error information if applicable
  ///
  /// This is useful for debugging, monitoring, and health checks.
  Future<Map<String, dynamic>> getDiagnosticInfo() => _platform.getDiagnosticInfo();

  /// Convenience method to start tracking with performance-optimized settings.
  ///
  /// This uses [FocusTrackerConfig.performance()] which is optimized
  /// for minimal resource usage while maintaining reasonable accuracy.
  Future<void> startTrackingPerformance() {
    return startTracking(FocusTrackerConfig.performance());
  }

  /// Convenience method to start tracking with detailed information collection.
  ///
  /// This uses [FocusTrackerConfig.detailed()] which collects comprehensive
  /// metadata about applications but may use more system resources.
  Future<void> startTrackingDetailed() {
    return startTracking(FocusTrackerConfig.detailed());
  }

  /// Convenience method to start tracking with privacy-focused settings.
  ///
  /// This uses [FocusTrackerConfig.privacy()] which excludes common
  /// system applications and minimizes data collection.
  Future<void> startTrackingPrivacy() {
    return startTracking(FocusTrackerConfig.privacy());
  }
}
