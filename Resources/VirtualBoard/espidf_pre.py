from pathlib import Path
import shutil
import sys

# Capability profile schema v2 includes power, audio, and variable frame rate.

root = Path(sys.argv[1]).resolve()
support = root / ".sticks3-virtual-board"


def replace_once(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text(encoding="utf-8")
    if marker in text:
        return
    if old not in text:
        raise RuntimeError(f"StickS3 virtual-board patch point is missing: {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def find_optional(filename: str, required_fragment: str):
    candidates = [root / "managed_components", root / "components"]
    matches = [
        path for directory in candidates if directory.exists()
        for path in directory.rglob(filename)
        if required_fragment.lower() in path.as_posix().lower()
    ]
    return matches[0] if matches else None


def find_one(filename: str, required_fragment: str) -> Path:
    match = find_optional(filename, required_fragment)
    if match is None:
        raise RuntimeError(
            f"The project did not resolve {required_fragment}; "
            "the automatic StickS3 display bridge requires M5Unified/M5GFX."
        )
    return match


def find_direct_esp_lcd_source():
    search_roots = [root / "src", root / "main", root]
    visited = set()
    for directory in search_roots:
        if not directory.exists():
            continue
        for pattern in ("*.c", "*.cpp"):
            for path in directory.rglob(pattern):
                if path in visited:
                    continue
                visited.add(path)
                relative = path.relative_to(root).parts
                if relative and relative[0] in {
                    "managed_components", "components", ".sticks3-virtual-board"
                }:
                    continue
                text = path.read_text(encoding="utf-8", errors="ignore")
                if "esp_lcd_panel_draw_bitmap" in text:
                    return path
    return None


def prepare_direct_lcd_source(path: Path) -> None:
    """Adapt canvas-rendered LVGL firmware only in the private QEMU copy.

    Fruit Machine redraws its complete RGB565 canvas on every game update. Its
    short LVGL mutex timeout can skip UI creation while QEMU is processing the
    initial blank LCD strips. Wait reliably for that one initialization lock,
    then present the finished canvas directly to the virtual LCD. The physical
    firmware source, render cadence, and small DMA draw buffer remain intact.
    """
    text = path.read_text(encoding="utf-8", errors="ignore")
    original = text
    lock_marker = "STICKS3_VIRTUAL_RELIABLE_UI_LOCK"
    ui_creation = '    if (lvgl_lock()) {create_ui();lvgl_unlock();}\n'
    if lock_marker not in text and ui_creation in text:
        text = text.replace(
            ui_creation,
            '    /* ' + lock_marker + ' */\n'
            '    while (!lvgl_lock()) vTaskDelay(pdMS_TO_TICKS(5));\n'
            '    create_ui();\n'
            '    lvgl_unlock();\n',
            1,
        )

    canvas_marker = "STICKS3_VIRTUAL_DIRECT_CANVAS_PRESENT"
    invalidation = "    lv_obj_invalidate(s_canvas);"
    render_declaration = "static void render(void)\n"
    if (canvas_marker not in text and text.count(invalidation) == 2
            and render_declaration in text
            and "s_canvas_buffer" in text and "s_panel" in text):
        text = text.replace(invalidation, "    present_canvas();")
        presenter = (
            "/* " + canvas_marker + " */\n"
            "static void present_canvas(void)\n"
            "{\n"
            "#if defined(STICKS3_VIRTUAL_DEVICE)\n"
            "    lv_draw_sw_rgb565_swap(s_canvas_buffer,SCREEN_W*SCREEN_H);\n"
            "    esp_lcd_panel_draw_bitmap(\n"
            "        s_panel,0,0,SCREEN_W,SCREEN_H,s_canvas_buffer);\n"
            "#else\n"
            "    lv_obj_invalidate(s_canvas);\n"
            "#endif\n"
            "}\n\n"
        )
        text = text.replace(render_declaration, presenter + render_declaration, 1)

    if text != original:
        path.write_text(text, encoding="utf-8")
        print("StickS3 virtual display uses reliable UI creation and direct "
              "canvas presentation")


def install_semantic_audio_bridge() -> None:
    """Replace unsupported codec hardware only in the private build copy.

    The event remains the firmware's own fruit_sound_t value; the host renders
    it asynchronously, so the firmware's game loop and timing stay unchanged.
    """
    marker = "STICKS3_VIRTUAL_AUDIO_BRIDGE"
    for directory in (root / "src", root / "main"):
        if not directory.exists():
            continue
        for path in directory.rglob("*.c"):
            text = path.read_text(encoding="utf-8", errors="ignore")
            if marker in text:
                return
            if ("esp_err_t fruit_audio_play(" not in text
                    or "esp_err_t fruit_audio_init(" not in text):
                continue
            virtual = (
                "/* STICKS3_VIRTUAL_AUDIO_BRIDGE */\n"
                "#if defined(STICKS3_VIRTUAL_DEVICE)\n"
                "#include \"fruit_audio.h\"\n"
                "#include \"StickS3VirtualBoard.h\"\n"
                "esp_err_t fruit_audio_init(void) { return ESP_OK; }\n"
                "esp_err_t fruit_audio_play(fruit_sound_t sound) {\n"
                "  s3vd_send_audio_event((uint8_t)sound);\n"
                "  return ESP_OK;\n"
                "}\n"
                "#else\n"
                + text
                + "\n#endif\n"
            )
            path.write_text(virtual, encoding="utf-8")
            print("StickS3 semantic audio event bridge enabled")
            return


def link_direct_component(component_source: Path) -> None:
    for directory in [component_source.parent, *component_source.parents]:
        if directory == root.parent:
            break
        cmake = directory / "CMakeLists.txt"
        if not cmake.exists():
            continue
        text = cmake.read_text(encoding="utf-8")
        if "idf_component_register" not in text:
            continue
        marker = "STICKS3_VIRTUAL_BOARD_DIRECT_LCD_DEPENDENCY"
        if marker not in text:
            text += (
                "\n# STICKS3_VIRTUAL_BOARD_DIRECT_LCD_DEPENDENCY\n"
                "target_link_libraries(${COMPONENT_LIB} PRIVATE "
                "__idf_sticks3_virtual_board)\n"
            )
            cmake.write_text(text, encoding="utf-8")
        return
    raise RuntimeError(
        f"StickS3 direct esp_lcd component registration is unsupported: "
        f"{component_source}"
    )


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


install_semantic_audio_bridge()

m5gfx_cpp = find_optional("M5GFX.cpp", "m5gfx")
if m5gfx_cpp is None:
    direct_source = find_direct_esp_lcd_source()
    if direct_source is None:
        raise RuntimeError(
            "The project resolved neither M5GFX nor a direct esp_lcd display "
            "path supported by the automatic StickS3 bridge."
        )
    prepare_direct_lcd_source(direct_source)
    link_direct_component(direct_source)
    print("StickS3 ESP-IDF direct esp_lcd display and GPIO button bridge enabled")
    sys.exit(0)

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
