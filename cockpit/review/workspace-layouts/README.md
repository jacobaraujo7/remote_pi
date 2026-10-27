# Workspace layout previews

These PNGs render the production WorkspaceExperience, WorkspaceBoxList, WorkspaceGraphView and WorkspaceBoxInspector widgets with fictional sessions. They are component previews, not operating-system screenshots or proof of macOS execution. The preview terminal header is supplied by the fixture; desktop chrome and sidebars are omitted.

The offline renderer uses bundled Geist in place of production Google Fonts, which load at runtime. Unavailable context/process measurements remain unavailable; no agent or command is started.

Regenerate from cockpit/: `flutter test tool/design/render_workspace_layouts_test.dart`.

- boxes.png: searchable/filterable list, manual drag handles and 60% terminal preview.
- graph.png: planned relationship and 35% terminal preview.
- inspector.png: shared optional name/function/tool/model form and explicit session actions.
