# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(cockpit LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "cockpit")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# O flutter_inappwebview_windows ainda inclui <experimental/coroutine>, que o
# MSVC 14.51 transformou em erro de compilação (STL1011). Enquanto o plugin não
# migra pro <coroutine> do C++20, silencia o guard — senão o build do Windows
# não passa.
add_definitions(-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)

# Compilações paralelas do MSVC (cl /MP) escrevendo no mesmo .pdb estouram
# C1041 no flutter_inappwebview_windows; /FS serializa o acesso ao PDB.
add_compile_options(/FS)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# === cockpit-hook helper (status de turno do claude nas abas) ===
# Compila o helper que o claude invoca nos hooks e o instala ao lado do binário
# (o Inno empacota o bundle inteiro). Em runtime o ClaudeHookInstaller o extrai
# pra ~/.cockpit/bin. Equivale ao Run Script phase do macOS (build_hook.sh).
set(COCKPIT_HOOK_SRC "${CMAKE_SOURCE_DIR}/../tool/cockpit_hook.dart")
set(COCKPIT_HOOK_EXE "${CMAKE_BINARY_DIR}/cockpit-hook.exe")
if(DEFINED ENV{FLUTTER_ROOT})
  set(DART_EXE "$ENV{FLUTTER_ROOT}/bin/dart.bat")
else()
  set(DART_EXE "dart")
endif()
add_custom_command(
  OUTPUT "${COCKPIT_HOOK_EXE}"
  COMMAND "${DART_EXE}" compile exe "${COCKPIT_HOOK_SRC}" -o "${COCKPIT_HOOK_EXE}"
  DEPENDS "${COCKPIT_HOOK_SRC}"
  COMMENT "Compilando cockpit-hook.exe"
  VERBATIM)
add_custom_target(cockpit_hook ALL DEPENDS "${COCKPIT_HOOK_EXE}")
install(PROGRAMS "${COCKPIT_HOOK_EXE}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# === cockpit CLI (CLI interna: send/send-key/list-panes) ===
# Compila a CLI como `cockpit-cli.exe` (nome distinto do runner) e a instala ao
# lado do binário. Em runtime o ClaudeHookInstaller a materializa como
# ~/.cockpit/bin/cockpit.exe. Equivale ao Run Script phase do macOS (build_cli.sh).
# === cli/ → cockpit-cli (CLI interna em Rust, com o hook como subcomando) ===
# A CLI absorveu o antigo helper `cockpit-hook`: `cockpit hook` faz o mesmo
# papel. Rust porque o `dart compile exe` sai de UMA arquitetura, não
# cross-compila e não sobrevive ao `lipo` — ver macos/build_cli.sh.
set(COCKPIT_CLI_CRATE "${CMAKE_SOURCE_DIR}/../cli")
# O PATH do processo que roda o CMake nem sempre traz o `cargo` (IDE/launcher
# não herda o shell de login), então a instalação padrão do rustup entra como
# hint — mesma resolução do `resolve_cargo` do macos/build_cli.sh. Falhar aqui,
# no configure, troca o "no such file or directory" do ninja por uma causa.
find_program(CARGO_EXECUTABLE cargo HINTS "$ENV{USERPROFILE}/.cargo/bin")
if(NOT CARGO_EXECUTABLE)
  message(FATAL_ERROR
    "'cargo' não encontrado: a CLI interna (cli/) é um crate Rust e faz parte "
    "do build. Instale o Rust (https://rustup.rs) e rode o build de novo.")
endif()
# `build.rs` entra na lista: é ele que assa o flavor no binário, e uma
# mudança lá não mexe em `src/` — sem isto o CMake daria a CLI por
# atualizada. Mesma classe do glob do servidor logo abaixo.
file(GLOB_RECURSE COCKPIT_CLI_SOURCES CONFIGURE_DEPENDS
  "${COCKPIT_CLI_CRATE}/src/*.rs" "${COCKPIT_CLI_CRATE}/text/*"
  "${COCKPIT_CLI_CRATE}/build.rs")
set(COCKPIT_CLI_BUILT "${COCKPIT_CLI_CRATE}/target/release/cockpit.exe")
set(COCKPIT_CLI_EXE "${CMAKE_BINARY_DIR}/cockpit-cli.exe")
# Flavor assado no binário (ver cli/build.rs): decide qual socket a CLI procura
# primeiro quando roda fora de um terminal do Cockpit.
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(COCKPIT_CLI_FLAVOR "debug")
else()
  set(COCKPIT_CLI_FLAVOR "release")
endif()
add_custom_command(
  OUTPUT "${COCKPIT_CLI_EXE}"
  COMMAND "${CMAKE_COMMAND}" -E env "COCKPIT_FLAVOR=${COCKPIT_CLI_FLAVOR}"
          "${CARGO_EXECUTABLE}" build --release
          --manifest-path "${COCKPIT_CLI_CRATE}/Cargo.toml"
  COMMAND "${CMAKE_COMMAND}" -E copy "${COCKPIT_CLI_BUILT}" "${COCKPIT_CLI_EXE}"
  DEPENDS ${COCKPIT_CLI_SOURCES} "${COCKPIT_CLI_CRATE}/Cargo.toml"
  COMMENT "Compilando cockpit-cli.exe (Rust)"
  VERBATIM)
add_custom_target(cockpit_cli ALL DEPENDS "${COCKPIT_CLI_EXE}")
install(PROGRAMS "${COCKPIT_CLI_EXE}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# === cockpit-server (sidecar) ===
# Bundle `bin/` + `lib/` do servidor headless, instalado AO LADO do executável
# (o Inno empacota o bundle inteiro). Equivale ao Run Script do macOS
# (build_server.sh); sem isto o app cai no fallback in-process e o Windows roda
# uma arquitetura diferente do macOS.
#
# `dart build cli` NÃO cross-compila, mas aqui não é problema: o runner do CI é
# x64 nativo, a única arquitetura que publicamos no Windows.
set(COCKPIT_SERVER_PKG "${CMAKE_SOURCE_DIR}/../packages/cockpit_server")
set(COCKPIT_SERVER_DIR "${CMAKE_BINARY_DIR}/server-bundle")
set(COCKPIT_SERVER_EXE "${COCKPIT_SERVER_DIR}/bin/cockpit-server.exe")
# O servidor NÃO é só o pacote dele: depende dos irmãos por `path:`
# (cockpit_core, cockpit_engine, cockpit_protocol). Enquanto o glob só olhava
# `cockpit_server/`, editar o engine não invalidava nada e o CMake dava o
# bundle por atualizado — o build saía com um `cockpit-server.exe` VELHO, em
# silêncio. Aconteceu com a correção do login shell em host Windows.
file(GLOB_RECURSE COCKPIT_SERVER_SOURCES CONFIGURE_DEPENDS
  "${COCKPIT_SERVER_PKG}/bin/*.dart" "${COCKPIT_SERVER_PKG}/lib/*.dart"
  "${COCKPIT_SERVER_PKG}/../cockpit_core/lib/*.dart"
  "${COCKPIT_SERVER_PKG}/../cockpit_engine/lib/*.dart"
  "${COCKPIT_SERVER_PKG}/../cockpit_protocol/lib/*.dart")
add_custom_command(
  OUTPUT "${COCKPIT_SERVER_EXE}"
  # Bundle limpo: `dart build cli` recusa diretório de saída já existente.
  COMMAND "${CMAKE_COMMAND}" -E rm -rf "${COCKPIT_SERVER_DIR}" "${CMAKE_BINARY_DIR}/server-out"
  COMMAND "${CMAKE_COMMAND}" -E chdir "${COCKPIT_SERVER_PKG}" "${DART_EXE}" pub get
  COMMAND "${CMAKE_COMMAND}" -E chdir "${COCKPIT_SERVER_PKG}" "${DART_EXE}" build cli
          -o "${CMAKE_BINARY_DIR}/server-out"
  # `dart build cli` gera <out>/bundle/{bin,lib}; o exe sai com underscore.
  COMMAND "${CMAKE_COMMAND}" -E copy_directory
          "${CMAKE_BINARY_DIR}/server-out/bundle" "${COCKPIT_SERVER_DIR}"
  COMMAND "${CMAKE_COMMAND}" -E rename
          "${COCKPIT_SERVER_DIR}/bin/cockpit_server.exe" "${COCKPIT_SERVER_EXE}"
  # A lib do PTY vai ao LADO do exe do servidor: é o 2º candidato do
  # openPtyDylib (o 1º é a env COCKPIT_PTY_DYLIB, que o sidecar preenche).
  # Reusa o artefato do plugin em vez de compilar o mesmo .c duas vezes.
  COMMAND "${CMAKE_COMMAND}" -E copy
          "$<TARGET_FILE:cockpit_pty>" "${COCKPIT_SERVER_DIR}/bin/"
  # CLI embarcada ao lado do servidor (plano 60, Wave G): o servidor instala o
  # hook do agente apontando pra ela, e a acha na mesma pasta bin/.
  COMMAND "${CMAKE_COMMAND}" -E copy
          "${COCKPIT_CLI_EXE}" "${COCKPIT_SERVER_DIR}/bin/cockpit.exe"
  DEPENDS ${COCKPIT_SERVER_SOURCES} "${COCKPIT_SERVER_PKG}/pubspec.yaml"
          "${COCKPIT_CLI_EXE}" cockpit_pty
  COMMENT "Compilando cockpit-server (bundle do sidecar)"
  VERBATIM)
add_custom_target(cockpit_server ALL DEPENDS "${COCKPIT_SERVER_EXE}")
install(DIRECTORY "${COCKPIT_SERVER_DIR}/"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/cockpit-server-bundle"
  USE_SOURCE_PERMISSIONS COMPONENT Runtime)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
