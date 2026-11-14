---
name: cockpit-canvas
description: Draw or revise flowcharts, swimlanes, architecture diagrams and Mermaid in Cockpit. Use for editable Gallery Canvas Board (.board) documents, Mermaid source (.mmd).
---

# Draw diagrams in Cockpit

Choose the representation by what the person will edit next.

Start from the [approval flow](templates/approval.board) for a simple process or the [swimlane example](templates/swimlanes.board) for a decision crossing team boundaries and a grouped payment service. Copy it into the workspace, give the copy its own document ID, then edit it with your normal text tools.

Work on the local workspace file. Read the current revision before changing it, keep the IDs of existing items, and preserve unrelated sections. Re-read the file immediately before replacing it. If it changed while you were preparing an edit, apply that edit to the latest version and check both connector endpoints. Save the completed Markdown to a temporary file in the same directory and replace the workspace file. An open local Canvas Board watches for that replacement and refreshes automatically. If the change is missing, use Reload and verify the document path.

- **Move individual steps, connect shapes or arrange a canvas.** Use **Canvas Board** in the Gallery. For a workspace file, follow [the native document format](references/board.md). Open the finished document from the workspace tree or with `cockpit open "path/to/diagram.board"` inside a Cockpit terminal.
- **Maintain a diagram as text.** Write Mermaid in the requested Markdown fence or as plain source in a UTF-8 `.mmd` file. For a Board containing Mermaid, use [the Mermaid workflow](references/mermaid.md).

Use the language and terminology of the people reading the drawing. Give process steps verb labels, phrase decisions as questions and label each outgoing path with its outcome. Use lanes for ownership and containers for system boundaries. Keep a consistent reading direction and leave room for connector captions. Pair color with a label or shape so approval and rejection remain distinguishable in monochrome.
