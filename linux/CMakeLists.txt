cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "flutter_fd_utils")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "flutter_fd_utils_plugin")

add_library(${PLUGIN_NAME} SHARED
  "flutter_fd_utils_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})

target_include_directories(${PLUGIN_NAME} PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(flutter_fd_utils_bundled_libraries
  ""
  PARENT_SCOPE)
