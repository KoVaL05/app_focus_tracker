#!/bin/bash

echo "Setting up macOS app for accessibility permissions..."

# Check if we're in a Flutter project with macOS support
if [ ! -f "macos/Runner.xcodeproj/project.pbxproj" ]; then
    echo "Error: Please run this script from a Flutter project root with macOS support"
    echo "Make sure you have run 'flutter create --platforms=macos .' or similar"
    exit 1
fi

echo "✓ Found Flutter macOS project"

# Check if Info.plist has the accessibility usage description
if grep -q "NSAccessibilityUsageDescription" "macos/Runner/Info.plist"; then
    echo "✓ Accessibility usage description already present in Info.plist"
else
    echo "✗ Accessibility usage description missing from Info.plist"
fi

# Check if entitlements have app sandbox disabled
if grep -A1 "com.apple.security.app-sandbox" "macos/Runner/DebugProfile.entitlements" | grep -q "false"; then
    echo "✓ App sandbox disabled in DebugProfile.entitlements"
else
    echo "✗ App sandbox not disabled in DebugProfile.entitlements"
fi

if grep -A1 "com.apple.security.app-sandbox" "macos/Runner/Release.entitlements" | grep -q "false"; then
    echo "✓ App sandbox disabled in Release.entitlements"
else
    echo "✗ App sandbox not disabled in Release.entitlements"
fi

echo ""
echo "To ensure the app appears in System Preferences:"
echo "1. Clean and rebuild the project: flutter clean && flutter pub get"
echo "2. Run the app: flutter run -d macos"
echo "3. Add the plugin to your pubspec.yaml:"
echo "   dependencies:"
echo "     app_focus_tracker: ^0.0.1"
echo "3. When prompted, grant accessibility permissions"
echo "4. If the app doesn't appear in System Preferences, try:"
echo "   - Restarting the app"
echo "   - Restarting your Mac"
echo "   - Running the app from Xcode instead of Flutter"
echo ""
echo "Note: The app must be signed with a valid developer certificate to appear in System Preferences." 