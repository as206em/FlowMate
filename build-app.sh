#!/bin/bash

# Build the FlowMate app with icon
set -e

# Kill any running instances of the app before building
echo "Stopping any running instances of FlowMate..."
pkill -f "FlowMate" 2>/dev/null || true

# Get version information
VERSION="1.1.0"
BUILD_NUMBER=$(date +"%Y%m%d%H%M")
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

echo "Building FlowMate v$VERSION (Build $BUILD_NUMBER)"
echo "Git: $GIT_HASH | Date: $BUILD_DATE"

# Build the release binary
echo "Building release binary..."
swift build -c release

# Create app bundle structure
echo "Creating app bundle..."
APP_BUNDLE="FlowMate.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp ".build/release/FlowMate" "$APP_BUNDLE/Contents/MacOS/"

# Copy icon
cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || echo "Icon not found, continuing without icon"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FlowMate</string>
    <key>CFBundleIdentifier</key>
    <string>com.asem-mkl.FlowMate</string>
    <key>CFBundleName</key>
    <string>FlowMate</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 asem-mkl. All rights reserved.</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>GitCommitHash</key>
    <string>$GIT_HASH</string>
    <key>BuildDate</key>
    <string>$BUILD_DATE</string>
</dict>
</plist>
EOF

echo "App bundle created: $APP_BUNDLE"

# Create entitlements file for codesigning
echo "Creating entitlements file..."
cat > entitlements.plist << 'ENT_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <key>com.apple.security.device.input-monitoring</key>
    <true/>
</dict>
</plist>
ENT_EOF

# Codesign the app with entitlements
echo "Codesigning app with entitlements..."
codesign --force --deep --sign "FlowMate Dev Certificate" --entitlements entitlements.plist "$APP_BUNDLE"

# Verify the entitlements
echo "Verifying entitlements..."
codesign -dv --entitlements :- "$APP_BUNDLE"

# Open the app after successful build
echo "Starting FlowMate..."
open "$APP_BUNDLE"

echo "Build completed successfully!"
