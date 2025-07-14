# Windows Setup Script for App Focus Tracker
# This script checks the Windows configuration for the app focus tracker

Write-Host "Setting up Windows app for focus tracking permissions..." -ForegroundColor Green

# Check if we're in a Flutter project with Windows support
if (-not (Test-Path "windows\runner\CMakeLists.txt")) {
    Write-Host "Error: Please run this script from a Flutter project root with Windows support" -ForegroundColor Red
    Write-Host "Make sure you have run 'flutter create --platforms=windows .' or similar" -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Found Flutter Windows project" -ForegroundColor Green

# Check if the manifest file exists
if (Test-Path "windows\runner\runner.exe.manifest") {
    Write-Host "✓ Application manifest found" -ForegroundColor Green
} else {
    Write-Host "✗ Application manifest missing" -ForegroundColor Red
}

# Check if the main.cpp file exists
if (Test-Path "windows\runner\main.cpp") {
    Write-Host "✓ Main application file found" -ForegroundColor Green
} else {
    Write-Host "✗ Main application file missing" -ForegroundColor Red
}

# Check Windows version compatibility
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
$windowsVersion = [System.Version]$osInfo.Version
Write-Host "✓ Windows version: $($osInfo.Caption) ($($osInfo.Version))" -ForegroundColor Green

# Check if running as administrator (optional for development)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if ($isAdmin) {
    Write-Host "✓ Running as Administrator" -ForegroundColor Green
} else {
    Write-Host "ℹ Running as regular user (may need elevation for some features)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Windows Configuration Summary:" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "• Windows generally doesn't require special permissions for focus tracking" -ForegroundColor White
Write-Host "• The app uses Windows API hooks to monitor foreground window changes" -ForegroundColor White
Write-Host "• No additional configuration files are required" -ForegroundColor White
Write-Host "• The app should work without elevated privileges" -ForegroundColor White
Write-Host ""
Write-Host "To test the app:" -ForegroundColor Yellow
Write-Host "1. Add the plugin to your pubspec.yaml:" -ForegroundColor White
Write-Host "   dependencies:" -ForegroundColor White
Write-Host "     app_focus_tracker: ^0.0.1" -ForegroundColor White
Write-Host "2. Build the project: flutter build windows" -ForegroundColor White
Write-Host "3. Run the app: flutter run -d windows" -ForegroundColor White
Write-Host "4. Test focus tracking by switching between applications" -ForegroundColor White
Write-Host ""
Write-Host "Note: If you encounter permission issues, try running the app as Administrator" -ForegroundColor Yellow 