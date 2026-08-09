#include "StickS3VirtualBoard.h"
#include "StickS3VirtualHardware.generated.h"

#include <driver/uart.h>
#include <driver/gpio.h>
#include <driver/spi_master.h>
#include <esp_err.h>
#include <esp_heap_caps.h>
#include <esp_lcd_io_spi.h>
#include <esp_lcd_panel_io.h>
#include <esp_lcd_panel_ops.h>
#include <esp_lcd_panel_st7789.h>
#include <esp_http_client.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/task.h>

#include <cstring>
#include <cstdlib>

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
constexpr uint8_t kCapabilities = S3VD_CAPABILITIES | (1 << 5);
constexpr int64_t kPressMicros = 70000;
constexpr int64_t kGapMicros = 100000;

portMUX_TYPE gLock = portMUX_INITIALIZER_UNLOCKED;
bool gStarted = false;
SemaphoreHandle_t gOutputMutex = nullptr;
SemaphoreHandle_t gHttpMutex = nullptr;
SemaphoreHandle_t gHttpResponseReady = nullptr;
float gAccel[3] = {0.0f, 0.0f, 1.0f};
int gBatteryPercent = 86;
bool gBatteryCharging = true;
bool gAudioEnabled = true;
int64_t gFrameIntervalMicros = 16667;

struct ButtonState {
  bool pressed = false;
  bool held = false;
  uint8_t transitions = 0;
  int64_t nextTransition = 0;
};

ButtonState gButtons[2];
uint8_t* gFramePacket = nullptr;
size_t gFrameCapacity = 0;
uint8_t* gPreviousFrame = nullptr;
size_t gPreviousFrameCapacity = 0;
uint32_t gFrameSequence = 0;
uint64_t gLastFrameHash = 0;
uint16_t gLastFrameWidth = 0;
uint16_t gLastFrameHeight = 0;
bool gHasLastFrameHash = false;
constexpr uint16_t kDirectDisplayWidth = 135;
constexpr uint16_t kDirectDisplayHeight = 240;
constexpr size_t kDirectDisplayBytes =
    static_cast<size_t>(kDirectDisplayWidth) * kDirectDisplayHeight * 2;
constexpr size_t kMaximumFramePacketBytes =
    kHeaderSize + 8 + kDirectDisplayBytes;
uint8_t gDirectDisplay[kDirectDisplayBytes] = {};
int64_t gDirectDisplayLastFrameMicros = 0;
int64_t gDirectDisplayLastUpdateMicros = 0;
bool gDirectDisplayDirty = false;
bool gDirectFullFrameMode = false;
TaskHandle_t gDirectDisplayTask = nullptr;
uint8_t gVirtualPanelIOStorage = 0;
uint8_t gVirtualPanelStorage = 0;
esp_lcd_panel_io_callbacks_t gVirtualPanelCallbacks = {};
void* gVirtualPanelUserContext = nullptr;
constexpr size_t kMaximumHostPacketBytes = 65536;
uint8_t* gInputBuffer = nullptr;
uint32_t gNextHttpRequestID = 1;

struct PendingHttpResponse {
  uint32_t requestID = 0;
  int32_t statusCode = 0;
  int32_t errorCode = 0;
  uint8_t* body = nullptr;
  size_t bodyLength = 0;
};

PendingHttpResponse gPendingHttp;

struct VirtualHttpClient {
  char* url = nullptr;
  char* headers = nullptr;
  size_t headersLength = 0;
  uint8_t* requestBody = nullptr;
  size_t requestBodyLength = 0;
  esp_http_client_method_t method = HTTP_METHOD_GET;
  int timeoutMilliseconds = 5000;
  http_event_handle_cb eventHandler = nullptr;
  void* userData = nullptr;
  int statusCode = 0;
};

void writeLE32(uint8_t* destination, uint32_t value) {
  destination[0] = static_cast<uint8_t>(value);
  destination[1] = static_cast<uint8_t>(value >> 8);
  destination[2] = static_cast<uint8_t>(value >> 16);
  destination[3] = static_cast<uint8_t>(value >> 24);
}

void writeLE16(uint8_t* destination, uint16_t value) {
  destination[0] = static_cast<uint8_t>(value);
  destination[1] = static_cast<uint8_t>(value >> 8);
}

uint32_t readLE32(const uint8_t* source) {
  return static_cast<uint32_t>(source[0])
      | (static_cast<uint32_t>(source[1]) << 8)
      | (static_cast<uint32_t>(source[2]) << 16)
      | (static_cast<uint32_t>(source[3]) << 24);
}

void sendPacket(uint8_t type, const uint8_t* payload, size_t payloadSize) {
  uint8_t header[kHeaderSize] = {'S', '3', 'V', 'D', 1, type, 0, 0, 0, 0};
  writeLE32(header + 6, static_cast<uint32_t>(payloadSize));
  if (gOutputMutex) xSemaphoreTake(gOutputMutex, portMAX_DELAY);
  uart_write_bytes(kPort, header, sizeof(header));
  if (payloadSize) uart_write_bytes(kPort, payload, payloadSize);
  uart_wait_tx_done(kPort, pdMS_TO_TICKS(250));
  if (gOutputMutex) xSemaphoreGive(gOutputMutex);
}

void directDisplayTask(void*) {
  while (true) {
    const int64_t now = esp_timer_get_time();
    const int64_t frameInterval = s3vd_frame_interval_micros();
    bool shouldSend = false;
    portENTER_CRITICAL(&gLock);
    if (gDirectDisplayDirty && now - gDirectDisplayLastUpdateMicros >= 2000
        && now - gDirectDisplayLastFrameMicros >= frameInterval) {
      gDirectDisplayDirty = false;
      gDirectDisplayLastFrameMicros = now;
      shouldSend = true;
    }
    portEXIT_CRITICAL(&gLock);
    if (shouldSend) {
      s3vd_send_frame_rgb565_be(
          gDirectDisplay, kDirectDisplayWidth, kDirectDisplayHeight);
    }
    vTaskDelay(pdMS_TO_TICKS(1));
  }
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

void applyDeviceState(const uint8_t* payload, size_t size) {
  if (size != 4) return;
  portENTER_CRITICAL(&gLock);
  gBatteryPercent = payload[0] > 100 ? 100 : payload[0];
  gBatteryCharging = payload[1] != 0;
  gAudioEnabled = payload[2] != 0;
  gFrameIntervalMicros = payload[3] <= 30 ? 33333 : 16667;
  portEXIT_CRITICAL(&gLock);
}

void applyHttpResponse(const uint8_t* payload, size_t size) {
  if (size < 16) return;
  const uint32_t requestID = readLE32(payload);
  const uint32_t bodyLength = readLE32(payload + 12);
  if (requestID != gPendingHttp.requestID || bodyLength != size - 16) return;
  free(gPendingHttp.body);
  gPendingHttp.body = nullptr;
  gPendingHttp.bodyLength = 0;
  if (bodyLength) {
    gPendingHttp.body = static_cast<uint8_t*>(malloc(bodyLength));
    if (!gPendingHttp.body) {
      gPendingHttp.errorCode = -1;
      xSemaphoreGive(gHttpResponseReady);
      return;
    }
    memcpy(gPendingHttp.body, payload + 16, bodyLength);
    gPendingHttp.bodyLength = bodyLength;
  }
  gPendingHttp.statusCode = static_cast<int32_t>(readLE32(payload + 4));
  gPendingHttp.errorCode = static_cast<int32_t>(readLE32(payload + 8));
  xSemaphoreGive(gHttpResponseReady);
}

void inputTask(void*) {
  size_t used = 0;
  for (;;) {
    if (!gInputBuffer) { vTaskDelay(pdMS_TO_TICKS(20)); continue; }
    int count = uart_read_bytes(kPort, gInputBuffer + used,
                                kMaximumHostPacketBytes - used, pdMS_TO_TICKS(20));
    if (count > 0) used += static_cast<size_t>(count);
    size_t offset = 0;
    while (used - offset >= kHeaderSize) {
      if (memcmp(gInputBuffer + offset, kMagic, sizeof(kMagic)) != 0) {
        ++offset;
        continue;
      }
      const uint8_t version = gInputBuffer[offset + 4];
      const uint8_t type = gInputBuffer[offset + 5];
      const uint32_t length = readLE32(gInputBuffer + offset + 6);
      if (version != 1 || length > kMaximumHostPacketBytes - kHeaderSize) {
        ++offset;
        continue;
      }
      if (used - offset < kHeaderSize + length) break;
      const uint8_t* payload = gInputBuffer + offset + kHeaderSize;
      if (type == 0x11 && length == 2) applyButton(payload[0], payload[1]);
      if (type == 0x12) applyMotion(payload, length);
      if (type == 0x13) applyDeviceState(payload, length);
      if (type == 0x21) applyHttpResponse(payload, length);
      offset += kHeaderSize + length;
    }
    if (offset) {
      memmove(gInputBuffer, gInputBuffer + offset, used - offset);
      used -= offset;
    } else if (used == kMaximumHostPacketBytes) {
      used = 0;
    }
  }
}
}  // namespace

extern "C" esp_http_client_handle_t __wrap_esp_http_client_init(
    const esp_http_client_config_t* config) {
  if (!config || !config->url) return nullptr;
  auto* client = static_cast<VirtualHttpClient*>(calloc(1, sizeof(VirtualHttpClient)));
  if (!client) return nullptr;
  client->url = strdup(config->url);
  client->method = config->method;
  client->timeoutMilliseconds = config->timeout_ms > 0 ? config->timeout_ms : 5000;
  client->eventHandler = config->event_handler;
  client->userData = config->user_data;
  if (!client->url) { free(client); return nullptr; }
  s3vd_bridge_begin();
  return reinterpret_cast<esp_http_client_handle_t>(client);
}

extern "C" esp_err_t __wrap_esp_http_client_set_url(
    esp_http_client_handle_t handle, const char* url) {
  auto* client = reinterpret_cast<VirtualHttpClient*>(handle);
  if (!client || !url) return ESP_ERR_INVALID_ARG;
  char* replacement = strdup(url);
  if (!replacement) return ESP_ERR_NO_MEM;
  free(client->url);
  client->url = replacement;
  return ESP_OK;
}

extern "C" esp_err_t __wrap_esp_http_client_set_method(
    esp_http_client_handle_t handle, esp_http_client_method_t method) {
  auto* client = reinterpret_cast<VirtualHttpClient*>(handle);
  if (!client) return ESP_ERR_INVALID_ARG;
  client->method = method;
  return ESP_OK;
}

extern "C" esp_err_t __wrap_esp_http_client_set_header(
    esp_http_client_handle_t handle, const char* key, const char* value) {
  auto* client = reinterpret_cast<VirtualHttpClient*>(handle);
  if (!client || !key || !value) return ESP_ERR_INVALID_ARG;
  const size_t addition = strlen(key) + strlen(value) + 2;
  if (client->headersLength + addition > 4096) return ESP_ERR_INVALID_SIZE;
  auto* replacement = static_cast<char*>(realloc(
      client->headers, client->headersLength + addition + 1));
  if (!replacement) return ESP_ERR_NO_MEM;
  client->headers = replacement;
  snprintf(client->headers + client->headersLength, addition + 1, "%s:%s\n", key, value);
  client->headersLength += addition;
  return ESP_OK;
}

extern "C" esp_err_t __wrap_esp_http_client_set_post_field(
    esp_http_client_handle_t handle, const char* data, int length) {
  auto* client = reinterpret_cast<VirtualHttpClient*>(handle);
  if (!client || length < 0 || (length > 0 && !data)) return ESP_ERR_INVALID_ARG;
  if (length > 48 * 1024) return ESP_ERR_INVALID_SIZE;
  free(client->requestBody);
  client->requestBody = nullptr;
  client->requestBodyLength = 0;
  if (length) {
    client->requestBody = static_cast<uint8_t*>(malloc(static_cast<size_t>(length)));
    if (!client->requestBody) return ESP_ERR_NO_MEM;
    memcpy(client->requestBody, data, static_cast<size_t>(length));
    client->requestBodyLength = static_cast<size_t>(length);
  }
  return ESP_OK;
}

extern "C" esp_err_t __wrap_esp_http_client_perform(esp_http_client_handle_t handle) {
  auto* client = reinterpret_cast<VirtualHttpClient*>(handle);
  if (!client || !client->url || !gHttpMutex || !gHttpResponseReady) return ESP_ERR_INVALID_STATE;
  if (xSemaphoreTake(gHttpMutex, pdMS_TO_TICKS(client->timeoutMilliseconds)) != pdTRUE) {
    return ESP_ERR_TIMEOUT;
  }
  while (xSemaphoreTake(gHttpResponseReady, 0) == pdTRUE) {}
  free(gPendingHttp.body);
  gPendingHttp = {};
  gPendingHttp.requestID = gNextHttpRequestID++;
  const size_t urlLength = strlen(client->url);
  const size_t payloadLength = 17 + urlLength + client->headersLength + client->requestBodyLength;
  if (payloadLength > kMaximumHostPacketBytes - kHeaderSize || urlLength > UINT16_MAX
      || client->headersLength > UINT16_MAX) {
    xSemaphoreGive(gHttpMutex);
    return ESP_ERR_INVALID_SIZE;
  }
  auto* payload = static_cast<uint8_t*>(malloc(payloadLength));
  if (!payload) { xSemaphoreGive(gHttpMutex); return ESP_ERR_NO_MEM; }
  writeLE32(payload, gPendingHttp.requestID);
  payload[4] = client->method == HTTP_METHOD_POST ? 1
      : client->method == HTTP_METHOD_PUT ? 2
      : client->method == HTTP_METHOD_DELETE ? 3
      : client->method == HTTP_METHOD_PATCH ? 4 : 0;
  writeLE32(payload + 5, static_cast<uint32_t>(client->timeoutMilliseconds));
  writeLE16(payload + 9, static_cast<uint16_t>(urlLength));
  writeLE16(payload + 11, static_cast<uint16_t>(client->headersLength));
  writeLE32(payload + 13, static_cast<uint32_t>(client->requestBodyLength));
  memcpy(payload + 17, client->url, urlLength);
  if (client->headersLength) memcpy(payload + 17 + urlLength, client->headers, client->headersLength);
  if (client->requestBodyLength) memcpy(
      payload + 17 + urlLength + client->headersLength,
      client->requestBody, client->requestBodyLength);
  sendPacket(0x20, payload, payloadLength);
  free(payload);
  const BaseType_t received = xSemaphoreTake(
      gHttpResponseReady, pdMS_TO_TICKS(client->timeoutMilliseconds + 1000));
  if (received != pdTRUE) {
    xSemaphoreGive(gHttpMutex);
    return ESP_ERR_TIMEOUT;
  }
  client->statusCode = gPendingHttp.statusCode;
  if (gPendingHttp.errorCode == 0 && client->eventHandler && gPendingHttp.bodyLength) {
    esp_http_client_event_t event = {};
    event.event_id = HTTP_EVENT_ON_DATA;
    event.client = handle;
    event.data = reinterpret_cast<char*>(gPendingHttp.body);
    event.data_len = static_cast<int>(gPendingHttp.bodyLength);
    event.user_data = client->userData;
    client->eventHandler(&event);
  }
  const esp_err_t result = gPendingHttp.errorCode == 0 ? ESP_OK : ESP_FAIL;
  xSemaphoreGive(gHttpMutex);
  return result;
}

extern "C" int __wrap_esp_http_client_get_status_code(esp_http_client_handle_t handle) {
  auto* client = reinterpret_cast<VirtualHttpClient*>(handle);
  return client ? client->statusCode : 0;
}

extern "C" esp_err_t __wrap_esp_http_client_cleanup(esp_http_client_handle_t handle) {
  auto* client = reinterpret_cast<VirtualHttpClient*>(handle);
  if (!client) return ESP_ERR_INVALID_ARG;
  free(client->url);
  free(client->headers);
  free(client->requestBody);
  free(client);
  return ESP_OK;
}

extern "C" esp_err_t __wrap_spi_bus_initialize(
    spi_host_device_t, const spi_bus_config_t*, spi_dma_chan_t) {
  s3vd_bridge_begin();
  return ESP_OK;
}

extern "C" esp_err_t __wrap_esp_lcd_new_panel_io_spi(
    esp_lcd_spi_bus_handle_t, const esp_lcd_panel_io_spi_config_t*,
    esp_lcd_panel_io_handle_t* output) {
  if (!output) return ESP_ERR_INVALID_ARG;
  s3vd_bridge_begin();
  *output = reinterpret_cast<esp_lcd_panel_io_handle_t>(&gVirtualPanelIOStorage);
  return ESP_OK;
}

extern "C" esp_err_t __wrap_esp_lcd_new_panel_st7789(
    const esp_lcd_panel_io_handle_t, const esp_lcd_panel_dev_config_t*,
    esp_lcd_panel_handle_t* output) {
  if (!output) return ESP_ERR_INVALID_ARG;
  *output = reinterpret_cast<esp_lcd_panel_handle_t>(&gVirtualPanelStorage);
  return ESP_OK;
}

extern "C" esp_err_t __wrap_esp_lcd_panel_io_register_event_callbacks(
    esp_lcd_panel_io_handle_t, const esp_lcd_panel_io_callbacks_t* callbacks,
    void* userContext) {
  gVirtualPanelCallbacks = callbacks ? *callbacks : esp_lcd_panel_io_callbacks_t{};
  gVirtualPanelUserContext = userContext;
  return ESP_OK;
}

extern "C" esp_err_t __wrap_esp_lcd_panel_reset(esp_lcd_panel_handle_t) { return ESP_OK; }
extern "C" esp_err_t __wrap_esp_lcd_panel_init(esp_lcd_panel_handle_t) { return ESP_OK; }
extern "C" esp_err_t __wrap_esp_lcd_panel_invert_color(esp_lcd_panel_handle_t, bool) { return ESP_OK; }
extern "C" esp_err_t __wrap_esp_lcd_panel_swap_xy(esp_lcd_panel_handle_t, bool) { return ESP_OK; }
extern "C" esp_err_t __wrap_esp_lcd_panel_mirror(esp_lcd_panel_handle_t, bool, bool) { return ESP_OK; }
extern "C" esp_err_t __wrap_esp_lcd_panel_set_gap(esp_lcd_panel_handle_t, int, int) { return ESP_OK; }
extern "C" esp_err_t __wrap_esp_lcd_panel_disp_on_off(esp_lcd_panel_handle_t, bool) { return ESP_OK; }

extern "C" esp_err_t __wrap_esp_lcd_panel_draw_bitmap(
    esp_lcd_panel_handle_t, int x_start, int y_start,
    int x_end, int y_end, const void* color_data) {
  const bool isFullFrame = x_start == 0 && y_start == 0 &&
      x_end == kDirectDisplayWidth && y_end == kDirectDisplayHeight;
  if (color_data && isFullFrame) {
    // A canvas-rendered firmware already owns a complete, stable frame here.
    // Encode it before replacing the virtual LCD's previous-frame storage.
    s3vd_send_frame_rgb565_be(
        static_cast<const uint8_t*>(color_data),
        kDirectDisplayWidth, kDirectDisplayHeight);
    gDirectFullFrameMode = true;
  }
  if (color_data && (isFullFrame || !gDirectFullFrameMode) &&
      x_start >= 0 && y_start >= 0 &&
      x_end > x_start && y_end > y_start &&
      x_end <= kDirectDisplayWidth && y_end <= kDirectDisplayHeight) {
    const size_t rowBytes = static_cast<size_t>(x_end - x_start) * 2;
    const auto* source = static_cast<const uint8_t*>(color_data);
    for (int y = y_start; y < y_end; ++y) {
      auto* destination = gDirectDisplay
          + (static_cast<size_t>(y) * kDirectDisplayWidth + x_start) * 2;
      memcpy(destination, source, rowBytes);
      source += rowBytes;
    }
    if (!isFullFrame) {
      portENTER_CRITICAL(&gLock);
      gDirectDisplayDirty = true;
      gDirectDisplayLastUpdateMicros = esp_timer_get_time();
      portEXIT_CRITICAL(&gLock);
    }
  }
  if (!isFullFrame && gVirtualPanelCallbacks.on_color_trans_done) {
    gVirtualPanelCallbacks.on_color_trans_done(
        reinterpret_cast<esp_lcd_panel_io_handle_t>(&gVirtualPanelIOStorage),
        nullptr, gVirtualPanelUserContext);
  }
  return ESP_OK;
}

extern "C" int __real_gpio_get_level(gpio_num_t gpio_num);

extern "C" int __wrap_gpio_get_level(gpio_num_t gpio_num) {
  if (gpio_num == static_cast<gpio_num_t>(S3VD_FRONT_GPIO)) {
    const bool pressed = s3vd_button_pressed(0);
    return S3VD_FRONT_ACTIVE_LOW ? !pressed : pressed;
  }
  if (gpio_num == static_cast<gpio_num_t>(S3VD_SIDE_GPIO)) {
    const bool pressed = s3vd_button_pressed(1);
    return S3VD_SIDE_ACTIVE_LOW ? !pressed : pressed;
  }
  return __real_gpio_get_level(gpio_num);
}

extern "C" esp_err_t __wrap_vibe_board_init_power(void) { return ESP_OK; }
extern "C" esp_err_t __wrap_vibe_board_imu_init(void) {
  s3vd_bridge_begin();
  return ESP_OK;
}
extern "C" esp_err_t __wrap_vibe_board_accel_read(int16_t* x, int16_t* y, int16_t* z) {
  if (!x || !y || !z) return ESP_ERR_INVALID_ARG;
  float ax = 0.0f, ay = 0.0f, az = 1.0f;
  s3vd_get_accel(&ax, &ay, &az);
  *x = static_cast<int16_t>(ax * 16384.0f);
  *y = static_cast<int16_t>(ay * 16384.0f);
  *z = static_cast<int16_t>(az * 16384.0f);
  return ESP_OK;
}
extern "C" esp_err_t __wrap_vibe_board_battery_level(int* level) {
  if (!level) return ESP_ERR_INVALID_ARG;
  portENTER_CRITICAL(&gLock);
  *level = gBatteryPercent;
  portEXIT_CRITICAL(&gLock);
  return ESP_OK;
}
extern "C" esp_err_t __wrap_vibe_board_battery_charging(bool* charging) {
  if (!charging) return ESP_ERR_INVALID_ARG;
  portENTER_CRITICAL(&gLock);
  *charging = gBatteryCharging;
  portEXIT_CRITICAL(&gLock);
  return ESP_OK;
}
extern "C" esp_err_t __wrap_vibe_board_usb_powered(bool* powered) {
  if (!powered) return ESP_ERR_INVALID_ARG;
  *powered = false;
  return ESP_OK;
}
extern "C" esp_err_t __wrap_vibe_board_speaker_set_enabled(bool) {
  return ESP_OK;
}

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
  // The bridge carries framebuffer data rather than a human serial console.
  // Raising the private virtual UART rate prevents display transport from
  // slowing the emulated firmware clock.
  uart_set_baudrate(kPort, 5000000);
  if (!gOutputMutex) gOutputMutex = xSemaphoreCreateMutex();
  if (!gHttpMutex) gHttpMutex = xSemaphoreCreateMutex();
  if (!gHttpResponseReady) gHttpResponseReady = xSemaphoreCreateBinary();
  if (!gInputBuffer) {
    gInputBuffer = static_cast<uint8_t*>(
        heap_caps_malloc(kMaximumHostPacketBytes, MALLOC_CAP_8BIT));
  }
  // Reserve the largest possible encoded packet before LVGL, its canvas, and
  // task stacks fragment internal RAM. The fixed virtual LCD buffer doubles
  // as previous-frame storage, so no third 64.8 KB framebuffer is required.
  if (!gFramePacket) {
    gFramePacket = static_cast<uint8_t*>(
        heap_caps_malloc(kMaximumFramePacketBytes, MALLOC_CAP_8BIT));
    if (gFramePacket) gFrameCapacity = kMaximumFramePacketBytes;
  }
  if (!gPreviousFrame) {
    gPreviousFrame = gDirectDisplay;
    gPreviousFrameCapacity = kDirectDisplayBytes;
  }
  if (!gDirectDisplayTask) {
    xTaskCreatePinnedToCore(directDisplayTask, "s3vd-lcd", 3072, nullptr, 1,
                            &gDirectDisplayTask, 0);
  }
  xTaskCreatePinnedToCore(inputTask, "s3vd-input", 3072, nullptr, 2, nullptr, 0);
  const uint8_t report[] = {
      kCapabilities,
      static_cast<uint8_t>(static_cast<int8_t>(S3VD_LOGICAL_X)),
      static_cast<uint8_t>(static_cast<int8_t>(S3VD_LOGICAL_Y)),
      static_cast<uint8_t>(static_cast<int8_t>(S3VD_LOGICAL_Z)),
      S3VD_FRONT_GPIO, S3VD_SIDE_GPIO,
      S3VD_FRONT_ACTIVE_LOW, S3VD_SIDE_ACTIVE_LOW,
      S3VD_DISPLAY_ROTATION, S3VD_COMPATIBILITY,
  };
  sendPacket(0x01, report, sizeof(report));
}

extern "C" void s3vd_send_frame_rgb565_be(const uint8_t* pixels, uint16_t width, uint16_t height) {
  if (!pixels || !width || !height) return;
  s3vd_bridge_begin();
  const size_t pixelBytes = static_cast<size_t>(width) * height * 2;
  const uint8_t* framePixels = pixels;
  // Draw callbacks can fire even when no pixel changed. Hash the source buffer
  // before byte swapping so identical frames never cross the UART/QEMU pipe.
  uint64_t frameHash = 1469598103934665603ULL;
  for (size_t index = 0; index < pixelBytes; ++index) {
    frameHash ^= framePixels[index];
    frameHash *= 1099511628211ULL;
  }
  if (gHasLastFrameHash && width == gLastFrameWidth && height == gLastFrameHeight &&
      frameHash == gLastFrameHash) {
    return;
  }
  const bool hasPreviousFrame = gPreviousFrame && gPreviousFrame != framePixels
      && gPreviousFrameCapacity >= pixelBytes
      && width == gLastFrameWidth && height == gLastFrameHeight;
  // Choose the smallest of three lossless representations: raw full frame,
  // full-frame RLE, or sparse changed-pixel runs. Fruit Machine reel motion
  // changes only part of the LCD, so delta runs avoid repeatedly moving the
  // unchanged header, controls, and background through QEMU's virtual UART.
  const size_t pixelCount = pixelBytes / 2;
  size_t runCount = 0;
  for (size_t index = 0; index < pixelCount;) {
    const uint8_t high = framePixels[index * 2];
    const uint8_t low = framePixels[index * 2 + 1];
    size_t run = 1;
    while (index + run < pixelCount && run < 65535 &&
           framePixels[(index + run) * 2] == high &&
           framePixels[(index + run) * 2 + 1] == low) {
      ++run;
    }
    ++runCount;
    index += run;
  }
  size_t deltaBytes = 0;
  if (hasPreviousFrame) {
    for (size_t index = 0; index < pixelCount;) {
      while (index < pixelCount &&
             framePixels[index * 2] == gPreviousFrame[index * 2] &&
             framePixels[index * 2 + 1] == gPreviousFrame[index * 2 + 1]) {
        ++index;
      }
      if (index == pixelCount) break;
      size_t changed = 0;
      while (index + changed < pixelCount && changed < 65535 &&
             (framePixels[(index + changed) * 2] != gPreviousFrame[(index + changed) * 2] ||
              framePixels[(index + changed) * 2 + 1] != gPreviousFrame[(index + changed) * 2 + 1])) {
        ++changed;
      }
      deltaBytes += 4 + changed * 2;
      index += changed;
    }
  }
  const size_t rleBytes = runCount * 4;
  const bool useDelta = hasPreviousFrame && deltaBytes < pixelBytes && deltaBytes < rleBytes;
  const bool useRLE = !useDelta && rleBytes < pixelBytes;
  const size_t encodedPixelBytes = useDelta ? deltaBytes : (useRLE ? rleBytes : pixelBytes);
  const size_t payloadBytes = 8 + encodedPixelBytes;
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
  gFramePacket[5] = useDelta ? 0x05 : (useRLE ? 0x04 : 0x02);
  writeLE32(gFramePacket + 6, static_cast<uint32_t>(payloadBytes));
  gFramePacket[10] = static_cast<uint8_t>(width);
  gFramePacket[11] = static_cast<uint8_t>(width >> 8);
  gFramePacket[12] = static_cast<uint8_t>(height);
  gFramePacket[13] = static_cast<uint8_t>(height >> 8);
  writeLE32(gFramePacket + 14, ++gFrameSequence);
  auto* destination = gFramePacket + 18;
  if (useDelta) {
    size_t output = 0;
    for (size_t index = 0; index < pixelCount;) {
      while (index < pixelCount &&
             framePixels[index * 2] == gPreviousFrame[index * 2] &&
             framePixels[index * 2 + 1] == gPreviousFrame[index * 2 + 1]) {
        ++index;
      }
      if (index == pixelCount) break;
      size_t changed = 0;
      while (index + changed < pixelCount && changed < 65535 &&
             (framePixels[(index + changed) * 2] != gPreviousFrame[(index + changed) * 2] ||
              framePixels[(index + changed) * 2 + 1] != gPreviousFrame[(index + changed) * 2 + 1])) {
        ++changed;
      }
      writeLE16(destination + output, static_cast<uint16_t>(index));
      writeLE16(destination + output + 2, static_cast<uint16_t>(changed));
      output += 4;
      for (size_t offset = 0; offset < changed; ++offset) {
        destination[output++] = framePixels[(index + offset) * 2 + 1];
        destination[output++] = framePixels[(index + offset) * 2];
      }
      index += changed;
    }
  } else if (useRLE) {
    size_t output = 0;
    for (size_t index = 0; index < pixelCount;) {
      const uint8_t high = framePixels[index * 2];
      const uint8_t low = framePixels[index * 2 + 1];
      size_t run = 1;
      while (index + run < pixelCount && run < 65535 &&
             framePixels[(index + run) * 2] == high &&
             framePixels[(index + run) * 2 + 1] == low) {
        ++run;
      }
      destination[output] = static_cast<uint8_t>(run);
      destination[output + 1] = static_cast<uint8_t>(run >> 8);
      destination[output + 2] = low;
      destination[output + 3] = high;
      output += 4;
      index += run;
    }
  } else {
    for (size_t index = 0; index < pixelBytes; index += 2) {
      destination[index] = framePixels[index + 1];
      destination[index + 1] = framePixels[index];
    }
  }
  if (gOutputMutex) xSemaphoreTake(gOutputMutex, portMAX_DELAY);
  uart_write_bytes(kPort, gFramePacket, packetBytes);
  uart_wait_tx_done(kPort, pdMS_TO_TICKS(500));
  if (gOutputMutex) xSemaphoreGive(gOutputMutex);
  if (pixelBytes > gPreviousFrameCapacity && gPreviousFrame != gDirectDisplay) {
    auto* replacement = static_cast<uint8_t*>(heap_caps_realloc(
        gPreviousFrame, pixelBytes, MALLOC_CAP_8BIT | MALLOC_CAP_SPIRAM));
    if (!replacement) replacement = static_cast<uint8_t*>(heap_caps_realloc(
        gPreviousFrame, pixelBytes, MALLOC_CAP_8BIT));
    if (replacement) {
      gPreviousFrame = replacement;
      gPreviousFrameCapacity = pixelBytes;
    }
  }
  if (gPreviousFrame && gPreviousFrameCapacity >= pixelBytes) {
    memcpy(gPreviousFrame, framePixels, pixelBytes);
  }
  gLastFrameHash = frameHash;
  gLastFrameWidth = width;
  gLastFrameHeight = height;
  gHasLastFrameHash = true;
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

extern "C" bool s3vd_audio_enabled(void) {
  portENTER_CRITICAL(&gLock);
  const bool enabled = gAudioEnabled;
  portEXIT_CRITICAL(&gLock);
  return enabled;
}

extern "C" void s3vd_send_audio_event(uint8_t sound) {
  if (!s3vd_audio_enabled()) return;
  sendPacket(0x03, &sound, 1);
}

extern "C" int64_t s3vd_frame_interval_micros(void) {
  portENTER_CRITICAL(&gLock);
  const int64_t interval = gFrameIntervalMicros;
  portEXIT_CRITICAL(&gLock);
  return interval;
}
