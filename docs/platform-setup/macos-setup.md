# macOS Setup for App Focus Tracker Plugin

This guide explains how to configure your macOS Flutter application to use the App Focus Tracker plugin.

## Accessibility Permissions

The app requires accessibility permissions to track which applications have focus. Here's how to set it up:

### Automatic Setup

Run the setup script to check your configuration:

```bash
# From your Flutter project root
./docs/platform-setup/setup_accessibility.sh
```

### Manual Configuration

If the app doesn't appear in System Preferences, ensure these settings are correct:

#### 1. Info.plist Configuration

The `Runner/Info.plist` file should contain:

```xml
<key>NSAccessibilityUsageDescription</key>
<string>This app needs accessibility permissions to track which applications have focus for productivity monitoring.</string>
```

#### 2. Entitlements Configuration

Both `DebugProfile.entitlements` and `Release.entitlements` should have:

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
<key>com.apple.security.automation.apple-events</key>
<true/>
```

### Troubleshooting

If the app doesn't appear in System Preferences > Security & Privacy > Privacy > Accessibility:

1. **Clean and rebuild**:
   ```bash
   flutter clean
   flutter pub get
   ```

2. **Run from Xcode** (recommended for development):
   ```bash
   open macos/Runner.xcworkspace
   ```
   Then build and run from Xcode

3. **Check code signing**:
   - Ensure you have a valid developer certificate
   - The app must be properly signed to appear in System Preferences

4. **Restart the app** after granting permissions

5. **Restart your Mac** if permissions still don't work

### Development vs Production

- **Development**: App sandbox is disabled to allow accessibility access
- **Production**: Consider re-enabling app sandbox and using proper entitlements for App Store distribution

### Testing Permissions

1. Run the app: `flutter run -d macos`
2. Click "Request Permissions" in the app
3. If permissions aren't granted, click "Open Settings"
4. Grant accessibility permissions in System Preferences
5. Return to the app and try "Request Permissions" again

The app should now be able to track focus changes between applications. 