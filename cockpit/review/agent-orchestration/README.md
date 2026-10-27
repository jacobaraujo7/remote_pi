# Agent Orchestration layouts

These PNGs render the production `OrchestrationView`, Boxes/Graph/inspector, `StablePaneHost` and an xterm terminal with fictional sessions. The tab-strip labels are fixture chrome; OS window controls and sidebars are omitted. They are not desktop screenshots and do not demonstrate manual macOS acceptance. Bundled Geist is loaded offline for deterministic rendering, including the terminal fixture.

Reproduce from `cockpit/`:

```
flutter test --no-pub tool/design/render_orchestration_layouts_test.dart
```

The same test checks mode switching preserves the adjacent terminal element and renders narrow Graph and inspector layouts without Flutter overflow exceptions.

- `boxes-dock.png`: searchable/reorderable Boxes beside the terminal.
- `graph-dock.png`: planned links and runtime legend beside the terminal.
- `inspector-dock.png`: configuration remains inside the orchestration dock.
- `narrow-inspector.png`: overlay restricted to the app pane.
- `narrow-graph.png`: graph navigation in a narrow dock.
