#pragma once

#include <cstdlib>

#define MALLOC_CAP_SPIRAM 0x01
#define MALLOC_CAP_8BIT 0x02

static inline void *heap_caps_calloc(size_t count, size_t size, int) {
    return std::calloc(count, size);
}
