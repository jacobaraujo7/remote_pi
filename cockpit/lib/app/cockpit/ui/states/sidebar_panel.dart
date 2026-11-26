/// Stable names persisted in the existing per-project layout document.
enum SidebarPanel { files, search, sourceControl, database, gallery, telemetry }

const kSidebarPanelKey = 'sidebarPanel';

SidebarPanel sidebarPanelOf(Map<String, dynamic>? document) =>
    SidebarPanel.values
        .where((panel) => panel.name == document?[kSidebarPanelKey])
        .firstOrNull ??
    SidebarPanel.files;
