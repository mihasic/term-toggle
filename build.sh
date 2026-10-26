#!/bin/bash
#
# Builds TermToggle.app.
#
#   ./build.sh              build, sign, install to ~/Applications, launch
#   ./build.sh --no-install build only (leaves build/TermToggle.app)
#   ./build.sh --dmg        build only, then package build/TermToggle-<version>.dmg
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TermToggle"
BUNDLE_ID="com.mihasic.term-toggle"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
DEPLOYMENT_TARGET="13.0"
VERSION="$(tr -d '[:space:]' < VERSION)"

INSTALL=1
DMG=0
case "${1:-}" in
	--no-install) INSTALL=0 ;;
	--dmg) INSTALL=0; DMG=1 ;;
	"") ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
esac

echo "==> Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling $APP_NAME $VERSION (arm64, Swift 6, target macOS $DEPLOYMENT_TARGET)"
# Apple Silicon only: macOS 26 was the last release for Intel Macs.
swiftc -O -swift-version 6 \
	-target "arm64-apple-macos${DEPLOYMENT_TARGET}" \
	-framework AppKit -framework Carbon -framework ServiceManagement \
	-o "$APP/Contents/MacOS/$APP_NAME" \
	Sources/main.swift

echo "==> Assembling bundle"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# ./VERSION is the single source of truth; the plist only carries a default.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

echo "==> Ad-hoc signing"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"

if [[ "$DMG" == "1" ]]; then
	DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
	echo "==> Packaging $DMG_PATH"
	STAGE="$(mktemp -d)"
	trap 'rm -rf "$STAGE"' EXIT
	cp -R "$APP" "$STAGE/$APP_NAME.app"
	ln -s /Applications "$STAGE/Applications"
	hdiutil create -quiet -volname "$APP_NAME $VERSION" \
		-srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH"
	echo
	echo "Done: $DMG_PATH"
	shasum -a 256 "$DMG_PATH"
	exit 0
fi

if [[ "$INSTALL" == "1" ]]; then
	if [[ -d "/Applications/$APP_NAME.app" ]]; then
		echo "!!  /Applications/$APP_NAME.app also exists (Homebrew cask)."
		echo "!!  Two copies fight over the hotkey and the loser fails silently."
		echo "!!  Run: brew uninstall --cask term-toggle"
	fi
	echo "==> Installing to $INSTALL_DIR"
	mkdir -p "$INSTALL_DIR"
	# Stop any running copy so the replaced binary is the one relaunched.
	pkill -x "$APP_NAME" 2>/dev/null || true
	rm -rf "$INSTALL_DIR/$APP_NAME.app"
	cp -R "$APP" "$INSTALL_DIR/$APP_NAME.app"
	echo "==> Launching"
	# `env -i` so launchd supplies the same environment as a Finder/login launch
	# instead of pinning this shell's into every terminal. Absolute path: no PATH.
	env -i /usr/bin/open "$INSTALL_DIR/$APP_NAME.app"
	echo
	# Prints the resolved target app and chord, so a stale preference is visible.
	"$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" --config
	echo "Registered as a login item (approve in System Settings > General > Login Items if prompted)."
else
	echo
	echo "Done: $APP (not installed)."
fi
