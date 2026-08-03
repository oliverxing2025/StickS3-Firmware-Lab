#ifndef LV_CONF_H
#define LV_CONF_H

/* 与 Stick S3 固件 sdkconfig.defaults 一致的主机渲染配置。 */
#define LV_COLOR_DEPTH 16
#define LV_MEM_SIZE (2U * 1024U * 1024U)
#define LV_USE_OS 0
#define LV_USE_LOG 0
#define LV_DRAW_SW_ASM 0

#define LV_FONT_MONTSERRAT_10 1
#define LV_FONT_MONTSERRAT_12 1
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_MONTSERRAT_28 1
#define LV_FONT_MONTSERRAT_36 1
#define LV_FONT_DEFAULT &lv_font_montserrat_14

#endif
