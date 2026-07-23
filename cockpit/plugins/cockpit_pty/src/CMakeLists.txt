# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(cockpit_pty_library VERSION 0.0.1 LANGUAGES C)

add_library(cockpit_pty SHARED
  "cockpit_pty.c"
)

set_target_properties(cockpit_pty PROPERTIES
  PUBLIC_HEADER cockpit_pty.h
  OUTPUT_NAME "cockpit_pty"
)

target_compile_definitions(cockpit_pty PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size.
  target_link_options(cockpit_pty PRIVATE "-Wl,-z,max-page-size=16384")
endif()
