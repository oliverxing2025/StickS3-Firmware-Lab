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
  sendFrameIfDue(false);
}

void Panel_StickS3Virtual::endTransaction(void) {
  _dirty = true;
  sendFrameIfDue(false);
}

void Panel_StickS3Virtual::sendFrameIfDue(bool force) {
  if (!_dirty || !_framebuffer) return;
  const int64_t now = esp_timer_get_time();
  if (!force && now - _last_frame_micros < 33333) return;
  _last_frame_micros = now;
  _dirty = false;
  s3vd_send_frame_rgb565_be(_framebuffer, _cfg.panel_width, _cfg.panel_height);
}

}  // namespace v1
}  // namespace lgfx
