# Windows Deadlock Fix Testing Guide

This directory contains tests specifically designed to verify that the Windows deadlock fixes are working correctly in release builds.

## Background

The original bug caused intermittent application crashes in Windows release builds due to a deadlock between:
1. Background threads generating focus events and holding mutexes
2. UI thread calling `getRunningApplications()` which blocked while also needing those same mutexes
3. DirectWrite font system interactions that were affected by the blocking operations

## Test Structure

### Automated Tests
- **`windows_deadlock_test.dart`** - Unit tests that simulate the deadlock conditions
- Run with: `flutter test test/platform_specific/windows_deadlock_test.dart`

### Manual Tests  
- **`windows_release_deadlock_test.dart`** - Manual test for real release builds
- Must be run in an actual Windows release build to verify real-world conditions

## Running the Tests

### 1. Automated Testing (Development)
```bash
# Run all Windows deadlock tests
flutter test test/platform_specific/windows_deadlock_test.dart

# Run full test suite including deadlock tests
flutter test test/test_runner.dart

# Run with verbose output
flutter test --verbose test/platform_specific/windows_deadlock_test.dart
```

### 2. Manual Testing (Release Build)
```bash
# Build release version
flutter build windows --release

# Run the executable
./build/windows/runner/Release/your_app.exe

# Then within the app, execute the manual test:
# (This depends on your app's integration - you may need to add a test button)
```

### 3. Stress Testing
For thorough verification, run the stress tests multiple times:
```bash
# Run stress tests 10 times
for i in {1..10}; do
  echo "Stress test run $i"
  flutter test test/platform_specific/windows_deadlock_test.dart
done
```

## What the Tests Verify

### ✅ Fixed Behaviors
1. **Event Sink Mutex Safety**: Events are dispatched without holding mutexes while calling into Flutter
2. **Async Process Enumeration**: `getRunningApplications()` runs on background thread
3. **Reduced Privilege**: Uses `PROCESS_QUERY_LIMITED_INFORMATION` instead of full access
4. **Clean Error Handling**: Suppresses noisy access-denied errors
5. **Resource Cleanup**: Proper cleanup without deadlocks

### ❌ Original Problem Scenarios
1. **Mutex Deadlock**: Background thread holds mutex while UI thread waits
2. **UI Thread Blocking**: Heavy process enumeration blocking main thread
3. **DirectWrite Contention**: Font system locks conflicting with plugin locks
4. **Resource Leaks**: Improper cleanup causing subsequent issues

## Expected Results

### Passing Tests Should Show:
- ✅ All test groups complete without hanging
- ✅ Events are processed consistently
- ✅ Multiple concurrent `getRunningApplications()` calls succeed
- ✅ System remains responsive during stress conditions
- ✅ No freezes or crashes in release builds

### Warning Signs of Remaining Issues:
- ❌ Tests hang or timeout
- ❌ Release build freezes during heavy operations
- ❌ High CPU usage with no progress
- ❌ Access violation or memory errors

## Debugging Tips

### If Tests Still Fail:

1. **Check Native Code Changes**:
   - Verify `SendEventDirectly()` doesn't hold mutex during Flutter calls
   - Confirm `getRunningApplications()` runs async
   - Ensure `PROCESS_QUERY_LIMITED_INFORMATION` is used

2. **Monitor System Resources**:
   ```bash
   # Watch CPU and memory usage
   Get-Process -Name "your_app" | Format-Table Name, CPU, WorkingSet
   ```

3. **Enable Debug Logging**:
   - Add debug output in native code
   - Monitor for mutex contention patterns
   - Look for "Access denied" error flooding

4. **Use Windows Performance Tools**:
   - Process Monitor (ProcMon) for file/registry access
   - Performance Toolkit for detailed analysis
   - Application Verifier for memory issues

## Test Environment Notes

- **Windows Version**: Tested on Windows 10/11
- **Build Mode**: Issues only appear in release builds
- **Debugger Effect**: Attaching debugger changes timing and may mask issues
- **UAC/Permissions**: Some system processes will always be inaccessible

## Integration with CI/CD

Add to your CI pipeline:
```yaml
- name: Run Windows Deadlock Tests
  run: flutter test test/platform_specific/windows_deadlock_test.dart
  if: matrix.os == 'windows-latest'
  
- name: Build Windows Release
  run: flutter build windows --release
  if: matrix.os == 'windows-latest'
  
- name: Test Release Build (Manual verification required)
  run: echo "Manual testing required for release build verification"
  if: matrix.os == 'windows-latest'
```

## Contributing

When adding new features that might affect threading:
1. Run the deadlock tests before and after your changes
2. Add relevant test cases to `windows_deadlock_test.dart`
3. Test in release builds, not just debug
4. Consider mutex usage and blocking operations on UI thread 