#pragma once

#include "Panel_FrameBufferBase.hpp"
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

namespace lgfx {
inline namespace v1 {

struct Panel_StickS3Virtual : public Panel_FrameBufferBase {
 public:
  Panel_StickS3Virtual();
  ~Panel_StickS3Virtual() override;

  bool init(bool use_reset) override;
  color_depth_t setColorDepth(color_depth_t depth) override;
  void display(uint_fast16_t x, uint_fast16_t y, uint_fast16_t w, uint_fast16_t h) override;
  void endTransaction(void) override;

 private:
  uint8_t* _framebuffer = nullptr;
  int64_t _last_frame_micros = 0;
  volatile int64_t _last_update_micros = 0;
  volatile bool _dirty = true;
  TaskHandle_t _frame_task = nullptr;
  bool allocateFrameBuffer();
  void sendFrameIfDue(bool force);
  static void frameTaskEntry(void* argument);
};

}  // namespace v1
}  // namespace lgfx
