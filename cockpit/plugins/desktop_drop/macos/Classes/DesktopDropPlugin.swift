import Cocoa
import FlutterMacOS

private func findFlutterViewController(_ viewController: NSViewController?) -> FlutterViewController? {
  guard let vc = viewController else {
    return nil
  }
  if let fvc = vc as? FlutterViewController {
    return fvc
  }
  for child in vc.children {
    let fvc = findFlutterViewController(child)
    if fvc != nil {
      return fvc
    }
  }
  return nil
}

public class DesktopDropPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    guard let flutterView = registrar.view else { return }
    guard let flutterWindow = flutterView.window else { return }
    guard let vc = findFlutterViewController(flutterWindow.contentViewController) else { return }

    let channel = FlutterMethodChannel(name: "desktop_drop", binaryMessenger: registrar.messenger)

    let instance = DesktopDropPlugin()
      
      channel.setMethodCallHandler(instance.handle(_:result:))
      
    let d = DropTarget(frame: vc.view.bounds, channel: channel)
    d.autoresizingMask = [.width, .height]

    d.registerForDraggedTypes(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    d.registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])

    vc.view.addSubview(d)

    registrar.addMethodCallDelegate(instance, channel: channel)
  }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult){
 
      if call.method ==  "startAccessingSecurityScopedResource"{
            let map = call.arguments as! NSDictionary 
            var isStale: Bool = false

          let bookmarkByte = map["apple-bookmark"] as! FlutterStandardTypedData
          let bookmark = bookmarkByte.data
            
            let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
            let suc = url?.startAccessingSecurityScopedResource()
            result(suc) 
            return
      }

      if call.method ==  "stopAccessingSecurityScopedResource"{
            let map = call.arguments as! NSDictionary 
            var isStale: Bool = false 
          let bookmarkByte = map["apple-bookmark"] as! FlutterStandardTypedData
          let bookmark = bookmarkByte.data
            let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
            url?.stopAccessingSecurityScopedResource()
            result(true)
            return
      }

      Swift.print("method not found: \(call.method)")
      result(FlutterMethodNotImplemented)
      return
  }

   
}

class DropTarget: NSView {
  // Cockpit: fora de um drag a view é TRANSPARENTE ao hit test do AppKit.
  //
  // O DropTarget cobre a FlutterView inteira. Como view sob o cursor, ele fazia
  // o WebKit (WKWebView das previews/.panel/navegador, uma platform view)
  // descartar todo mouseMoved: CSS :hover nunca acendia e o cursor de link não
  // mudava. Clique passava (mouseDown é repassado), hover não tem repasse.
  // Mesmo fix do upstream MixinNetwork/flutter-plugins#436 (desktop_drop 0.9.0),
  // que não dá pra consumir ainda (exige Dart >=3.13.5). Drag continua igual:
  // draggingEntered liga a flag e o hitTest volta ao normal durante a sessão.
  private var isDragging = false

  override func hitTest(_ point: NSPoint) -> NSView? {
    if !isDragging { return nil }
    return super.hitTest(point)
  }

  override func draggingEnded(_ sender: NSDraggingInfo) {
    isDragging = false
  }

  private let channel: FlutterMethodChannel

  init(frame frameRect: NSRect, channel: FlutterMethodChannel) {
    self.channel = channel
    super.init(frame: frameRect)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    isDragging = true
    channel.invokeMethod("entered", arguments: convertPoint(sender.draggingLocation))
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    channel.invokeMethod("updated", arguments: convertPoint(sender.draggingLocation))
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    isDragging = false
    channel.invokeMethod("exited", arguments: nil)
  }

  /// Directory URL used for accepting file promises.
  private lazy var destinationURL: URL = {
    let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Drops")
    try? FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
    return destinationURL
  }()

  /// Queue used for reading and writing file promises.
  private lazy var workQueue: OperationQueue = {
    let providerQueue = OperationQueue()
    providerQueue.qualityOfService = .userInitiated
    return providerQueue
  }()

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { 
    var items: [[String: Any?]] = [];

    let searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true,
    ]

    let group = DispatchGroup()

    // retrieve NSFilePromise.
    sender.enumerateDraggingItems(options: [], for: nil, classes: [NSFilePromiseReceiver.self, NSURL.self], searchOptions: searchOptions) { draggingItem, _, _ in
      switch draggingItem.item {
      case let filePromiseReceiver as NSFilePromiseReceiver:
        group.enter()
        filePromiseReceiver.receivePromisedFiles(atDestination: self.destinationURL, options: [:], operationQueue: self.workQueue) { fileURL, error in
          if let error = error {
            debugPrint("error: \(error)")
          } else {
              let data = try? fileURL.bookmarkData()
          items.append([
            "path":fileURL.path,
            "apple-bookmark": data,
          ])
          }
          group.leave()
        }
      case let fileURL as URL:
          let data = try? fileURL.bookmarkData()
          
        items.append([
          "path":fileURL.path,
          "apple-bookmark": data,
        ])
      default: break
      }
    }

    group.notify(queue: .main) {
      self.channel.invokeMethod("performOperation_macos", arguments: items)
    }
    return true
  }

  func convertPoint(_ location: NSPoint) -> [CGFloat] {
    return [location.x, bounds.height - location.y]
  }
}
