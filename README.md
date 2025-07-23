# App Focus Tracker

A Flutter plugin for tracking application focus changes across macOS and Windows platforms. This plugin provides real-time monitoring of which applications are currently in focus, enabling productivity tracking, time management, and user behavior analysis.

## Features

- **Cross-Platform Support**: Native implementations for macOS and Windows
- **Real-Time Focus Tracking**: Stream-based API for live focus change events
- **Application Information**: Detailed metadata about running applications
- **Browser Tab Extraction**: Automatic detection and parsing of web browser tabs (domain, URL, title)
- **Browser Tab Change Detection**: Track browser tab changes as regular focus events when tabs change within the same browser application
- **Permission Management**: Automatic handling of platform-specific permissions
- **Performance Optimized**: Efficient event handling with configurable update intervals
- **Comprehensive Testing**: Extensive test suite covering unit, integration, and performance tests
- **Robust Error Handling**: Advanced error recovery, memory management, and stability improvements

## Stability and Error Handling

The plugin includes comprehensive error handling and stability improvements:

### Windows Platform
- **Event Loss Prevention**: Automatic retry mechanism for failed message posting
- **Memory Management**: Event queue health monitoring with automatic cleanup
- **Enhanced Diagnostics**: Human-readable Win32 error messages for troubleshooting
- **Thread Safety**: Improved cross-thread communication and resource management

### macOS Platform  
- **Non-Blocking Operations**: AppleScript execution moved to background threads
- **Permission Management**: Automatic re-checking of accessibility permissions
- **Crash Prevention**: Recursion depth limits and stack overflow protection
- **Performance Optimization**: Adaptive polling intervals based on application type
- **Resource Cleanup**: Guaranteed cleanup using defer blocks

### Cross-Platform
- **Graceful Degradation**: Plugin continues operating even when individual features fail
- **Comprehensive Logging**: Debug information available for troubleshooting
- **Memory Safety**: Automatic resource cleanup and memory leak prevention

## Supported Platforms

- **macOS**: Full support with accessibility permissions
- **Windows**: Full support with process monitoring
- **Other Platforms**: Graceful fallback with platform not supported exceptions

## Getting Started

### Installation

Add the plugin to your `pubspec.yaml`:

```yaml
dependencies:
  app_focus_tracker: ^0.0.7
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
      
      // Check if it's a browser and extract tab information
      if (event.isBrowser && event.browserTab != null) {
        print('Browser tab: ${event.browserTab!.domain} - ${event.browserTab!.title}');
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
  includeMetadata: true,        // Include detailed app metadata
  enableBrowserTabTracking: true, // Track browser tab changes as focus events
)
```

### Event Types

The plugin provides several types of focus events:

- `FocusEventType.gained`: Application gained focus
- `FocusEventType.lost`: Application lost focus  
- `FocusEventType.durationUpdate`: Duration update for current app

**Note**: When browser tab tracking is enabled, tab changes within the same browser are treated as regular focus events (gained/lost).

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
  
  /// Whether the focused application is a recognised web browser
  bool get isBrowser;
  
  /// Parsed browser tab info when [isBrowser] is true
  BrowserTabInfo? get browserTab;
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

## Browser Tab Tracking

The plugin automatically detects when the focused application is a web browser and extracts information about the currently active tab, including:

- **Domain**: The website's domain (e.g., `stackoverflow.com`)
- **URL**: The full base URL (e.g., `https://stackoverflow.com`)
- **Title**: The cleaned page title (without browser name suffix)
- **Browser Type**: The browser being used (`chrome`, `firefox`, `safari`, etc.)

### Platform-Specific Implementation

**macOS:**
- Primary: AppleScript integration for direct URL access
- Fallback: Accessibility API (AXWebArea → AXURL)
- Last resort: Window title parsing

**Windows:**
- Primary: UIAutomation API for address bar access
- Fallback: Window title parsing with enhanced regex patterns

### Troubleshooting URL Extraction

If you're seeing "unknown" domains or missing URLs, use the debug method to identify the issue:

```dart
// Debug URL extraction for the currently focused browser
final debugInfo = await AppFocusTracker.debugUrlExtraction();
print('Debug Info: $debugInfo');
```

#### Common Issues and Solutions

**1. Browser Security Restrictions**
- **Chrome/Edge**: May block UIAutomation access to address bar
- **Solution**: Check if the browser has security policies blocking automation
- **Workaround**: Rely on window title parsing when automation fails

**2. Missing Permissions**
- **macOS**: AppleScript may be disabled by system policies
- **Windows**: UIAutomation requires appropriate process privileges
- **Solution**: Ensure all accessibility permissions are granted

**3. Browser-Specific Issues**
- **Firefox**: Limited automation support, relies heavily on title parsing
- **Safari**: Different AppleScript interface than other browsers
- **Solution**: Update browser detection patterns or use alternative extraction methods

**4. Window Title Doesn't Contain Domain**
- Some sites don't include domain in page titles
- **Solution**: Use primary extraction methods (AppleScript/UIAutomation) when available

#### Debug Output Example

```dart
{
  'isBrowser': true,
  'windowTitle': 'Stack Overflow - Where Developers Learn, Share, & Build Careers',
  'applescriptUrl': 'https://stackoverflow.com',  // macOS only
  'uiAutomationUrl': 'https://stackoverflow.com', // Windows only
  'titleExtraction': {
    'domain': 'stackoverflow.com',
    'url': 'https://stackoverflow.com',
    'valid': true
  }
}
```

#### Enabling Debug Logging

For detailed debugging information during development:

**Windows (Debug Build):**
```cpp
// Add to preprocessor definitions
#define _DEBUG
```

**macOS (Debug Build):**
```swift
// Debug output automatically enabled in DEBUG builds
#if DEBUG
print("[DEBUG] URL extraction details...")
#endif
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
- **Windows Deadlock Prevention Tests**: Comprehensive testing for Windows-specific threading and deadlock scenarios
- **Mock Platform**: Comprehensive simulation for testing

**Windows Deadlock Testing:**
The plugin includes a specialized test suite (`test/platform_specific/windows_deadlock_test.dart`) that simulates the exact conditions that could cause deadlocks in Windows applications:

- **Concurrent Event Generation**: Tests multiple threads generating events rapidly while UI thread processes them
- **Event Queue Threading Safety**: Verifies mutex deadlock prevention in event sink operations
- **Process Enumeration Thread Safety**: Ensures `getRunningApplications` executes asynchronously without blocking UI
- **Error Recovery**: Tests system recovery from native crashes and resource cleanup under stress
- **Release Build Simulation**: Catches timing-dependent deadlocks that may only occur in release builds
- **Font Rendering Contention**: Prevents DirectWrite-related deadlocks during font operations

**Manual Testing Framework:**
For release build verification, the plugin includes a manual testing framework (`test/manual/`):

- **Release Build Testing Guide**: Comprehensive documentation for testing in actual Windows release builds
- **Manual Test Script**: `windows_release_deadlock_test.dart` for real-world deadlock prevention verification
- **Stress Testing Instructions**: Guidelines for thorough verification of deadlock fixes
- **Debugging Tools**: Tips for identifying and resolving remaining threading issues

**Windows Platform Improvements:**
The Windows implementation includes several critical fixes to prevent deadlocks:

- **Event Sink Mutex Safety**: Fixed potential deadlock by copying event sink pointer under mutex and releasing lock before Flutter calls
- **Async Process Enumeration**: Moved `getRunningApplications()` to background thread to prevent UI thread blocking
- **Reduced Process Access Privileges**: Uses `PROCESS_QUERY_LIMITED_INFORMATION` for better compatibility
- **Improved Error Handling**: Suppressed noisy access-denied error logging to prevent performance impact

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