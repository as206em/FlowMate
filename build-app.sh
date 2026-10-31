#!/bin/bash

# Build the FlowMate app with icon
set -e

# Settings (environment variables; the defaults are what a local build uses):
#   VERSION            marketing version (default 1.1.0; the release workflow passes the tag)
#   BUILD_NUMBER       CFBundleVersion, must grow with every release (default: timestamp)
#   SIGN_IDENTITY      codesign identity (default: the Developer ID in the keychain, else "FlowMate Dev Certificate")
#   FEED_URL           Sparkle appcast URL
#   SPARKLE_PUBLIC_KEY Sparkle EdDSA public key (default: Resources/SparklePublicKey.txt)
#   UNIVERSAL=1        build for arm64 and x86_64
#   NO_LAUNCH=1        don't quit or open the app (CI)
# Signing identity: the Developer ID in the keychain when there is one (stable across builds, so
# macOS keeps the Accessibility permission), else the local dev certificate.
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
    SIGN_IDENTITY="${SIGN_IDENTITY:-FlowMate Dev Certificate}"
fi
FEED_URL="${FEED_URL:-https://as206em.github.io/FlowMate/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-$(cat Resources/SparklePublicKey.txt 2>/dev/null || true)}"

if [ -z "$NO_LAUNCH" ]; then
    # Quit any running FlowMate (exact process name only, so other processes are never matched)
    echo "Stopping any running instances of FlowMate..."
    pkill -x FlowMate 2>/dev/null || true
fi

# Get version information
VERSION="${VERSION:-1.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +"%Y%m%d%H%M")}"
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

echo "Building FlowMate v$VERSION (Build $BUILD_NUMBER)"
echo "Git: $GIT_HASH | Date: $BUILD_DATE"

# Build the release binary
echo "Building release binary..."
BUILD_FLAGS=(-c release)
if [ -n "$UNIVERSAL" ]; then BUILD_FLAGS+=(--arch arm64 --arch x86_64); fi
swift build "${BUILD_FLAGS[@]}"
BIN_DIR=$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)

# Create app bundle structure
echo "Creating app bundle..."
APP_BUNDLE="FlowMate.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Copy binary
cp "$BIN_DIR/FlowMate" "$APP_BUNDLE/Contents/MacOS/"

# Embed Sparkle (ditto keeps the framework's symlinks) and let the binary find it
SPARKLE_FRAMEWORK=$(find .build/artifacts -type d -name Sparkle.framework -path "*macos*" | head -1)
if [ -z "$SPARKLE_FRAMEWORK" ]; then echo "Sparkle.framework not found - run 'swift package resolve'"; exit 1; fi
ditto "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/FlowMate" 2>/dev/null || true

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
    <key>SUFeedURL</key>
    <string>$FEED_URL</string>
    <key>SUPublicEDKey</key>
    <string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
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

if [ -z "$SPARKLE_PUBLIC_KEY" ]; then
    echo "Warning: no Sparkle public key (Resources/SparklePublicKey.txt) - this build can't update itself"
fi

# Codesign inside-out (no --deep): Sparkle's helpers, then the framework, then the app.
# Developer ID builds also get the hardened runtime and a secure timestamp, as notarization needs.
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
case "$SIGN_IDENTITY" in "Developer ID"*) SIGN_FLAGS+=(--options runtime --timestamp) ;; esac
SPARKLE_DEST="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
echo "Codesigning with: $SIGN_IDENTITY"
for item in "$SPARKLE_DEST"/XPCServices/*.xpc "$SPARKLE_DEST/Autoupdate" "$SPARKLE_DEST/Updater.app" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"; do
    [ -e "$item" ] && codesign "${SIGN_FLAGS[@]}" "$item"
done
codesign "${SIGN_FLAGS[@]}" --entitlements entitlements.plist "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

# Verify the entitlements
echo "Verifying entitlements..."
codesign -dv --entitlements :- "$APP_BUNDLE"

# Open the app after successful build
if [ -z "$NO_LAUNCH" ]; then
    echo "Starting FlowMate..."
    open "$APP_BUNDLE"
fi

echo "Build completed successfully!"
