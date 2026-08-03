execute_process(
  COMMAND "${PYTHON}" "${CMAKE_CURRENT_LIST_DIR}/espidf_pre.py" "${CMAKE_SOURCE_DIR}"
  RESULT_VARIABLE STICKS3_VIRTUAL_PATCH_RESULT
  OUTPUT_VARIABLE STICKS3_VIRTUAL_PATCH_OUTPUT
  ERROR_VARIABLE STICKS3_VIRTUAL_PATCH_ERROR
)
if(NOT STICKS3_VIRTUAL_PATCH_RESULT EQUAL 0)
  message(FATAL_ERROR "StickS3 virtual-board patch failed: ${STICKS3_VIRTUAL_PATCH_ERROR}")
endif()
message(STATUS "${STICKS3_VIRTUAL_PATCH_OUTPUT}")
add_compile_definitions(STICKS3_VIRTUAL_DEVICE)
add_link_options("-Wl,--wrap=adc_calc_hw_calibration_code")
include_directories("${CMAKE_SOURCE_DIR}/components/sticks3_virtual_board")
