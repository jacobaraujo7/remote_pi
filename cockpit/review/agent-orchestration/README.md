# Agent Orchestration layouts

These PNGs render the production `OrchestrationView`, Boxes/Graph/inspector, `OrchestrationTerminalsView`, `StablePaneHost` and xterm terminals with fictional sessions. The orchestration owns its lower terminal area; the adjacent workspace terminal is a separate session/controller. The tab-strip labels are fixture chrome; OS window controls and sidebars are omitted. They are not desktop screenshots and do not demonstrate manual macOS acceptance. Bundled Geist is loaded offline for deterministic rendering, including the terminal fixture.

Reproduce from `cockpit/`:

```
flutter test --no-pub tool/design/render_orchestration_layouts_test.dart
```

The same test checks mode switching preserves the internal and adjacent terminal elements without consulting the global terminal inventory and renders narrow Graph and inspector layouts without Flutter overflow exceptions.

- `boxes-dock.png`: searchable/reorderable Boxes above owned terminals, beside an independent workspace dock.
- `graph-dock.png`: planned links and runtime legend above owned terminals, beside an independent workspace dock.
- `inspector-dock.png`: configuration remains inside the orchestration dock.
- `narrow-inspector.png`: overlay restricted to the app pane.
- `narrow-graph.png`: graph navigation in a narrow dock.
