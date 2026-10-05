#include "flutter_window.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <string>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"

namespace {

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(len, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      out.data(), len);
  return out;
}

// Canal "cockpit/document_window" das JANELAS DE DOCUMENTO (desktop_multi_window):
// a janela nasce 800x600 e sem título; o Dart manda `present` com título e
// tamanho, e aqui aplicamos na janela raiz (pai da view), centralizando no
// monitor. Espelha DocumentWindows.swift no macOS.
void RegisterDocumentWindowChannel(flutter::FlutterViewController* controller) {
  auto channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          controller->engine()->messenger(), "cockpit/document_window",
          &flutter::StandardMethodCodec::GetInstance());
  HWND view = controller->view()->GetNativeWindow();
  // `channel` capturado no próprio handler: vive enquanto o engine da janela.
  channel->SetMethodCallHandler(
      [channel, view](const flutter::MethodCall<flutter::EncodableValue>& call,
                      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                          result) {
        if (call.method_name() != "present") {
          result->NotImplemented();
          return;
        }
        std::string title;
        double width = 960, height = 720;
        if (const auto* args =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          if (auto it = args->find(flutter::EncodableValue("title"));
              it != args->end()) {
            if (const auto* s = std::get_if<std::string>(&it->second)) title = *s;
          }
          if (auto it = args->find(flutter::EncodableValue("width"));
              it != args->end()) {
            if (const auto* d = std::get_if<double>(&it->second)) width = *d;
          }
          if (auto it = args->find(flutter::EncodableValue("height"));
              it != args->end()) {
            if (const auto* d = std::get_if<double>(&it->second)) height = *d;
          }
        }
        HWND root = GetAncestor(view, GA_ROOT);
        if (root) {
          SetWindowTextW(root, Utf16FromUtf8(title).c_str());
          double scale = GetDpiForWindow(root) / 96.0;
          int w = static_cast<int>(width * scale);
          int h = static_cast<int>(height * scale);
          MONITORINFO mi = {sizeof(mi)};
          int x = CW_USEDEFAULT, y = CW_USEDEFAULT;
          if (GetMonitorInfoW(MonitorFromWindow(root, MONITOR_DEFAULTTONEAREST),
                              &mi)) {
            x = mi.rcWork.left + ((mi.rcWork.right - mi.rcWork.left) - w) / 2;
            y = mi.rcWork.top + ((mi.rcWork.bottom - mi.rcWork.top) - h) / 2;
          }
          SetWindowPos(root, HWND_TOP, x, y, w, h,
                       SWP_SHOWWINDOW | SWP_NOZORDER);
          SetForegroundWindow(root);
        }
        result->Success();
      });
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  // Fechamento limpo do Cockpit: o Dart chama `windowManager.destroy()`, que
  // no window_manager (Windows) é só `PostQuitMessage(0)`. O loop de mensagens
  // sai com a janela top-level AINDA VIVA e o controller ainda de pé, e o
  // destrutor padrão do membro `unique_ptr` deletaria o controller SEM zerar
  // o ponteiro antes. Destruir a view Flutter manda mensagens à janela viva
  // (ativação/foco/tamanho), `MessageHandler` vê `flutter_controller_` não
  // nulo e repassa pra um controller meio destruído → APPCRASH c0000005 em
  // `flutter_windows.dll` ~1 s depois do `[exit] encerramento limpo` (dump de
  // 2026-10-03, stack em FlutterDesktopViewControllerDestroy →
  // NtUserDestroyWindow → nosso WndProc → HandleTopLevelWindowProc).
  //
  // Mesmo caminho do `OnDestroy` (WM_DESTROY): `reset` zera o membro ANTES de
  // deletar, então as mensagens durante a destruição não encontram controller.
  flutter_controller_.reset();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  // Janelas de documento (desktop_multi_window): cada uma é um engine novo e
  // nasce sem plugin nenhum — registra os gerados + o canal de título/tamanho.
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterPlugins(view_controller->engine());
    RegisterDocumentWindowChannel(view_controller);
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
