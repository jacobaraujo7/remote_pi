#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // Impeller desligado no Windows: com ele ligado (default desde o Flutter
  // 3.47) o backend GLES/ANGLE quebra ao compor a textura das webviews
  // (WebView2 via flutter_inappwebview) — `[FATAL] render_pass_gles.cc: Could
  // not create a complete framebuffer` no debug e, no release, APPCRASH em
  // `impeller::AiksContext::GetContentContext` (Event Log de 2026-10-03). Abrir
  // um preview de markdown ou um .panel derrubava o app. Skia segue como era
  // ate o 3.46; reavaliar quando o Impeller/GLES tratar texturas externas.
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Cockpit", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // window_manager.destroy() posts WM_QUIT without destroying the HWND. Tear
  // down the Flutter view and plugins while COM is still initialized; leaving
  // this to the stack destructor runs their teardown after CoUninitialize().
  if (window.GetHandle()) {
    window.Destroy();
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
