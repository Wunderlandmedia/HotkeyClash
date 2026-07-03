#!/bin/bash
set -euo pipefail

# HotkeyClash release build script
# Produces a notarized .app, then packages as both DMG and ZIP.
#
# Prerequisites:
#   xcrun notarytool store-credentials "HotkeyClash" \
#     --apple-id "info@wunderlandmedia.com" \
#     --team-id "FBT967MAS7" \
#     --password "your-app-specific-password"
#
# Usage:
#   ./scripts/build-release.sh                    # uses version from Xcode project
#   ./scripts/build-release.sh --version 0.2.0    # override version
#   ./scripts/build-release.sh --skip-notarize    # skip notarization (local testing)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="HotkeyClash"
APP_NAME="HotkeyClash"
BUNDLE_ID="com.hotkeyclash.app"
KEYCHAIN_PROFILE="HotkeyClash"

BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_DIR="$BUILD_DIR/dmg"
OUTPUT_DIR="$BUILD_DIR/release"

SKIP_NOTARIZE=false
VERSION_OVERRIDE=""

# --- Parse arguments ---

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION_OVERRIDE="$2"
            shift 2
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--version X.Y.Z] [--skip-notarize]"
            echo ""
            echo "Options:"
            echo "  --version X.Y.Z    Override marketing version (default: from Xcode project)"
            echo "  --skip-notarize    Skip notarization (for local testing)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- Environment checks ---

check_requirements() {
    if ! command -v xcodebuild &>/dev/null; then
        echo "Error: xcodebuild not found. Install Xcode."
        exit 1
    fi

    if ! command -v xcrun &>/dev/null; then
        echo "Error: xcrun not found. Install Xcode Command Line Tools."
        exit 1
    fi

    if [[ "$SKIP_NOTARIZE" == false ]]; then
        if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null; then
            echo "Warning: Keychain profile '$KEYCHAIN_PROFILE' not found."
            echo "  Run: xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\"
            echo "         --apple-id \"info@wunderlandmedia.com\" \\"
            echo "         --team-id \"FBT967MAS7\" \\"
            echo "         --password \"your-app-specific-password\""
            echo ""
            echo "  Or use --skip-notarize for local testing."
            echo ""
            read -rp "Continue without notarization? [y/N] " answer
            if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
                exit 1
            fi
            SKIP_NOTARIZE=true
        fi
    fi
}

# --- Helpers ---

log() {
    echo "==> $1"
}

get_version() {
    if [[ -n "$VERSION_OVERRIDE" ]]; then
        echo "$VERSION_OVERRIDE"
    else
        xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
            -scheme "$SCHEME" \
            -showBuildSettings 2>/dev/null \
            | grep 'MARKETING_VERSION' \
            | head -1 \
            | awk '{print $NF}'
    fi
}

clean_build() {
    log "Cleaning previous build artifacts..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$OUTPUT_DIR"
}

# --- Build ---

archive() {
    log "Archiving $APP_NAME..."
    xcodebuild archive \
        -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -quiet \
        CODE_SIGN_STYLE=Automatic \
        ${VERSION_OVERRIDE:+MARKETING_VERSION="$VERSION_OVERRIDE"}
}

export_app() {
    log "Exporting app from archive..."
    mkdir -p "$EXPORT_DIR"

    if [[ "$SKIP_NOTARIZE" == true ]]; then
        cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_DIR/"
    else
        cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

        xcodebuild -exportArchive \
            -archivePath "$ARCHIVE_PATH" \
            -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
            -exportPath "$EXPORT_DIR" \
            -quiet
    fi
}

# --- Notarize ---

notarize() {
    local app_path="$EXPORT_DIR/$APP_NAME.app"

    if [[ "$SKIP_NOTARIZE" == true ]]; then
        log "Skipping notarization."
        return
    fi

    log "Creating ZIP for notarization submission..."
    local notarize_zip="$BUILD_DIR/$APP_NAME-notarize.zip"
    ditto -c -k --keepParent "$app_path" "$notarize_zip"

    log "Submitting for notarization..."
    xcrun notarytool submit "$notarize_zip" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    log "Stapling notarization ticket..."
    xcrun stapler staple "$app_path"

    rm -f "$notarize_zip"
}

# --- Package DMG ---

create_dmg() {
    local version="$1"
    local app_path="$EXPORT_DIR/$APP_NAME.app"
    local dmg_name="$APP_NAME-$version.dmg"
    local dmg_path="$OUTPUT_DIR/$dmg_name"

    log "Creating DMG: $dmg_name"

    # Detach leftovers from a previous failed run first. A stale volume named
    # "HotkeyClash" makes the fresh image mount as "HotkeyClash 1", and the
    # Finder styling below then talks to the wrong disk and dies.
    for vol in "/Volumes/$APP_NAME" "/Volumes/$APP_NAME "[0-9]*; do
        if [[ -d "$vol" ]]; then
            log "Detaching stale volume: $vol"
            hdiutil detach "$vol" -force -quiet || true
        fi
    done

    mkdir -p "$DMG_DIR"
    rm -rf "$DMG_DIR/"*

    cp -R "$app_path" "$DMG_DIR/"
    ln -s /Applications "$DMG_DIR/Applications"

    local dmg_bg="$PROJECT_DIR/scripts/dmg-background.png"
    if [[ -f "$dmg_bg" ]]; then
        mkdir -p "$DMG_DIR/.background"
        cp "$dmg_bg" "$DMG_DIR/.background/background.png"
    fi

    local tmp_dmg="$BUILD_DIR/$APP_NAME-tmp.dmg"

    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_DIR" \
        -ov \
        -format UDRW \
        "$tmp_dmg"

    local device
    device=$(hdiutil attach -readwrite -noverify "$tmp_dmg" | grep '/Volumes/' | awk '{print $1}')
    local mount_point="/Volumes/$APP_NAME"

    # The Finder styling is cosmetic; a failure here (usually missing Automation
    # permission for the terminal) must not abort the release build.
    if [[ -f "$dmg_bg" ]]; then
        osascript <<APPLESCRIPT || log "WARNING: Finder styling failed; continuing with default DMG layout"
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 640, 440}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {140, 180}
        set position of item "Applications" of container window to {400, 180}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT
    else
        osascript <<APPLESCRIPT || log "WARNING: Finder styling failed; continuing with default DMG layout"
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 640, 440}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set position of item "$APP_NAME.app" of container window to {140, 180}
        set position of item "Applications" of container window to {400, 180}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT
    fi

    sync
    # Finder can still hold the volume for a beat after the styling window closes.
    hdiutil detach "$device" -quiet || { sleep 2; hdiutil detach "$device" -force -quiet; }
    hdiutil convert "$tmp_dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg_path"
    rm -f "$tmp_dmg"

    if [[ "$SKIP_NOTARIZE" == false ]]; then
        log "Notarizing DMG..."
        xcrun notarytool submit "$dmg_path" \
            --keychain-profile "$KEYCHAIN_PROFILE" \
            --wait
        xcrun stapler staple "$dmg_path"
    fi
}

# --- Package ZIP ---

create_zip() {
    local version="$1"
    local app_path="$EXPORT_DIR/$APP_NAME.app"
    local zip_name="$APP_NAME-$version.zip"
    local zip_path="$OUTPUT_DIR/$zip_name"

    log "Creating ZIP: $zip_name"
    cd "$EXPORT_DIR"
    ditto -c -k --keepParent "$APP_NAME.app" "$zip_path"
    cd "$PROJECT_DIR"
}

# --- Checksums ---

create_checksums() {
    log "Generating checksums..."
    cd "$OUTPUT_DIR"
    shasum -a 256 *.dmg *.zip > SHA256SUMS.txt
    cat SHA256SUMS.txt
    cd "$PROJECT_DIR"
}

# --- Main ---

main() {
    check_requirements

    local version
    version=$(get_version)

    if [[ -z "$version" ]]; then
        echo "Error: Could not determine version."
        exit 1
    fi

    log "Building $APP_NAME v$version"
    echo ""

    clean_build
    archive
    export_app
    notarize
    create_dmg "$version"
    create_zip "$version"
    create_checksums

    echo ""
    log "Release artifacts:"
    ls -lh "$OUTPUT_DIR/"
    echo ""
    log "Done. Artifacts are in $OUTPUT_DIR/"
}

main
