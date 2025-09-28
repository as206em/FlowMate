#!/bin/bash

# Build the Proofreader app with icon - Development & Production versions
set -e

# Get version information
VERSION="1.1.0"
BUILD_NUMBER=$(date +"%Y%m%d%H%M")
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

echo "Building Proofreader v$VERSION (Build $BUILD_NUMBER)"
echo "Git: $GIT_HASH | Date: $BUILD_DATE"

# Build the release binary
echo "Building release binary..."
swift build -c release

# Check if we want to install to Applications (development mode) or create local bundle
if [[ "$1" == "--install" || "$1" == "-i" ]]; then
    # Development mode: Install to Applications folder
    APP_BUNDLE="/Applications/Proofreader.app"
    echo "Installing to Applications folder (development mode)..."
    
    # Create fresh app bundle in Applications
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"
    
    # Copy binary
    cp ".build/release/Proofreader" "$APP_BUNDLE/Contents/MacOS/"
    
    # Copy icon
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || echo "Icon not found, continuing without icon"
    
    # Create Info.plist
    cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Proofreader</string>
    <key>CFBundleIdentifier</key>
    <string>com.gequ.Proofreader</string>
    <key>CFBundleName</key>
    <string>Proofreader</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 gequ. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>GitCommitHash</key>
    <string>$GIT_HASH</string>
    <key>BuildDate</key>
    <string>$BUILD_DATE</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>This app needs access to Apple Events to function properly.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>This app needs to monitor keyboard input to trigger the proofreading shortcut.</string>
</dict>
</plist>
EOF

    echo "App bundle installed to: $APP_BUNDLE"
    echo "First time setup: Go to System Settings > Security & Privacy > Privacy > Input Monitoring and Accessibility, then add the app"
    echo "After permissions are granted, you can update the app by running this script again without losing permissions"
    
else
    # Regular mode: Create local bundle
    echo "Creating local app bundle..."
    APP_BUNDLE="Proofreader.app"
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    # Copy binary
    cp ".build/release/Proofreader" "$APP_BUNDLE/Contents/MacOS/"

    # Copy icon
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || echo "Icon not found, continuing without icon"

    # Create Info.plist
    cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Proofreader</string>
    <key>CFBundleIdentifier</key>
    <string>com.gequ.Proofreader</string>
    <key>CFBundleName</key>
    <string>Proofreader</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 gequ. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>GitCommitHash</key>
    <string>$GIT_HASH</string>
    <key>BuildDate</key>
    <string>$BUILD_DATE</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>This app needs access to Apple Events to function properly.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>This app needs to monitor keyboard input to trigger the proofreading shortcut.</string>
</dict>
</plist>
EOF

    echo "App bundle created: $APP_BUNDLE"
    echo "To install for development (with persistent permissions), run: ./build-app.sh --install"
fi
