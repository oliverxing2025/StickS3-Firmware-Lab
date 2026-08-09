#include "Panel_StickS3Virtual.hpp"

#include "StickS3VirtualBoard.h"
#include "../platforms/common.hpp"

#include <esp_timer.h>
#include <cstring>

namespace lgfx {
inline namespace v1 {

Panel_StickS3Virtual::Panel_StickS3Virtual() : Panel_FrameBufferBase() {
  _auto_display = true;
  auto cfg = config();
  cfg.panel_width = 135;
  cfg.panel_height = 240;
  cfg.memory_width = 135;
  cfg.memory_height = 240;
  cfg.offset_x = 0;
  cfg.offset_y = 0;
  cfg.offset_rotation = 0;
  cfg.readable = true;
  cfg.invert = false;
  cfg.bus_shared = false;
  config(cfg);
}

Panel_StickS3Virtual::~Panel_StickS3Virtual() {
  if (_frame_task) {
    vTaskDelete(_frame_task);
    _frame_task = nullptr;
  }
  if (_framebuffer) heap_free(_framebuffer);
  if (_lines_buffer) heap_free(_lines_buffer);
}

bool Panel_StickS3Virtual::allocateFrameBuffer() {
  const size_t widthBytes = static_cast<size_t>(_cfg.panel_width) * 2;
  _lines_buffer = static_cast<uint8_t**>(heap_alloc_dma(_cfg.panel_height * sizeof(uint8_t*)));
  _framebuffer = static_cast<uint8_t*>(heap_alloc_dma(widthBytes * _cfg.panel_height));
  if (!_lines_buffer || !_framebuffer) return false;
  memset(_framebuffer, 0, widthBytes * _cfg.panel_height);
  for (size_t y = 0; y < _cfg.panel_height; ++y) _lines_buffer[y] = _framebuffer + y * widthBytes;
  return true;
}

bool Panel_StickS3Virtual::init(bool use_reset) {
  if (!_framebuffer && !allocateFrameBuffer()) return false;
  setColorDepth(rgb565_2Byte);
  s3vd_bridge_begin();
  const bool result = Panel_FrameBufferBase::init(use_reset);
  sendFrameIfDue(true);
  if (!_frame_task) {
    xTaskCreatePinnedToCore(frameTaskEntry, "s3vd-frame", 3072, this, 1,
                            &_frame_task, 0);
  }
  return result;
}

color_depth_t Panel_StickS3Virtual::setColorDepth(color_depth_t) {
  _write_depth = rgb565_2Byte;
  _read_depth = rgb565_2Byte;
  return rgb565_2Byte;
}

void Panel_StickS3Virtual::display(uint_fast16_t x, uint_fast16_t y, uint_fast16_t w, uint_fast16_t h) {
  Panel_FrameBufferBase::display(x, y, w, h);
  _dirty = true;
  _last_update_micros = esp_timer_get_time();
}

void Panel_StickS3Virtual::endTransaction(void) {
  _dirty = true;
  _last_update_micros = esp_timer_get_time();
}

void Panel_StickS3Virtual::sendFrameIfDue(bool force) {
  if (!_dirty || !_framebuffer) return;
  const int64_t now = esp_timer_get_time();
  // LVGL flushes one logical frame through several rectangles. Wait for a
  // short quiet window so the host never sees a half-painted frame.
  if (!force && now - _last_update_micros < 2000) return;
  if (!force && now - _last_frame_micros < s3vd_frame_interval_micros()) return;
  _last_frame_micros = now;
  _dirty = false;
  s3vd_send_frame_rgb565_be(_framebuffer, _cfg.panel_width, _cfg.panel_height);
}

void Panel_StickS3Virtual::frameTaskEntry(void* argument) {
  auto* panel = static_cast<Panel_StickS3Virtual*>(argument);
  while (true) {
    panel->sendFrameIfDue(false);
    vTaskDelay(pdMS_TO_TICKS(1));
  }
}

}  // namespace v1
}  // namespace lgfx
