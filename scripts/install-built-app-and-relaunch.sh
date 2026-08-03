#!/bin/zsh
set -euo pipefail

if [[ $# -ne 3 ]]; then
    exit 64
fi

SOURCE_APP="$1"
TARGET_APP="$2"
WAIT_PID="$3"
SUPPORT_DIR="$HOME/Library/Application Support/Stick S3 Firmware Simulator"
STATUS_LOG="$SUPPORT_DIR/update-status.log"
mkdir -p "$SUPPORT_DIR"

log_status() {
    print -r -- "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $1" >> "$STATUS_LOG"
}

if [[ "$SOURCE_APP" != *.app || "$TARGET_APP" != *.app || ! -d "$SOURCE_APP/Contents/MacOS" ]]; then
    exit 65
fi

for _ in {1..300}; do
    if ! kill -0 "$WAIT_PID" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

if kill -0 "$WAIT_PID" 2>/dev/null; then
    log_status "failed: process $WAIT_PID did not exit"
    exit 66
fi

STAGE_DIR="$(mktemp -d "$SUPPORT_DIR/update.XXXXXX")"
cleanup() {
    if [[ -n "${STAGE_DIR:-}" && "$STAGE_DIR" == "$SUPPORT_DIR"/update.* ]]; then
        /bin/rm -rf -- "$STAGE_DIR"
    fi
}
trap cleanup EXIT
STAGED_APP="$STAGE_DIR/Stick S3 虚拟设备.app"
PREVIOUS_APP="$SUPPORT_DIR/Previous Stick S3 虚拟设备.app"

ditto "$SOURCE_APP" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

if [[ -d "$TARGET_APP" ]]; then
    /bin/rm -rf -- "$PREVIOUS_APP"
    ditto "$TARGET_APP" "$PREVIOUS_APP"
fi

if [[ -e "$TARGET_APP" ]]; then
    /bin/rm -rf -- "$TARGET_APP"
fi
if ! ditto "$STAGED_APP" "$TARGET_APP" || ! codesign --verify --deep --strict "$TARGET_APP"; then
    /bin/rm -rf -- "$TARGET_APP"
    if [[ -d "$PREVIOUS_APP" ]]; then
        ditto "$PREVIOUS_APP" "$TARGET_APP"
    fi
    log_status "failed: install verification failed; previous app restored"
    [[ -d "$TARGET_APP" ]] && open "$TARGET_APP"
    exit 67
fi

log_status "success"
open "$TARGET_APP"
