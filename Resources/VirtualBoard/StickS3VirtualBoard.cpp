#include "StickS3VirtualBoard.h"

#include <driver/uart.h>
#include <esp_err.h>
#include <esp_heap_caps.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

#include <cstring>

// Arduino-ESP32 2.x probes the QEMU flash with a legacy command which the
// current Espressif QEMU model does not answer. The image was already fully
// validated and assembled by the host, so allow startup to continue. This
// compatibility hook exists only in the private virtual build.
extern "C" esp_err_t __wrap_esp_flash_init_default_chip(void) {
  return ESP_OK;
}

// Espressif QEMU does not model the ESP32-S3 ADC oneshot completion event.
// ESP-IDF initializes ADC calibration before app_main whenever an imported
// component links esp_adc, so its hardware self-calibration would otherwise
// wait forever. The virtual board supplies BMI270 motion directly and does not
// expose the ADC, making a no-op calibration safe for this private build.
extern "C" void __wrap_adc_calc_hw_calibration_code(int, int) {}

namespace {
constexpr uart_port_t kPort = UART_NUM_0;
constexpr uint8_t kMagic[] = {'S', '3', 'V', 'D'};
constexpr size_t kHeaderSize = 10;
constexpr uint8_t kCapabilities = 0x01 | 0x02 | 0x04;
constexpr int64_t kPressMicros = 70000;
constexpr int64_t kGapMicros = 100000;

portMUX_TYPE gLock = portMUX_INITIALIZER_UNLOCKED;
bool gStarted = false;
float gAccel[3] = {0.0f, 0.0f, 1.0f};

struct ButtonState {
  bool pressed = false;
  bool held = false;
  uint8_t transitions = 0;
  int64_t nextTransition = 0;
};

ButtonState gButtons[2];
uint8_t* gFramePacket = nullptr;
size_t gFrameCapacity = 0;
uint32_t gFrameSequence = 0;

void writeLE32(uint8_t* destination, uint32_t value) {
  destination[0] = static_cast<uint8_t>(value);
  destination[1] = static_cast<uint8_t>(value >> 8);
  destination[2] = static_cast<uint8_t>(value >> 16);
  destination[3] = static_cast<uint8_t>(value >> 24);
}

void sendPacket(uint8_t type, const uint8_t* payload, size_t payloadSize) {
  uint8_t header[kHeaderSize] = {'S', '3', 'V', 'D', 1, type, 0, 0, 0, 0};
  writeLE32(header + 6, static_cast<uint32_t>(payloadSize));
  uart_write_bytes(kPort, header, sizeof(header));
  if (payloadSize) uart_write_bytes(kPort, payload, payloadSize);
  uart_wait_tx_done(kPort, pdMS_TO_TICKS(250));
}

void applyButton(uint8_t button, uint8_t clicks) {
  if (button > 1 || clicks == 0) return;
  portENTER_CRITICAL(&gLock);
  auto& state = gButtons[button];
  if (clicks >= 5) {
    state.held = !state.held;
    state.pressed = state.held;
    state.transitions = 0;
  } else {
    state.held = false;
    state.pressed = true;
    state.transitions = static_cast<uint8_t>(clicks * 2 - 1);
    state.nextTransition = esp_timer_get_time() + kPressMicros;
  }
  portEXIT_CRITICAL(&gLock);
}

void applyMotion(const uint8_t* payload, size_t size) {
  if (size != 12) return;
  float values[3];
  memcpy(values, payload, sizeof(values));
  portENTER_CRITICAL(&gLock);
  memcpy(gAccel, values, sizeof(values));
  portEXIT_CRITICAL(&gLock);
}

void inputTask(void*) {
  uint8_t buffer[96];
  size_t used = 0;
  for (;;) {
    int count = uart_read_bytes(kPort, buffer + used, sizeof(buffer) - used, pdMS_TO_TICKS(20));
    if (count > 0) used += static_cast<size_t>(count);
    size_t offset = 0;
    while (used - offset >= kHeaderSize) {
      if (memcmp(buffer + offset, kMagic, sizeof(kMagic)) != 0) {
        ++offset;
        continue;
      }
      const uint8_t version = buffer[offset + 4];
      const uint8_t type = buffer[offset + 5];
      const uint32_t length = static_cast<uint32_t>(buffer[offset + 6])
                            | (static_cast<uint32_t>(buffer[offset + 7]) << 8)
                            | (static_cast<uint32_t>(buffer[offset + 8]) << 16)
                            | (static_cast<uint32_t>(buffer[offset + 9]) << 24);
      if (version != 1 || length > 32) {
        ++offset;
        continue;
      }
      if (used - offset < kHeaderSize + length) break;
      const uint8_t* payload = buffer + offset + kHeaderSize;
      if (type == 0x11 && length == 2) applyButton(payload[0], payload[1]);
      if (type == 0x12) applyMotion(payload, length);
      offset += kHeaderSize + length;
    }
    if (offset) {
      memmove(buffer, buffer + offset, used - offset);
      used -= offset;
    } else if (used == sizeof(buffer)) {
      used = 0;
    }
  }
}
}  // namespace

extern "C" void s3vd_bridge_begin(void) {
  portENTER_CRITICAL(&gLock);
  if (gStarted) {
    portEXIT_CRITICAL(&gLock);
    return;
  }
  gStarted = true;
  portEXIT_CRITICAL(&gLock);

  if (!uart_is_driver_installed(kPort)) {
    uart_driver_install(kPort, 512, 0, 0, nullptr, 0);
  }
  xTaskCreatePinnedToCore(inputTask, "s3vd-input", 3072, nullptr, 2, nullptr, 0);
  sendPacket(0x01, &kCapabilities, 1);
}

extern "C" void s3vd_send_frame_rgb565_be(const uint8_t* pixels, uint16_t width, uint16_t height) {
  if (!pixels || !width || !height) return;
  s3vd_bridge_begin();
  const size_t pixelBytes = static_cast<size_t>(width) * height * 2;
  const size_t payloadBytes = 8 + pixelBytes;
  const size_t packetBytes = kHeaderSize + payloadBytes;
  if (packetBytes > gFrameCapacity) {
    auto* replacement = static_cast<uint8_t*>(heap_caps_realloc(
        gFramePacket, packetBytes, MALLOC_CAP_8BIT | MALLOC_CAP_SPIRAM));
    if (!replacement) replacement = static_cast<uint8_t*>(heap_caps_realloc(gFramePacket, packetBytes, MALLOC_CAP_8BIT));
    if (!replacement) return;
    gFramePacket = replacement;
    gFrameCapacity = packetBytes;
  }
  memcpy(gFramePacket, kMagic, sizeof(kMagic));
  gFramePacket[4] = 1;
  gFramePacket[5] = 0x02;
  writeLE32(gFramePacket + 6, static_cast<uint32_t>(payloadBytes));
  gFramePacket[10] = static_cast<uint8_t>(width);
  gFramePacket[11] = static_cast<uint8_t>(width >> 8);
  gFramePacket[12] = static_cast<uint8_t>(height);
  gFramePacket[13] = static_cast<uint8_t>(height >> 8);
  writeLE32(gFramePacket + 14, ++gFrameSequence);
  auto* destination = gFramePacket + 18;
  for (size_t index = 0; index < pixelBytes; index += 2) {
    destination[index] = pixels[index + 1];
    destination[index + 1] = pixels[index];
  }
  uart_write_bytes(kPort, gFramePacket, packetBytes);
  uart_wait_tx_done(kPort, pdMS_TO_TICKS(500));
}

extern "C" bool s3vd_button_pressed(uint8_t button) {
  if (button > 1) return false;
  const int64_t now = esp_timer_get_time();
  portENTER_CRITICAL(&gLock);
  auto& state = gButtons[button];
  while (state.transitions && now >= state.nextTransition) {
    state.pressed = !state.pressed;
    --state.transitions;
    state.nextTransition += state.pressed ? kGapMicros : kPressMicros;
  }
  const bool result = state.pressed;
  portEXIT_CRITICAL(&gLock);
  return result;
}

extern "C" void s3vd_get_accel(float* x, float* y, float* z) {
  portENTER_CRITICAL(&gLock);
  if (x) *x = gAccel[0];
  if (y) *y = gAccel[1];
  if (z) *z = gAccel[2];
  portEXIT_CRITICAL(&gLock);
}
