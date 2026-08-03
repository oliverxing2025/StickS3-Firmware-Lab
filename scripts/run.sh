#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
"$PROJECT_DIR/scripts/build-app.sh" >/dev/null
BUILT_APP="$PROJECT_DIR/build/Stick S3 虚拟设备.app"
open "$BUILT_APP"
