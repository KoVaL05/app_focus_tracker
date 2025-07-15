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
