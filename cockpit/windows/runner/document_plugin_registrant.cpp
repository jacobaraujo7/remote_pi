//
//  Document-engine registration. Keep aligned with generated_plugin_registrant.cc.
//

// clang-format off

#include <flutter/plugin_registry.h>

#include <desktop_drop/desktop_drop_plugin.h>
#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <flutter_inappwebview_windows/flutter_inappwebview_windows_plugin_c_api.h>
#include <flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h>

#include <pasteboard/pasteboard_plugin.h>
#include <screen_retriever_windows/screen_retriever_windows_plugin_c_api.h>
#include <url_launcher_windows/url_launcher_windows.h>

// AutoUpdater is process-wide and throws on a second initialization.
// WindowManager also owns a process-global channel; registering it again
// redirects main-window events to the document engine. Documents use their
// own native channel for title and size instead.
// MediaKitVideo owns a process-global WndProc delegate: destroying a second
// instance breaks message forwarding for the primary window. Media and volume
// are not used by document windows and stay owned by the main engine.
// The main engine retains the generated full registration.
void RegisterDocumentPlugins(flutter::PluginRegistry* registry) {
  DesktopDropPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("DesktopDropPlugin"));
  DesktopMultiWindowPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("DesktopMultiWindowPlugin"));
  FlutterInappwebviewWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterInappwebviewWindowsPluginCApi"));
  FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterSecureStorageWindowsPlugin"));

  PasteboardPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PasteboardPlugin"));
  ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ScreenRetrieverWindowsPluginCApi"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
}
