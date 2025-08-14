/// Detailed information about an application.
///
/// This class provides comprehensive metadata about an application
/// including platform-specific identifiers and optional details.
import 'browser_tab_info.dart';
import '../utils/map_conversion.dart';

class AppInfo {
  /// The display name of the application
  final String name;

  /// The bundle identifier (macOS) or executable path (Windows)
  final String identifier;

  /// The process ID of the application
  final int? processId;

  /// The version string of the application
  final String? version;

  /// The path to the application's icon (if available)
  final String? iconPath;

  /// The full path to the application executable
  final String? executablePath;

  /// The window title of the currently focused window for this app (if available)
  final String? windowTitle;

  /// Additional platform-specific metadata
  final Map<String, dynamic>? metadata;

  /// Creates a new [AppInfo] instance.
  const AppInfo({
    required this.name,
    required this.identifier,
    this.processId,
    this.version,
    this.iconPath,
    this.executablePath,
    this.windowTitle,
    this.metadata,
  });

  /// Creates an [AppInfo] from a JSON map.
  ///
  /// This is typically used when deserializing app information from platform channels.
  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      name: json['name'] as String,
      identifier: json['identifier'] as String,
      processId: json['processId'] as int?,
      version: json['version'] as String?,
      iconPath: json['iconPath'] as String?,
      executablePath: json['executablePath'] as String?,
      windowTitle: json['windowTitle'] as String?,
      metadata: safeMapConversion(json['metadata']),
    );
  }

  /// Converts this [AppInfo] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'identifier': identifier,
      'processId': processId,
      'version': version,
      'iconPath': iconPath,
      'executablePath': executablePath,
      'windowTitle': windowTitle,
      'metadata': metadata,
    };
  }

  /// Whether this application is a recognised web browser.
  bool get isBrowser => (metadata?['isBrowser'] as bool?) ?? false;

  /// Parsed browser tab info when [isBrowser] is true and data available, otherwise null.
  BrowserTabInfo? get browserTab {
    final tabJson = metadata?['browserTab'];
    if (tabJson is Map<String, dynamic>) {
      return BrowserTabInfo.fromJson(tabJson);
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AppInfo) return false;
    return name == other.name &&
        identifier == other.identifier &&
        processId == other.processId &&
        version == other.version &&
        iconPath == other.iconPath &&
        executablePath == other.executablePath;
  }

  @override
  int get hashCode {
    return Object.hash(
      name,
      identifier,
      processId,
      version,
      iconPath,
      executablePath,
    );
  }

  @override
  String toString() {
    return 'AppInfo(name: $name, identifier: $identifier, processId: $processId, version: $version)';
  }
}
