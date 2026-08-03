#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"

echo "REBUILD-STEP:TESTS"
cd "$PROJECT_DIR"
# 先验证仓库内已确认的适配器基准。用户正在开发的固件可能有正常的
# 像素变化，不应因为旧截图哈希而无法载入；它会在下一步作为真实编译输入。
/usr/bin/env -u SIMULATOR_FIRMWARE_RUNTIME -u SIMULATOR_FIRMWARE_ROOT swift test

echo "REBUILD-STEP:BUILD"
"$PROJECT_DIR/scripts/build-app.sh"

echo "REBUILD-STEP:SIGNING"
codesign --verify --deep --strict "$PROJECT_DIR/build/Stick S3 虚拟设备.app"
