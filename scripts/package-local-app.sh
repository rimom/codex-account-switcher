#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
RESOURCE_BUNDLE="CodexAccountSwitcher_CodexAccountSwitcher.bundle"
APP_ICON="$PROJECT_DIR/assets/AppIcon.icns"
APP_VERSION=${RELEASE_VERSION:-0.1.10}
CODESIGN_IDENTITY=${CODESIGN_IDENTITY:--}
CODEX_BACKEND_BINARY=${CODEX_BACKEND_BINARY:-}
CODEX_CODE_MODE_HOST_BINARY=${CODEX_CODE_MODE_HOST_BINARY:-}

if [[ -n "$CODEX_BACKEND_BINARY" ]]; then
    if [[ ! -x "$CODEX_BACKEND_BINARY" ]]; then
        echo "CODEX_BACKEND_BINARY is not an executable file: $CODEX_BACKEND_BINARY" >&2
        exit 1
    fi
    if [[ ! -x "$CODEX_CODE_MODE_HOST_BINARY" ]]; then
        echo "CODEX_CODE_MODE_HOST_BINARY is required and must be executable when packaging a Codex backend." >&2
        exit 1
    fi
elif [[ -n "$CODEX_CODE_MODE_HOST_BINARY" ]]; then
    echo "CODEX_BACKEND_BINARY is required when CODEX_CODE_MODE_HOST_BINARY is set." >&2
    exit 1
fi

cd "$PROJECT_DIR"
BUILD_ARGUMENTS=(-c release)
if [[ -n "${SWIFT_BUILD_ARCH:-}" ]]; then
    BUILD_ARGUMENTS+=(--arch "$SWIFT_BUILD_ARCH")
fi

swift build "${BUILD_ARGUMENTS[@]}"
BUILD_DIR=$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)
APP_DIR="$BUILD_DIR/Codex Account Switcher.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

rm -rf "$APP_DIR"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
ditto "$BUILD_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"
cp "$BUILD_DIR/CodexAccountSwitcher" "$MACOS_DIR/CodexAccountSwitcher"
chmod 0755 "$MACOS_DIR/CodexAccountSwitcher"
if [[ -n "$CODEX_BACKEND_BINARY" ]]; then
    cp "$CODEX_BACKEND_BINARY" "$MACOS_DIR/codex"
    cp "$CODEX_CODE_MODE_HOST_BINARY" "$MACOS_DIR/codex-code-mode-host"
    chmod 0755 "$MACOS_DIR/codex"
    chmod 0755 "$MACOS_DIR/codex-code-mode-host"
fi
ditto "$BUILD_DIR/$RESOURCE_BUNDLE" "$RESOURCES_DIR/$RESOURCE_BUNDLE"
ditto "$APP_ICON" "$RESOURCES_DIR/AppIcon.icns"
cp "$PROJECT_DIR/LICENSE" "$RESOURCES_DIR/LICENSE.txt"

/usr/bin/plutil -create xml1 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleDevelopmentRegion -string en "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string "Codex Account Switcher" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string CodexAccountSwitcher "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string com.liuzhao.codex-account-switcher "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleIconFile -string AppIcon "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleName -string "Codex Account Switcher" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string "$APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 14.0 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert LSUIElement -bool true "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert SUFeedURL -string "https://github.com/liuzhao1225/codex-account-switcher/releases/latest/download/appcast.xml" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert SUPublicEDKey -string "$(cat "$SCRIPT_DIR/sparkle-public-key.txt")" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert SUEnableAutomaticChecks -bool true "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert SUScheduledCheckInterval -integer 3600 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert SUAutomaticallyUpdate -bool false "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert SUAllowsAutomaticUpdates -bool false "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert SUEnableSystemProfiling -bool false "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert SUVerifyUpdateBeforeExtraction -bool true "$CONTENTS_DIR/Info.plist"

# Sign nested executable bundles from the inside out before signing the host app.
sparkle_version="$FRAMEWORKS_DIR/Sparkle.framework/Versions/B"
for component in \
    "$sparkle_version/XPCServices/Downloader.xpc" \
    "$sparkle_version/XPCServices/Installer.xpc" \
    "$sparkle_version/Autoupdate" \
    "$sparkle_version/Updater.app" \
    "$FRAMEWORKS_DIR/Sparkle.framework"; do
    if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
        codesign --force --sign - "$component"
    else
        codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$component"
    fi
done

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP_DIR"
else
    codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
