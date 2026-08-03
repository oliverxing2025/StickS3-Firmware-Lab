#pragma once

// 直接引用固件项目的真实游戏接口，避免 Mac 版另存一套规则。
#ifndef BREAKOUT_FIRMWARE_GAME_HEADER
#define BREAKOUT_FIRMWARE_GAME_HEADER "../../../Vendor/Firmware/breakout/include/BreakoutGame.h"
#endif
#include BREAKOUT_FIRMWARE_GAME_HEADER
