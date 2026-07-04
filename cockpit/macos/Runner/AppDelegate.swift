import Cocoa
import FlutterMacOS
import ObjectiveC

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    enableClickThrough()
  }

  /// "Click-through": quando a janela do cockpit está sem foco, o primeiro
  /// clique numa janela de app já ATIVA e é engolido (só depois o 2º clique age)
  /// — porque `NSView.acceptsFirstMouse(for:)` retorna `false` por padrão e o
  /// `FlutterView` não sobrescreve. Como toda a UI (tabs inclusive) é desenhada
  /// dentro do único `FlutterView`, adicionamos um override retornando `true`
  /// **só nessa classe** (via runtime, sem mexer no `NSView` global): assim o
  /// primeiro clique numa janela desfocada foca E aciona a tab/botão, como nos
  /// apps nativos. Escopo mínimo — não afeta outras views (ex.: campos de IME).
  private func enableClickThrough() {
    guard let cls: AnyClass = NSClassFromString("FlutterView") else { return }
    let sel = #selector(NSView.acceptsFirstMouse(for:))
    let block: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
    let imp = imp_implementationWithBlock(block)
    // "B@:@" = retorna BOOL; recebe self, _cmd e um NSEvent*.
    if !class_addMethod(cls, sel, imp, "B@:@") {
      // Já tinha implementação própria → troca a IMP existente.
      if let method = class_getInstanceMethod(cls, sel) {
        method_setImplementation(method, imp)
      }
    }
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    // Ignora SIGPIPE no processo inteiro (disposição de sinal é por-processo,
    // não por-thread → cobre a platform/UI thread mesclada). Sem isso, qualquer
    // escrita num pipe sem leitor — spawn de language server que falha, PTY de
    // terminal fechado, processo `pi --mode rpc` que sumiu junto com uma worktree
    // deletada — entrega SIGPIPE e derruba o app inteiro, sem dialog nem crash
    // report. A Dart VM normalmente seta SIG_IGN, mas o embedder Flutter macOS no
    // modo "merged UI and platform thread (Experimental)" não o herda.
    signal(SIGPIPE, SIG_IGN)
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
