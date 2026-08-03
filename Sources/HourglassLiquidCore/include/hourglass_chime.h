#pragma once
#include "esp_err.h"
esp_err_t hourglass_liquid_host_chime_play(void);
static inline esp_err_t hourglass_chime_play(void) { return hourglass_liquid_host_chime_play(); }
