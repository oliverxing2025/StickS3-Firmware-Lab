#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE_APP="$PROJECT_DIR/build/StickS3 固件实验台.app"
DESKTOP_APP="$HOME/Desktop/StickS3 固件实验台.app"

"$PROJECT_DIR/scripts/build-app.sh" >/dev/null
if [[ -e "$DESKTOP_APP" ]]; then
    echo "Desktop target already exists: $DESKTOP_APP" >&2
    exit 2
fi
cp -R "$SOURCE_APP" "$DESKTOP_APP"
echo "$DESKTOP_APP"
