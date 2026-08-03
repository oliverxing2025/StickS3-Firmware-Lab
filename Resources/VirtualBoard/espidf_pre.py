from pathlib import Path
import shutil
import sys


root = Path(sys.argv[1]).resolve()
support = root / ".sticks3-virtual-board"


def replace_once(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text(encoding="utf-8")
    if marker in text:
        return
    if old not in text:
        raise RuntimeError(f"StickS3 virtual-board patch point is missing: {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def find_one(filename: str, required_fragment: str) -> Path:
    candidates = [root / "managed_components", root / "components"]
    matches = [
        path for directory in candidates if directory.exists()
        for path in directory.rglob(filename)
        if required_fragment.lower() in path.as_posix().lower()
    ]
    if not matches:
        raise RuntimeError(
            f"The project did not resolve {required_fragment}; "
            "the automatic StickS3 display bridge requires M5Unified/M5GFX."
        )
    return matches[0]


def require_virtual_board(component_source: Path) -> None:
    component_root = component_source.parent.parent
    cmake = component_root / "CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")
    marker = "STICKS3_VIRTUAL_BOARD_LINK_DEPENDENCY"
    if marker in text:
        return
    registration = "register_component()"
    if registration not in text:
        raise RuntimeError(
            f"StickS3 virtual-board component registration is unsupported: {cmake}"
        )
    dependency = (
        "# STICKS3_VIRTUAL_BOARD_LINK_DEPENDENCY\n"
        "list(APPEND COMPONENT_REQUIRES sticks3_virtual_board)\n"
        "register_component()"
    )
    cmake.write_text(text.replace(registration, dependency, 1), encoding="utf-8")


m5gfx_cpp = find_one("M5GFX.cpp", "m5gfx")
require_virtual_board(m5gfx_cpp)
panel_dir = m5gfx_cpp.parent / "lgfx" / "v1" / "panel"
for filename in ("Panel_StickS3Virtual.hpp", "Panel_StickS3Virtual.cpp"):
    shutil.copy2(support / filename, panel_dir / filename)

replace_once(
    m5gfx_cpp,
    '#include "lgfx/v1/panel/Panel_ST7789.hpp"',
    '#include "lgfx/v1/panel/Panel_ST7789.hpp"\n'
    '#if defined(STICKS3_VIRTUAL_DEVICE)\n'
    '#include "lgfx/v1/panel/Panel_StickS3Virtual.hpp"\n'
    '#endif',
    "Panel_StickS3Virtual.hpp",
)
replace_once(
    m5gfx_cpp,
    "  bool M5GFX::init_impl(bool use_reset, bool use_clear)\n  {\n",
    "  bool M5GFX::init_impl(bool use_reset, bool use_clear)\n  {\n"
    "#if defined(STICKS3_VIRTUAL_DEVICE)\n"
    "    auto virtual_panel = new lgfx::Panel_StickS3Virtual();\n"
    "    _panel_last.reset(virtual_panel);\n"
    "    panel(virtual_panel);\n"
    "    _board = board_t::board_M5StickS3;\n"
    "    return LGFX_Device::init_impl(false, use_clear);\n"
    "#endif\n",
    "auto virtual_panel = new lgfx::Panel_StickS3Virtual();",
)

m5unified_cpp = find_one("M5Unified.cpp", "m5unified")
require_virtual_board(m5unified_cpp)
replace_once(
    m5unified_cpp,
    '#include "M5Unified.hpp"',
    '#include "M5Unified.hpp"\n#if defined(STICKS3_VIRTUAL_DEVICE)\n'
    '#include "StickS3VirtualBoard.h"\n#endif',
    'include "StickS3VirtualBoard.h"',
)
replace_once(
    m5unified_cpp,
    "    case board_t::board_M5StickS3:\n"
    "      use_rawstate_bits = 0b00011;\n"
    "      btn_rawstate_bits = ((!m5gfx::gpio_in(GPIO_NUM_11)) & 1)\n"
    "                        | ((!m5gfx::gpio_in(GPIO_NUM_12)) & 1) << 1;\n"
    "      break;",
    "    case board_t::board_M5StickS3:\n"
    "      use_rawstate_bits = 0b00011;\n"
    "#if defined(STICKS3_VIRTUAL_DEVICE)\n"
    "      btn_rawstate_bits = (s3vd_button_pressed(0) ? 1 : 0)\n"
    "                        | (s3vd_button_pressed(1) ? 2 : 0);\n"
    "#else\n"
    "      btn_rawstate_bits = ((!m5gfx::gpio_in(GPIO_NUM_11)) & 1)\n"
    "                        | ((!m5gfx::gpio_in(GPIO_NUM_12)) & 1) << 1;\n"
    "#endif\n"
    "      break;",
    "btn_rawstate_bits = (s3vd_button_pressed(0)",
)

imu_cpp = find_one("IMU_Class.cpp", "m5unified")
replace_once(
    imu_cpp,
    '#include "IMU_Class.hpp"',
    '#include "IMU_Class.hpp"\n#if defined(STICKS3_VIRTUAL_DEVICE)\n'
    '#include "StickS3VirtualBoard.h"\n#endif',
    'include "StickS3VirtualBoard.h"',
)
replace_once(
    imu_cpp,
    "  bool IMU_Class::begin(I2C_Class* i2c, m5::board_t board)\n  {\n",
    "  bool IMU_Class::begin(I2C_Class* i2c, m5::board_t board)\n  {\n"
    "#if defined(STICKS3_VIRTUAL_DEVICE)\n"
    "    (void)i2c; (void)board;\n"
    "    _imu = imu_t::imu_bmi270;\n"
    "    _has_sensor_mask = sensor_mask_accel;\n"
    "    _latest_micros = m5gfx::micros();\n"
    "    s3vd_bridge_begin();\n"
    "    return true;\n"
    "#endif\n",
    "_has_sensor_mask = sensor_mask_accel;",
)
replace_once(
    imu_cpp,
    "  IMU_Class::sensor_mask_t IMU_Class::update(void)\n  {\n",
    "  IMU_Class::sensor_mask_t IMU_Class::update(void)\n  {\n"
    "#if defined(STICKS3_VIRTUAL_DEVICE)\n"
    "    _latest_micros = m5gfx::micros();\n"
    "    return sensor_mask_accel;\n"
    "#endif\n",
    "return sensor_mask_accel;",
)
replace_once(
    imu_cpp,
    "  void IMU_Class::getImuData(imu_data_t* data)\n  {\n",
    "  void IMU_Class::getImuData(imu_data_t* data)\n  {\n"
    "#if defined(STICKS3_VIRTUAL_DEVICE)\n"
    "    data->usec = m5gfx::micros();\n"
    "    s3vd_get_accel(&data->accel.x, &data->accel.y, &data->accel.z);\n"
    "    data->gyro = {};\n"
    "    data->mag = {};\n"
    "    return;\n"
    "#endif\n",
    "s3vd_get_accel(&data->accel.x",
)

print("StickS3 ESP-IDF virtual display, buttons, and BMI270 bridge enabled")
