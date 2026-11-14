---
name: cockpit-canvas
description: Draw or revise flowcharts, swimlanes, architecture diagrams and Mermaid in Cockpit. Use for editable Gallery Board (.board) documents, Mermaid source (.mmd).
---

# Draw diagrams in Cockpit

Choose the representation by what the person will edit next.

- **Move individual steps, connect shapes or arrange a canvas.** Use a Gallery **Board**. For a workspace file, follow [the native document format](references/board.md). Open the finished document from the workspace tree or with `cockpit open "path/to/diagram.board"` inside a Cockpit terminal.
- **Maintain a diagram as text.** Write Mermaid in the requested Markdown fence or as plain source in a UTF-8 `.mmd` file. For a Board containing Mermaid, use [the Mermaid workflow](references/mermaid.md).

Use the language and terminology of the people reading the drawing. Give process steps verb labels, phrase decisions as questions and label each outgoing path with its outcome. Use lanes for ownership and containers for system boundaries. Keep a consistent reading direction and leave room for connector captions. Pair color with a label or shape so approval and rejection remain distinguishable in monochrome.
