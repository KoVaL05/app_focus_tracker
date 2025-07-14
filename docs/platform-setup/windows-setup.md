# Windows Setup for App Focus Tracker Plugin

This guide explains how to configure your Windows Flutter application to use the App Focus Tracker plugin.

## Windows Permissions

Windows generally doesn't require special permissions for focus tracking, but the app performs runtime checks to ensure it can access the necessary Windows APIs:

### Permission Checks

The app verifies:
1. **Window Access**: Ability to get foreground window information
2. **Event Hook Access**: Ability to set up window focus event hooks
3. **Process Information**: Ability to retrieve process details

### Common Issues

- **Antivirus Software**: May block window hooks
- **UAC Restrictions**: Some features may require elevated privileges
- **Windows Version**: Requires Windows 10 or later for full functionality

### Automatic Setup

Run the setup script to check your configuration:

```powershell
# From your Flutter project root
.\docs\platform-setup\setup_permissions.ps1
```

### How Windows Focus Tracking Works

The Windows implementation uses:

1. **WinEvent Hooks**: `SetWinEventHook` with `EVENT_SYSTEM_FOREGROUND` to detect window focus changes
2. **Process Information**: `GetWindowThreadProcessId` and `OpenProcess` to get application details
3. **Window Information**: `GetWindowText` and `GetForegroundWindow` for window titles and focus state

### Configuration Files

#### Application Manifest (`runner.exe.manifest`)

The manifest includes:
- DPI awareness settings
- Windows 10/11 compatibility
- No special permissions required

#### CMake Configuration (`CMakeLists.txt`)

The build configuration includes:
- Required Windows libraries (`dwmapi.lib`)
- Flutter integration
- Standard build settings

### Troubleshooting

If focus tracking doesn't work:

1. **Check permissions**: Use the "Diagnostics" button in the app to see detailed permission status
2. **Run as Administrator**: Some features may require elevated privileges
3. **Check antivirus**: Some antivirus software may block window hooks
4. **Check Windows version**: Ensure you're running Windows 10 or later
5. **Verify build**: Ensure the app was built correctly

#### Permission Status in Diagnostics

The app provides detailed permission information:
- `hasPermissions`: Overall permission status
- `hasWindowAccess`: Can access window information
- `hasHookAccess`: Can set up event hooks

### Testing the App

1. **Build the project**:
   ```bash
   flutter build windows
   ```

2. **Run the app**:
   ```bash
   flutter run -d windows
   ```

3. **Test focus tracking**:
   - Click "Start Tracking" in the app
   - Switch between different applications
   - Check that focus events are displayed

### Development vs Production

- **Development**: No special configuration required
- **Production**: Consider code signing for distribution
- **Security**: The app doesn't require elevated privileges for basic functionality

### Windows-Specific Features

- **Browser Tab Detection**: Extracts tab information from browser window titles
- **Process Information**: Gets detailed process information including version and path
- **System Apps**: Can optionally include or exclude system applications

### Performance Considerations

- **Event Hooks**: Minimal performance impact from window focus monitoring
- **Memory Usage**: Efficient process information retrieval
- **CPU Usage**: Low overhead for focus tracking

The Windows implementation is designed to be lightweight and efficient while providing comprehensive focus tracking capabilities. 