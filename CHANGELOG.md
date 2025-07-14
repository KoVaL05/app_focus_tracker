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
