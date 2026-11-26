import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Flutter ocupa toda a janela (sem barra de título nativa).
    // window_manager usa TitleBarStyle.hidden + windowButtonVisibility: false
    // no lado Dart; aqui garantimos que o conteúdo expande até o topo.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    RegisterGeneratedPlugins(registry: flutterViewController)

    registerNativeDialogs(flutterViewController)
    registerAppActivation(flutterViewController)

    // Arquivos abertos pelo Finder chegam pelo AppDelegate → este canal.
    OpenFilesChannel.shared.register(flutterViewController)

    // Cada janela de documento (desktop_multi_window) é um engine novo: sem
    // isto ela nasce sem plugin nenhum (media_kit, webview, file_picker…).
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      DocumentWindowChannel.register(controller)
    }

    super.awakeFromNib()
  }

  /// Channel that activates ANOTHER Cockpit instance by pid: a detached
  /// workspace window is a second process (see `WorkspaceWindowService` on the
  /// Dart side). Since macOS 14 activation is cooperative: a background app
  /// cannot bring itself to the front, the active app has to yield. So the
  /// main window, which just received the click, yields activation and
  /// activates the other one.
  private func registerAppActivation(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "cockpit/app_activation",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "activate",
        let args = call.arguments as? [String: Any],
        let pid = args["pid"] as? Int,
        let app = NSRunningApplication(processIdentifier: pid_t(pid))
      else {
        result(false)
        return
      }
      if #available(macOS 14.0, *) {
        NSApp.yieldActivation(to: app)
        result(app.activate(options: []))
      } else {
        result(app.activate(options: [.activateIgnoringOtherApps]))
      }
    }
  }

  /// Canal nativo pro seletor de PASTA. Existe porque o `file_picker` (em
  /// nenhuma versão) liga `NSOpenPanel.canCreateDirectories` no diálogo de
  /// diretório — então o botão "New Folder" nunca aparece. Aqui abrimos o
  /// `NSOpenPanel` nós mesmos com esse flag ligado e com a pasta inicial
  /// (`initialDirectory`). Usa `beginSheetModal` (assíncrono) em vez de
  /// `runModal` pra não travar a platform/UI thread mesclada do embedder.
  private func registerNativeDialogs(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "cockpit/native_dialogs",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickDirectory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      self?.presentDirectoryPanel(
        initialDirectory: args?["initialDirectory"] as? String,
        result: result
      )
    }
  }

  private func presentDirectoryPanel(
    initialDirectory: String?,
    result: @escaping FlutterResult
  ) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true  // botão "New Folder"
    panel.showsHiddenFiles = false
    if let dir = initialDirectory, !dir.isEmpty {
      panel.directoryURL = URL(fileURLWithPath: dir)
    }
    panel.beginSheetModal(for: self) { response in
      if response == .OK, let url = panel.url {
        result(url.path)
      } else {
        result(nil)  // usuário cancelou
      }
    }
  }
}
