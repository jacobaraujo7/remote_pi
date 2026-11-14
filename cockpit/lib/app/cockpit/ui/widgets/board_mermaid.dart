import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'webview_chrome.dart';

typedef MermaidDrawing = ({String source, String? thumbnail});

Future<MermaidDrawing?> editMermaid(BuildContext context, String? source) =>
    showDialog<MermaidDrawing>(
      context: context,
      builder: (_) => _MermaidDialog(source: source),
    );

class _MermaidDialog extends StatefulWidget {
  const _MermaidDialog({this.source});
  final String? source;
  @override
  State<_MermaidDialog> createState() => _MermaidState();
}

class _MermaidState extends State<_MermaidDialog> {
  late final input = TextEditingController(
    text: widget.source ?? 'flowchart LR\n    A[Start] --> B[End]\n',
  );
  InAppWebViewController? web;
  String? rendered, error;
  bool rendering = false;
  Map<String, String> examples = {};
  static const shell = """<!doctype html><html><head>
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:">
<style>body{font:14px sans-serif;margin:12px}svg{max-width:100%;height:auto}</style>
</head><body><main></main></body></html>""";
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> load(InAppWebViewController controller) async {
    try {
      final js = await rootBundle.loadString('assets/board/mermaid.min.js');
      await controller.evaluateJavascript(source: js);
      // ZenUML uses preferences even for a document with an opaque origin.
      await controller.evaluateJavascript(
        source:
            "try { void localStorage.length; } catch (_) { const data=new Map(); Object.defineProperty(window,'localStorage',{value:{getItem:k=>data.get(k)??null,setItem:(k,v)=>data.set(k,String(v)),removeItem:k=>data.delete(k),clear:()=>data.clear()}}); }",
      );
      final zen = await rootBundle.loadString(
        'assets/board/mermaid-zenuml.min.js',
      );
      await controller.evaluateJavascript(source: zen);
      await controller.callAsyncJavaScript(
        functionBody:
            "await mermaid.registerExternalDiagrams([globalThis['mermaid-zenuml']]);",
      );
      await controller.evaluateJavascript(
        source:
            "mermaid.initialize({startOnLoad:false,securityLevel:'strict',suppressErrorRendering:true});",
      );
      if (!mounted) return;
      final catalog =
          jsonDecode(await rootBundle.loadString('assets/board/examples.json'))
              as Map;
      if (!mounted) return;
      examples = catalog.cast<String, String>();
      web = controller;
      await preview();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> preview() async {
    if (web == null || rendering) return;
    final source = input.text;
    setState(() {
      rendering = true;
      error = null;
      rendered = null;
    });
    try {
      final result = await web!.callAsyncJavaScript(
        arguments: {'diagram': source},
        functionBody: """
        const root=document.querySelector('main');
        root.replaceChildren();
        const result=await mermaid.render('boardDiagram',diagram);
        root.innerHTML=result.svg;
        return true;
      """,
      );
      if (result?.value != true) {
        throw FormatException(result?.error?.toString() ?? 'Mermaid');
      }
      if (mounted) setState(() => rendered = source);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => rendering = false);
    }
  }

  Future<void> file(bool save) async {
    try {
      if (save) {
        final path = await FilePicker.platform.saveFile(
          fileName: 'diagram.mmd',
        );
        if (path != null) {
          await File(path).writeAsBytes(utf8.encode(input.text));
        }
      } else {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['mmd', 'mermaid'],
        );
        final path = picked?.files.single.path;
        if (path == null) return;
        final source = await File(path).readAsString();
        if (mounted) {
          input.text = source;
          await preview();
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.t.cockpit.gallery.board;
    return Dialog(
      child: SizedBox(
        width: 900,
        height: 590,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Mermaid')),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.category_outlined),
                    tooltip: tr.diagramTypes,
                    enabled: examples.isNotEmpty && !rendering,
                    onSelected: (key) async {
                      final replace =
                          input.text.isEmpty ||
                          (await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  content: Text(tr.replaceSource),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(tr.discard),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text(tr.apply),
                                    ),
                                  ],
                                ),
                              ) ??
                              false);
                      if (!replace) return;
                      if (!mounted) return;
                      input.text = examples[key]!;
                      await preview();
                    },
                    itemBuilder: (_) => [
                      for (final key in examples.keys)
                        PopupMenuItem(value: key, child: Text(key)),
                    ],
                  ),
                  IconButton(
                    tooltip: tr.importMmd,
                    onPressed: rendering ? null : () => file(false),
                    icon: const Icon(Icons.file_open),
                  ),
                  IconButton(
                    tooltip: tr.exportMmd,
                    onPressed: () => file(true),
                    icon: const Icon(Icons.save_alt),
                  ),
                  IconButton(
                    tooltip: tr.preview,
                    onPressed: web == null || rendering ? null : preview,
                    icon: const Icon(Icons.play_arrow),
                  ),
                  IconButton(
                    tooltip: tr.apply,
                    onPressed: rendered == input.text
                        ? () async {
                            final source = input.text;
                            final bytes = await web!.takeScreenshot();
                            if (context.mounted) {
                              Navigator.pop(context, (
                                source: source,
                                thumbnail: bytes == null
                                    ? null
                                    : base64Encode(bytes),
                              ));
                            }
                          }
                        : null,
                    icon: const Icon(Icons.check),
                  ),
                  CloseButton(onPressed: () => Navigator.pop(context)),
                ],
              ),
              if (rendering) const LinearProgressIndicator(),
              if (error != null) SelectableText(error!, maxLines: 3),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        onChanged: (_) => setState(() => rendered = null),
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: WebViewEnvironmentGate(
                        builder: (context, environment) => InAppWebView(
                          webViewEnvironment: environment,
                          initialData: InAppWebViewInitialData(data: shell),
                          initialSettings: InAppWebViewSettings(
                            javaScriptEnabled: true,
                            useShouldOverrideUrlLoading: true,
                            allowFileAccess: false,
                            allowContentAccess: false,
                            javaScriptCanOpenWindowsAutomatically: false,
                          ),
                          shouldOverrideUrlLoading: (_, action) async =>
                              action.request.url?.toString() == 'about:blank'
                              ? NavigationActionPolicy.ALLOW
                              : NavigationActionPolicy.CANCEL,
                          onLoadStop: (web, _) => load(web),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
