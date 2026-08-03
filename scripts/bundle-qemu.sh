#!/bin/zsh
set -euo pipefail

DEST_DIR="${1:?destination Emulation directory is required}"
QEMU_SOURCE="${STICKS3_QEMU_PATH:-}"

if [[ -z "$QEMU_SOURCE" ]]; then
    candidates=("$HOME"/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa(N.om))
    (( ${#candidates[@]} > 0 )) && QEMU_SOURCE="$candidates[1]"
fi

if [[ -z "$QEMU_SOURCE" || ! -x "$QEMU_SOURCE" ]]; then
    print -u2 -- "QEMU not found; building app without the optional emulator runtime"
    exit 0
fi

QEMU_ROOT="${QEMU_SOURCE:h:h}"
mkdir -p "$DEST_DIR/bin" "$DEST_DIR/root" "$DEST_DIR/share/qemu"
cp "$QEMU_SOURCE" "$DEST_DIR/bin/qemu-system-xtensa"
cp "$QEMU_ROOT"/share/qemu/*.bin "$DEST_DIR/share/qemu/"
chmod 755 "$DEST_DIR/bin/qemu-system-xtensa"

# Espressif's macOS QEMU package currently references Homebrew libraries. Copy
# the complete transitive graph under an app-private virtual root. DYLD_ROOT_PATH
# resolves those original absolute paths without changing QEMU or SDL load
# commands; directly rewriting SDL2 causes LaunchServices startup hangs.
typeset -a pending
typeset -A visited
pending=("$QEMU_SOURCE")
while (( ${#pending[@]} > 0 )); do
    source_binary="$pending[1]"
    pending=("${pending[@]:1}")
    [[ -n "${visited[$source_binary]:-}" ]] && continue
    visited[$source_binary]=1
    dependencies=("${(@f)$(otool -L "$source_binary" | tail -n +2 | awk '{print $1}')}" )
    for dependency in "${dependencies[@]}"; do
        [[ "$dependency" == /opt/homebrew/* || "$dependency" == /usr/local/* ]] || continue
        [[ -f "$dependency" ]] || {
            print -u2 -- "Required QEMU library is missing: $dependency"
            exit 66
        }
        bundled_library="$DEST_DIR/root$dependency"
        if [[ ! -f "$bundled_library" ]]; then
            mkdir -p "${bundled_library:h}"
            cp -L "$dependency" "$bundled_library"
            chmod 755 "$bundled_library"
            pending+=("$dependency")
        fi
    done
done

for library in "$DEST_DIR"/root/**/*.dylib(N); do
    codesign --force --timestamp=none --sign - "$library"
done
codesign --force --timestamp=none --sign - "$DEST_DIR/bin/qemu-system-xtensa"

# Verify the child process with Homebrew removed from the lookup path.
env -i PATH=/usr/bin:/bin HOME=/private/tmp DYLD_ROOT_PATH="$DEST_DIR/root" \
    "$DEST_DIR/bin/qemu-system-xtensa" --version >/dev/null
print -- "Bundled ESP32-S3 QEMU child process: $DEST_DIR"
