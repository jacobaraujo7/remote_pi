cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "terminal_clipboard.cpp"
  "document_plugin_registrant.cpp"
  "main.cpp"
  "native_open_forwarder.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")

# Versão "marketing": o FLUTTER_VERSION vem do pubspec COM o build number
# (`1.8.4+21`), e é ele que o Runner.rc punha no VERSIONINFO. Isso quebra o
# self-update: o WinSparkle compara a versão do appcast com esse string e
# classifica o `+` como Type_String, ou seja, lê `1.8.4+21` como um
# PRÉ-LANÇAMENTO de `1.8.4` (mesma regra que faz `1.5 > 1.5b3`). Resultado: o
# appcast `1.8.4` parece mais novo que o app `1.8.4+21` pra sempre, e o updater
# reoferece a mesma versão em loop.
#
# O appcast do Windows publica a versão marketing (ver cockpit-release.yml), então
# o VERSIONINFO precisa publicar a mesma coisa. O build number não se perde: segue
# no 4º campo do FILEVERSION numérico (`1,8,4,21`), que é o lugar convencional
# dele no Windows.
# Sem FLUTTER_VERSION não há o que publicar no VERSIONINFO: abortar no configure
# é melhor que gerar um binário com versão falsa e descobrir pelo self-update
# quebrado na máquina do usuário.
if(NOT FLUTTER_VERSION)
  message(FATAL_ERROR
    "FLUTTER_VERSION não definido: o VERSIONINFO sairia com versão falsa e o "
    "self-update do WinSparkle compararia contra ela.")
endif()
string(REGEX REPLACE "\\+.*$" "" FLUTTER_VERSION_MARKETING "${FLUTTER_VERSION}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MARKETING=\"${FLUTTER_VERSION_MARKETING}\"")

target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "gdiplus.lib" "ole32.lib" "shell32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Explicit test target, outside the installed app bundle.
add_executable(native_open_forwarder_test EXCLUDE_FROM_ALL
  "native_open_forwarder_test.cpp" "native_open_forwarder.cpp")
apply_standard_settings(native_open_forwarder_test)
target_compile_definitions(native_open_forwarder_test PRIVATE "NOMINMAX")
target_compile_options(native_open_forwarder_test PRIVATE /utf-8)
target_link_libraries(native_open_forwarder_test PRIVATE "shell32.lib")
set_target_properties(native_open_forwarder_test PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/native_tests")
