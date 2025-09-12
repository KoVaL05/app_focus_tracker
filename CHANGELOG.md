## 0.0.10

### Windows Compilation Fixes

- Fixed build errors C2065 related to `g_mouse_hook` being an undeclared identifier by declaring global hook variables (`g_plugin_instance`, `g_event_hook`, `g_keyboard_hook`, `g_mouse_hook`) before first use in `windows/app_focus_tracker_plugin.cpp`.
- Removed duplicate later declarations to avoid redefinition and ensure consistent linkage.
- Verified no further undefined symbol issues and ensured lints are clean.

## 0.0.9

### Input Activity Tracking (optional)

- Added optional per-interval keyboard/mouse input aggregation attached to focus events.
- New `FocusTrackerConfig` fields: `enableInputActivityTracking`, `inputSamplingIntervalMs`, `inputIdleThresholdMs`,
  `normalizeMouseToVirtualDesktop`, `countKeyRepeat`, `includeMiddleButtonClicks`.
- `FocusEvent` now includes optional `input` payload with `delta` and `cumulative` stats.
- macOS: Implemented CGEventTap-based hooks, sampler, normalized mouse movement, and scroll tick standardization.
- Windows: Implemented low-level hooks (WH_KEYBOARD_LL/WH_MOUSE_LL), sampler, normalized mouse movement, and scroll tick standardization.
- Backward compatible: `input` omitted when disabled/unsupported.

## 0.0.8

### App name and window title consistency

Cross-platform changes:

- AppInfo now exposes a top-level `windowTitle` field in both Windows and macOS implementations and includes it in event payloads and `getCurrentFocusedApp`/`getRunningApplications` responses.
- The `appName` in events and `AppInfo.name` now use the application’s display name, not the active window title.

Platform details:

- Windows: `name` is derived from the process executable name with the `.exe` suffix removed; `windowTitle` is provided separately. Running apps enumeration also strips `.exe` from names.
- macOS: `name` uses `localizedName`/bundle identifier; `windowTitle` is provided separately via Accessibility API.

Notes:

- Back-compat: `metadata['windowTitle']` is still present for existing consumers, but you should prefer the new top-level `windowTitle`.

## 0.0.7

### Windows Deadlock Prevention and Testing Infrastructure

**Windows Platform Improvements:**
- **Event Sink Mutex Safety**: Fixed potential deadlock by copying event sink pointer under mutex and releasing lock before Flutter calls
- **Async Process Enumeration**: Moved `getRunningApplications()` to background thread to prevent UI thread blocking
- **Reduced Process Access Privileges**: Changed from `PROCESS_QUERY_INFORMATION` to `PROCESS_QUERY_LIMITED_INFORMATION` for better compatibility
- **Improved Error Handling**: Suppressed noisy access-denied error logging to prevent performance impact and log flooding
- **Enhanced Resource Management**: Improved cleanup operations in `FlushEventQueue()` with proper mutex handling

**Testing Infrastructure Enhancements:**
- **Comprehensive Windows Deadlock Test Suite**: Added `test/platform_specific/windows_deadlock_test.dart` with stress testing for concurrent event generation and UI thread operations
- **Manual Testing Framework**: Added `test/manual/` directory with release build testing guide and manual test script
- **Test Runner Integration**: Integrated Windows deadlock tests into the main test runner for automated CI/CD
- **Release Build Verification**: Added manual test script specifically for Windows release build deadlock prevention

**Test Coverage Improvements:**
- **Event Queue Threading Safety**: Tests for mutex deadlock prevention in event sink operations
- **Process Enumeration Thread Safety**: Verification of async operation without UI blocking
- **Error Recovery and Resource Management**: Stress testing under heavy load conditions
- **Release Build Simulation**: Tests to catch timing-dependent deadlocks that only occur in release builds
- **Font Rendering Contention**: Prevention of DirectWrite-related deadlocks during font operations
- **High-Frequency Event Generation**: Testing from background threads with UI thread responsiveness validation

## 0.0.6

### Stability and Error Handling Improvements

**Windows Platform:**
- Added PostMessage retry mechanism with 20ms timer to prevent event loss when message posting fails
- Implemented event queue health monitoring with 1000-event cap to prevent memory bloat
- Enhanced Win32 error reporting with human-readable error messages via `FormatMessageA`
- Added detailed logging for `OpenProcess` failures with error codes and descriptions
- Improved thread safety in event queue management

**macOS Platform:**
- Moved AppleScript execution to background queue with 300ms timeout to prevent main thread blocking
- Added 30-second throttling after Apple-Events privacy denial (-1743) to avoid repeated prompts
- Implemented accessibility permission re-checking with 2-second polling after permission request
- Added recursion depth limit (1500 levels) to AX tree traversal to prevent stack overflow crashes
- Enhanced browser tab comparison to ignore dynamic counters and punctuation, reducing false positives
- Implemented adaptive polling intervals (0.5s for browsers, 1.5s for non-browsers) to improve performance
- Added `defer` block in `stopTracking()` to guarantee cleanup even during partial failures
- All debug logging now properly guarded with `#if DEBUG` to prevent production log spam

**Cross-Platform:**
- Improved error handling and recovery mechanisms across both platforms
- Enhanced diagnostic information for troubleshooting permission and access issues
- Better memory management and resource cleanup

### Bug Fixes

**Windows:**
- Fixed potential event loss when PostMessage fails due to message pump issues
- Resolved memory growth issues during prolonged message queue stalls
- Improved error diagnostics for process access failures

**macOS:**
- Fixed main thread blocking during AppleScript execution
- Resolved stack overflow crashes on deep accessibility trees
- Fixed false-positive browser tab change events from dynamic title updates
- Improved cleanup reliability during tracking start/stop operations

## 0.0.5

### Bug Fixes

**Windows Compilation:**
- Fixed Windows compilation error C2280: "AppFocusTrackerPlugin::AppFocusTrackerPlugin(const AppFocusTrackerPlugin &)": attempt to reference a deleted function
- Fixed Windows compilation warning C4244: conversion from 'int' to 'char', possible loss of data (treated as error)
- Replaced invalid copy construction with lightweight `AppFocusTrackerStreamHandler` wrapper to avoid copying plugin instances
- Updated `std::transform` calls with `::tolower` to use safe lambda functions with explicit type casting
- Added missing `<cctype>` include for proper `std::tolower` usage
- All Windows compilation errors and warnings now resolved

## 0.0.4

### Bug Fixes

**Windows Compilation:**
- Fixed Windows compilation error where `FocusTrackerConfig` struct was undefined in header file
- Moved `FocusTrackerConfig` and `AppInfo` struct definitions from `.cpp` to `.h` file to resolve C2079 error
- Added proper method implementations with scope resolution operators in `.cpp` file
- Added missing includes (`<set>`, `<map>`) to header file for struct member types
- Maintained proper separation of interface and implementation while fixing compilation issues

## 0.0.3

### New Features

**Browser Tab Change Detection:**
- Added `enableBrowserTabTracking` configuration option to enable/disable browser tab change detection
- When enabled, browser tab changes within the same browser are treated as regular focus events (gained/lost)
- Real-time browser tab change detection on both macOS and Windows platforms
- Automatic browser tab information extraction and comparison for change detection

**Configuration Enhancements:**
- Added `enableBrowserTabTracking` field to `FocusTrackerConfig`
- Browser tab tracking requires both `includeMetadata: true` and `enableBrowserTabTracking: true`
- Default `FocusTrackerConfig.detailed()` now enables browser tab tracking by default
- Simplified approach: tab changes emit regular focus events instead of special event types

**Platform Implementations:**
- **macOS**: Added browser tab change detection using Accessibility API with 500ms polling interval
- **Windows**: Added browser tab change detection using Win32 API with 500ms polling interval
- Both platforms now track browser tab information changes and emit regular focus events when tabs change

### Testing and Maintenance

- Fixed all test failures in `/test` directory
- Updated mock platform implementations to include `debugUrlExtraction` and `getDiagnosticInfo` methods
- Updated tests to use static `AppFocusTracker.getDiagnosticInfo()` as required by the API
- Ensured all platform interface requirements are satisfied in all test mocks and local overrides
- All tests now pass successfully

## 0.0.2

### Bug Fixes

**Platform Compatibility:**
- Fixed `MissingPluginException` when calling `updateConfiguration()` on platforms that don't implement this optional method
- Added graceful fallback to Dart-side configuration updates for backward compatibility
- Enhanced `safeMapConversion()` to handle nested `Map<Object?, Object?>` structures from platform channels
- Resolved type casting errors in `getRunningApplications()` by ensuring all map keys are converted to String

**Error Handling:**
- Improved error recovery for missing native method implementations
- Better handling of platform channel data type mismatches
- Enhanced debugging output for map conversion failures

## 0.0.1

### Initial Release

**Features:**
- Cross-platform app focus tracking for macOS and Windows
- Real-time focus event streaming with configurable update intervals
- Comprehensive application information extraction
- **Browser tab extraction** - Automatic detection and parsing of web browser tabs (domain, URL, title)
- Platform-specific permission handling (macOS accessibility, Windows process monitoring)
- Support for system app filtering and duration tracking
- Extensive error handling with platform-specific exceptions

**Platform Support:**
- **macOS**: Full implementation with accessibility permissions, bundle identifier extraction, sandboxing support, and browser tab extraction via Accessibility API
- **Windows**: Complete implementation with Win32 API integration, UWP app support, UAC handling, and browser tab extraction via window title parsing
- **Other Platforms**: Graceful fallback with platform not supported exceptions

**API:**
- `AppFocusTracker`: Main plugin class with focus tracking capabilities
- `FocusTrackerConfig`: Configuration options for tracking behavior
- `FocusEvent`: Data model for focus change events
- `AppInfo`: Data model for application information with browser detection
- `BrowserTabInfo`: Data model for browser tab information
- `FocusEventType`: Enumeration of event types (gained, lost, durationUpdate, switched)

**Testing:**
- Comprehensive test suite with 160+ tests covering:
  - Unit tests for data models and core functionality
  - Integration tests for end-to-end workflows
  - Platform-specific tests for macOS and Windows features
  - Performance and stress tests for reliability
  - Mock platform implementation for testing scenarios
  - Browser tab extraction tests

**Documentation:**
- Complete API documentation and usage examples
- Platform-specific feature documentation
- Error handling guide
- Testing instructions
- Browser tab extraction examples
