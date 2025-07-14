# App Focus Tracker

A Flutter plugin for tracking application focus changes across macOS and Windows platforms. This plugin provides real-time monitoring of which applications are currently in focus, enabling productivity tracking, time management, and user behavior analysis.

## Features

- **Cross-Platform Support**: Native implementations for macOS and Windows
- **Real-Time Focus Tracking**: Stream-based API for live focus change events
- **Application Information**: Detailed metadata about running applications
- **Browser Tab Extraction**: Automatic detection and parsing of web browser tabs (domain, URL, title)
- **Permission Management**: Automatic handling of platform-specific permissions
- **Performance Optimized**: Efficient event handling with configurable update intervals
- **Comprehensive Testing**: Extensive test suite covering unit, integration, and performance tests

## Supported Platforms

- **macOS**: Full support with accessibility permissions
- **Windows**: Full support with process monitoring
- **Other Platforms**: Graceful fallback with platform not supported exceptions

## Getting Started

### Installation

Add the plugin to your `pubspec.yaml`:

```yaml
dependencies:
  app_focus_tracker: ^0.0.1
```

### Basic Usage

```dart
import 'package:app_focus_tracker/app_focus_tracker.dart';

void main() async {
  // Initialize the tracker
  final tracker = AppFocusTracker();
  
  // Check if the platform is supported
  if (await tracker.isSupported()) {
    // Request permissions (required on macOS)
    final hasPermissions = await tracker.hasPermissions();
    if (!hasPermissions) {
      await tracker.requestPermissions();
    }
    
    // Start tracking with custom configuration
    await tracker.startTracking(
      FocusTrackerConfig(
        updateIntervalMs: 100, // Update every 100ms
        includeSystemApps: false, // Exclude system applications
      ),
    );
    
    // Listen to focus events
    tracker.focusStream.listen((event) {
      print('App focused: ${event.appName}');
      print('Duration: ${event.duration}');
      print('Event type: ${event.eventType}');
      
      // Check if it's a browser and extract tab information
      if (event.isBrowser) {
        final tab = event.browserTab;
        if (tab != null) {
          print('Browser: ${tab.browserType}');
          print('Domain: ${tab.domain}');
          print('URL: ${tab.url}');
          print('Title: ${tab.title}');
        }
      }
    });
    
    // Get current focused application
    final currentApp = await tracker.getCurrentFocusedApp();
    print('Currently focused: ${currentApp?.name}');
    
    // Get all running applications
    final runningApps = await tracker.getRunningApplications();
    print('Running apps: ${runningApps.length}');
    
    // Stop tracking when done
    await tracker.stopTracking();
  }
}
```

### Configuration Options

```dart
FocusTrackerConfig(
  updateIntervalMs: 100,        // How often to check for focus changes (ms)
  includeSystemApps: false,     // Whether to include system applications
  enableDurationTracking: true, // Track how long apps stay in focus
  maxEventBufferSize: 1000,     // Maximum events to buffer
)
```

### Event Types

The plugin provides several types of focus events:

- `FocusEventType.gained`: Application gained focus
- `FocusEventType.lost`: Application lost focus  
- `FocusEventType.durationUpdate`: Duration update for current app
- `FocusEventType.switched`: Direct switch between applications

## API Reference

### Core Methods

- `isSupported()`: Check if the current platform is supported
- `hasPermissions()`: Check if required permissions are granted
- `requestPermissions()`: Request platform-specific permissions
- `startTracking(config)`: Start focus tracking with configuration
- `stopTracking()`: Stop focus tracking
- `isTracking()`: Check if tracking is currently active
- `getCurrentFocusedApp()`: Get the currently focused application
- `getRunningApplications()`: Get list of all running applications
- `getDiagnosticInfo()`: Get diagnostic information about the tracker

### Data Models

#### FocusEvent
```dart
class FocusEvent {
  final String eventId;
  final String appName;
  final String appIdentifier;
  final FocusEventType eventType;
  final DateTime timestamp;
  final Duration? duration;
  final Map<String, dynamic>? metadata;
}
```

#### AppInfo
```dart
class AppInfo {
  final String name;
  final String identifier;
  final int? processId;
  final String? version;
  final String? iconPath;
  final String? executablePath;
  final Map<String, dynamic>? metadata;
  
  /// Whether this application is a recognised web browser
  bool get isBrowser;
  
  /// Parsed browser tab info when [isBrowser] is true
  BrowserTabInfo? get browserTab;
}
```

#### BrowserTabInfo
```dart
class BrowserTabInfo {
  final String? domain;      // e.g., "stackoverflow.com"
  final String? url;         // e.g., "https://stackoverflow.com"
  final String title;        // Page title
  final String browserType;  // "chrome", "edge", "firefox", etc.
}
```

## Platform-Specific Features

### macOS
- Accessibility permissions required
- Bundle identifier extraction
- App version information
- Sandboxing support
- Mission Control integration
- Browser tab extraction via Accessibility API

### Windows
- Process monitoring via Win32 API
- UWP application support
- UAC elevation handling
- Multi-monitor support
- Virtual desktop detection
- Browser tab extraction via window title parsing

## Platform Setup

### macOS Setup
For macOS applications using this plugin, you need to configure accessibility permissions:

1. **Add to Info.plist**:
   ```xml
   <key>NSAccessibilityUsageDescription</key>
   <string>This app needs accessibility permissions to track which applications have focus for productivity monitoring.</string>
   ```

2. **Configure Entitlements** (disable app sandbox for development):
   ```xml
   <key>com.apple.security.app-sandbox</key>
   <false/>
   ```

3. **Run setup script**:
   ```bash
   ./docs/platform-setup/setup_accessibility.sh
   ```

See [macOS Setup Guide](docs/platform-setup/macos-setup.md) for detailed instructions.

### Windows Setup
Windows generally doesn't require special permissions, but you can verify configuration:

1. **Run setup script**:
   ```powershell
   .\docs\platform-setup\setup_permissions.ps1
   ```
   or
   ```cmd
   docs\platform-setup\setup_permissions.bat
   ```

See [Windows Setup Guide](docs/platform-setup/windows-setup.md) for detailed instructions.

## Error Handling

The plugin provides comprehensive error handling with specific exception types:

- `PlatformNotSupportedException`: Platform not supported
- `PermissionDeniedException`: Required permissions not granted
- `PlatformChannelException`: Platform communication errors
- `AppFocusTrackerException`: General plugin errors

## Testing

The plugin includes an extensive test suite:

- **Unit Tests**: Core functionality and data models
- **Integration Tests**: End-to-end workflows and scenarios
- **Platform-Specific Tests**: macOS and Windows specific features
- **Performance Tests**: Stress testing and memory management
- **Mock Platform**: Comprehensive simulation for testing

Run tests with:
```bash
flutter test
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a list of changes and version history.

