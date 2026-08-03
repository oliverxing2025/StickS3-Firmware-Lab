#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
LVGL_SOURCE="${LVGL_SOURCE_DIR:-}"
LVGL_TARGET="$PROJECT_DIR/Sources/LVGLHost"

if [[ -z "$LVGL_SOURCE" || ! -d "$LVGL_SOURCE/src" ]]; then
    echo "Usage: LVGL_SOURCE_DIR=/path/to/lvgl scripts/sync-firmware-sources.sh" >&2
    exit 2
fi

# 这是维护者显式更新第三方 LVGL 快照的工具，正常构建不会访问相邻仓库。
rsync -a --delete "$LVGL_SOURCE/src/" "$LVGL_TARGET/src/"
cp "$LVGL_SOURCE/lvgl.h" "$LVGL_TARGET/lvgl.h"
cp "$LVGL_SOURCE/lv_version.h" "$LVGL_TARGET/lv_version.h"
