/// Base exception class for all app focus tracker related errors.
///
/// This provides a common interface for all exceptions that can occur
/// during app focus tracking operations.
abstract class AppFocusTrackerException implements Exception {
  /// A human-readable error message describing what went wrong.
  final String message;

  /// Optional error code for programmatic error handling.
  final String? code;

  /// Optional underlying cause of this exception.
  final dynamic cause;

  const AppFocusTrackerException(
    this.message, {
    this.code,
    this.cause,
  });

  @override
  String toString() {
    final codeStr = code != null ? ' ($code)' : '';
    final causeStr = cause != null ? '\nCaused by: $cause' : '';
    return 'AppFocusTrackerException$codeStr: $message$causeStr';
  }
}

/// Exception thrown when platform permissions are denied or insufficient.
///
/// This typically occurs when the user hasn't granted accessibility permissions
/// (macOS) or when the application lacks necessary privileges.
class PermissionDeniedException extends AppFocusTrackerException {
  /// The type of permission that was denied.
  final String permissionType;

  /// Instructions for how the user can grant the required permission.
  final String? instructions;

  const PermissionDeniedException(
    String message, {
    required this.permissionType,
    this.instructions,
    String? code,
    dynamic cause,
  }) : super(message, code: code, cause: cause);

  /// Creates a permission exception for macOS accessibility permissions.
  factory PermissionDeniedException.macOSAccessibility() {
    return const PermissionDeniedException(
      'Accessibility permission is required to track app focus on macOS',
      permissionType: 'accessibility',
      instructions:
          'Please grant accessibility permission in System Preferences > Security & Privacy > Privacy > Accessibility',
      code: 'MACOS_ACCESSIBILITY_DENIED',
    );
  }

  /// Creates a permission exception for Windows UAC or privileges.
  factory PermissionDeniedException.windowsPrivileges() {
    return const PermissionDeniedException(
      'Insufficient privileges to track app focus on Windows',
      permissionType: 'windows_privileges',
      instructions: 'The application may need to run with elevated privileges or have specific permissions',
      code: 'WINDOWS_PRIVILEGES_DENIED',
    );
  }

  @override
  String toString() {
    final instructionsStr = instructions != null ? '\nInstructions: $instructions' : '';
    return 'PermissionDeniedException ($permissionType): $message$instructionsStr';
  }
}

/// Exception thrown when the current platform is not supported.
///
/// This occurs when trying to use the focus tracker on a platform
/// that doesn't have a native implementation.
class PlatformNotSupportedException extends AppFocusTrackerException {
  /// The name of the unsupported platform.
  final String platform;

  /// List of platforms that are supported.
  final List<String> supportedPlatforms;

  const PlatformNotSupportedException(
    String message, {
    required this.platform,
    required this.supportedPlatforms,
    String? code,
    dynamic cause,
  }) : super(message, code: code, cause: cause);

  /// Creates a platform not supported exception with default supported platforms.
  factory PlatformNotSupportedException.create(String platform) {
    return PlatformNotSupportedException(
      'Platform "$platform" is not supported for app focus tracking',
      platform: platform,
      supportedPlatforms: const ['macOS', 'Windows'],
      code: 'PLATFORM_NOT_SUPPORTED',
    );
  }

  @override
  String toString() {
    return 'PlatformNotSupportedException: $message\n'
        'Platform: $platform\n'
        'Supported platforms: ${supportedPlatforms.join(', ')}';
  }
}

/// Exception thrown when there are issues with the platform channel communication.
///
/// This can occur due to method channel errors, encoding/decoding issues,
/// or native code errors.
class PlatformChannelException extends AppFocusTrackerException {
  /// The name of the method or channel that failed.
  final String? channelName;

  /// Details about the platform error if available.
  final Map<String, dynamic>? platformDetails;

  const PlatformChannelException(
    String message, {
    this.channelName,
    this.platformDetails,
    String? code,
    dynamic cause,
  }) : super(message, code: code, cause: cause);

  @override
  String toString() {
    final channelStr = channelName != null ? ' (channel: $channelName)' : '';
    final detailsStr = platformDetails != null ? '\nPlatform details: $platformDetails' : '';
    return 'PlatformChannelException$channelStr: $message$detailsStr';
  }
}

/// Exception thrown when the focus tracker configuration is invalid.
///
/// This occurs when configuration values are out of acceptable ranges
/// or contain conflicting settings.
class ConfigurationException extends AppFocusTrackerException {
  /// The name of the configuration parameter that is invalid.
  final String? parameterName;

  /// The invalid value that was provided.
  final dynamic invalidValue;

  /// The expected value or range for the parameter.
  final String? expectedValue;

  const ConfigurationException(
    String message, {
    this.parameterName,
    this.invalidValue,
    this.expectedValue,
    String? code,
    dynamic cause,
  }) : super(message, code: code, cause: cause);

  @override
  String toString() {
    final paramStr = parameterName != null ? ' (parameter: $parameterName)' : '';
    final valueStr = invalidValue != null ? '\nInvalid value: $invalidValue' : '';
    final expectedStr = expectedValue != null ? '\nExpected: $expectedValue' : '';
    return 'ConfigurationException$paramStr: $message$valueStr$expectedStr';
  }
}

/// Exception thrown when focus tracking operations time out.
///
/// This can occur when the platform takes too long to respond or
/// when waiting for events exceeds configured timeouts.
class TimeoutException extends AppFocusTrackerException {
  /// The operation that timed out.
  final String operation;

  /// The timeout duration that was exceeded (in milliseconds).
  final int timeoutMs;

  const TimeoutException(
    String message, {
    required this.operation,
    required this.timeoutMs,
    String? code,
    dynamic cause,
  }) : super(message, code: code, cause: cause);

  @override
  String toString() {
    return 'TimeoutException: $message\n'
        'Operation: $operation\n'
        'Timeout: ${timeoutMs}ms';
  }
}
