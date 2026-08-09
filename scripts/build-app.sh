#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
SWIFTPM_SCRATCH_PATH="${STICKS3_SWIFTPM_SCRATCH_PATH:-$PROJECT_DIR/.build}"

# Keep developer and synchronized-workspace paths out of public Mach-O files.
# C/C++ __FILE__ strings otherwise retain the absolute checkout directory even
# in an optimized release build.
swift build -c release --scratch-path "$SWIFTPM_SCRATCH_PATH" \
    -Xcc "-ffile-prefix-map=$PROJECT_DIR=." \
    -Xcc "-fdebug-prefix-map=$PROJECT_DIR=." \
    -Xswiftc -file-prefix-map \
    -Xswiftc "$PROJECT_DIR=."

APP_DIR="$PROJECT_DIR/build/StickS3 固件实验台.app"
mkdir -p "$PROJECT_DIR/build"
STAGE_ROOT="$(mktemp -d "$PROJECT_DIR/build/app-stage.XXXXXX")"
trap '[[ -n "${STAGE_ROOT:-}" && "$STAGE_ROOT" == "$PROJECT_DIR"/build/app-stage.* ]] && /bin/rm -rf -- "$STAGE_ROOT"' EXIT
STAGED_APP="$STAGE_ROOT/StickS3 固件实验台.app"
ICONSET_DIR="$STAGE_ROOT/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
sips -z 16 16     "$PROJECT_DIR/Resources/AppIcon-1024.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32     "$PROJECT_DIR/Resources/AppIcon-1024.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$PROJECT_DIR/Resources/AppIcon-1024.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64     "$PROJECT_DIR/Resources/AppIcon-1024.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$PROJECT_DIR/Resources/AppIcon-1024.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256   "$PROJECT_DIR/Resources/AppIcon-1024.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$PROJECT_DIR/Resources/AppIcon-1024.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512   "$PROJECT_DIR/Resources/AppIcon-1024.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$PROJECT_DIR/Resources/AppIcon-1024.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$PROJECT_DIR/Resources/AppIcon-1024.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$STAGE_ROOT/AppIcon.icns"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$SWIFTPM_SCRATCH_PATH/release/StickS3Simulator" "$STAGED_APP/Contents/MacOS/StickS3Simulator"
cp "$PROJECT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$STAGE_ROOT/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Resources/SplashAvatar.png" "$STAGED_APP/Contents/Resources/SplashAvatar.png"
cp -R "$PROJECT_DIR/Resources/VirtualBoard" "$STAGED_APP/Contents/Resources/VirtualBoard"
mkdir -p "$STAGED_APP/Contents/Resources/Licenses"
cp "$PROJECT_DIR/LICENSE" "$STAGED_APP/Contents/Resources/Licenses/StickS3-Firmware-Lab-LICENSE"
cp "$PROJECT_DIR/NOTICE" "$STAGED_APP/Contents/Resources/Licenses/NOTICE"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$STAGED_APP/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"
cp -R "$PROJECT_DIR/Vendor/Licenses/." "$STAGED_APP/Contents/Resources/Licenses/"
chmod 755 "$STAGED_APP/Contents/MacOS/StickS3Simulator"

# Remove local object-file records after prefix mapping and before signing.
# These records are not needed at runtime and otherwise expose the checkout
# path through the final release executable.
strip -S -x "$STAGED_APP/Contents/MacOS/StickS3Simulator"

"$PROJECT_DIR/scripts/bundle-qemu.sh" "$STAGED_APP/Contents/Resources/Emulation"

FINGERPRINT_TOOL="$SWIFTPM_SCRATCH_PATH/release/FirmwareFingerprintTool"
for runtime in breakout hourglass hourglassLiquid codex agentHub; do
    vendor_runtime="$runtime"
    [[ "$runtime" == "hourglassLiquid" ]] && vendor_runtime="liquid"
    firmware_root="$PROJECT_DIR/Vendor/Firmware/$vendor_runtime"
    if [[ "${SIMULATOR_FIRMWARE_RUNTIME:-}" == "$runtime" && -n "${SIMULATOR_FIRMWARE_ROOT:-}" ]]; then
        firmware_root="$SIMULATOR_FIRMWARE_ROOT"
    fi
    fingerprint="$($FINGERPRINT_TOOL "$runtime" "$firmware_root")"
    /usr/libexec/PlistBuddy -c "Add :SimulatorFingerprint_$runtime string $fingerprint" \
        "$STAGED_APP/Contents/Info.plist"
done

# 本机构建默认使用可复现的 ad-hoc 签名；获授权的发布者可显式传入身份。
SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
echo "REBUILD-STEP:SIGNING"
codesign --force --deep --timestamp=none --sign "$SIGNING_IDENTITY" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

if [[ -e "$APP_DIR" ]]; then
    [[ "$APP_DIR" == "$PROJECT_DIR/build/StickS3 固件实验台.app" ]] || exit 70
    /bin/rm -rf -- "$APP_DIR"
fi
mv "$STAGED_APP" "$APP_DIR"

SUPPORT_DIR="$HOME/Library/Application Support/Stick S3 Firmware Simulator"
mkdir -p "$SUPPORT_DIR"
print -r -- "$PROJECT_DIR" > "$SUPPORT_DIR/source-root.txt"
echo "$APP_DIR"
