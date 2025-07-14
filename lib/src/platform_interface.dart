import 'dart:async';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models/focus_event.dart';
import 'models/focus_tracker_config.dart';
import 'models/app_info.dart';
import 'exceptions/app_focus_tracker_exception.dart';

/// The interface that implementations of app_focus_tracker must implement.
///
/// Platform implementations should extend this class rather than implement it
/// directly, to avoid breaking changes when new methods are added.
abstract class AppFocusTrackerPlatform extends PlatformInterface {
  /// Constructs an AppFocusTrackerPlatform.
  AppFocusTrackerPlatform() : super(token: _token);

  static final Object _token = Object();

  static AppFocusTrackerPlatform? _instance;

  /// The default instance of [AppFocusTrackerPlatform] to use.
  ///
  /// Defaults to [MethodChannelAppFocusTracker].
  static AppFocusTrackerPlatform get instance {
    _instance ??= _createDefaultInstance();
    return _instance!;
  }

  static AppFocusTrackerPlatform? get maybeInstance => _instance;

  /// Creates the default method channel implementation.
  /// This is defined in a separate method to avoid circular imports.
  static AppFocusTrackerPlatform _createDefaultInstance() {
    // This will be imported dynamically to avoid circular dependency
    // The actual implementation is set by the method channel implementation
    throw UnimplementedError(
      'Default platform implementation not registered. '
      'Make sure to import the app_focus_tracker package properly.',
    );
  }

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AppFocusTrackerPlatform] when
  /// they register themselves.
  static set instance(AppFocusTrackerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns the current platform name.
  ///
  /// This is used for platform-specific error handling and feature detection.
  Future<String> getPlatformName() {
    throw UnimplementedError('getPlatformName() has not been implemented.');
  }

  /// Checks if the current platform supports focus tracking.
  ///
  /// Returns true if the platform has the necessary APIs and permissions
  /// to track application focus changes.
  Future<bool> isSupported() {
    throw UnimplementedError('isSupported() has not been implemented.');
  }

  /// Checks if the necessary permissions are granted for focus tracking.
  ///
  /// On macOS, this checks for accessibility permissions.
  /// On Windows, this checks for appropriate process access rights.
  Future<bool> hasPermissions() {
    throw UnimplementedError('hasPermissions() has not been implemented.');
  }

  /// Requests the necessary permissions for focus tracking.
  ///
  /// On macOS, this will prompt the user to grant accessibility permissions.
  /// On Windows, this may request elevated privileges if needed.
  ///
  /// Returns true if permissions were granted, false otherwise.
  Future<bool> requestPermissions() {
    throw UnimplementedError('requestPermissions() has not been implemented.');
  }

  /// Starts focus tracking with the given configuration.
  ///
  /// This begins monitoring application focus changes and will start
  /// emitting events through the [getFocusStream] stream.
  ///
  /// Throws [PermissionDeniedException] if permissions are not granted.
  /// Throws [PlatformNotSupportedException] if the platform is not supported.
  /// Throws [ConfigurationException] if the configuration is invalid.
  Future<void> startTracking(FocusTrackerConfig config) {
    throw UnimplementedError('startTracking() has not been implemented.');
  }

  /// Stops focus tracking.
  ///
  /// This will stop monitoring application focus changes and close
  /// the focus event stream. No more events will be emitted after this.
  Future<void> stopTracking() {
    throw UnimplementedError('stopTracking() has not been implemented.');
  }

  /// Returns whether focus tracking is currently active.
  Future<bool> isTracking() {
    throw UnimplementedError('isTracking() has not been implemented.');
  }

  /// Gets a stream of focus events.
  ///
  /// This stream will emit [FocusEvent] objects whenever the focused
  /// application changes or when duration updates are sent for the
  /// currently focused application.
  ///
  /// The stream will close when tracking is stopped or when an error occurs.
  Stream<FocusEvent> getFocusStream() {
    throw UnimplementedError('getFocusStream() has not been implemented.');
  }

  /// Gets information about the currently focused application.
  ///
  /// Returns null if no application is currently focused or if the
  /// information cannot be retrieved.
  Future<AppInfo?> getCurrentFocusedApp() {
    throw UnimplementedError('getCurrentFocusedApp() has not been implemented.');
  }

  /// Gets a list of all running applications.
  ///
  /// This is useful for configuration purposes (e.g., setting up
  /// inclusion/exclusion lists) but may be resource-intensive.
  ///
  /// The [includeSystemApps] parameter controls whether system
  /// applications are included in the result.
  Future<List<AppInfo>> getRunningApplications({bool includeSystemApps = false}) {
    throw UnimplementedError('getRunningApplications() has not been implemented.');
  }

  /// Updates the tracking configuration without stopping and restarting.
  ///
  /// This allows for dynamic configuration changes during tracking.
  /// Not all configuration changes may be supported - check the
  /// implementation documentation for details.
  ///
  /// Returns true if the configuration was successfully updated,
  /// false if a restart is required for the changes to take effect.
  Future<bool> updateConfiguration(FocusTrackerConfig config) {
    throw UnimplementedError('updateConfiguration() has not been implemented.');
  }

  /// Gets diagnostic information about the current state of the tracker.
  ///
  /// This includes information like tracking status, configuration,
  /// platform-specific details, and performance metrics.
  /// Useful for debugging and monitoring.
  Future<Map<String, dynamic>> getDiagnosticInfo() {
    throw UnimplementedError('getDiagnosticInfo() has not been implemented.');
  }
}
