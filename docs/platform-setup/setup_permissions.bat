@echo off
echo Setting up Windows app for focus tracking permissions...

REM Check if we're in a Flutter project with Windows support
if not exist "windows\runner\CMakeLists.txt" (
    echo Error: Please run this script from a Flutter project root with Windows support
    echo Make sure you have run 'flutter create --platforms=windows .' or similar
    pause
    exit /b 1
)

echo ✓ Found Flutter Windows project

REM Check if the manifest file exists
if exist "windows\runner\runner.exe.manifest" (
    echo ✓ Application manifest found
) else (
    echo ✗ Application manifest missing
)

REM Check if the main.cpp file exists
if exist "windows\runner\main.cpp" (
    echo ✓ Main application file found
) else (
    echo ✗ Main application file missing
)

REM Check Windows version
for /f "tokens=4-5 delims=. " %%i in ('ver') do set VERSION=%%i.%%j
echo ✓ Windows version detected

echo.
echo Windows Configuration Summary:
echo ==============================
echo • Windows generally doesn't require special permissions for focus tracking
echo • The app uses Windows API hooks to monitor foreground window changes
echo • No additional configuration files are required
echo • The app should work without elevated privileges
echo.
echo To test the app:
echo 1. Add the plugin to your pubspec.yaml:
echo    dependencies:
echo      app_focus_tracker: ^0.0.1
echo 2. Build the project: flutter build windows
echo 3. Run the app: flutter run -d windows
echo 4. Test focus tracking by switching between applications
echo.
echo Note: If you encounter permission issues, try running the app as Administrator
echo.
pause 