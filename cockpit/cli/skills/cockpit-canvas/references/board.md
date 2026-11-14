# Editable Gallery Canvas Board

Create the document from the Gallery or write UTF-8 Markdown to a file with the `.board` extension. Preserve document and item IDs when revising. Generate a fresh document ID for new files (the Gallery uses 32 hexadecimal digits). Both early workspace formats (JSON v1 and Markdown v2) open directly. Saving an edit writes Markdown version 3.

```markdown
---
version: 3
id: 45fb1dd29ec34876a25a37c11212c950
---

# Canvas Board

## process

- id: request
- x: 80
- y: 80
- width: 160
- height: 64
- color: #6EA8FE

> Receber pedido

## decision

- id: approve
- x: 360
- y: 80
- width: 160
- height: 80

> Pedido aprovado?

## arrow

- id: link
- from: request
- to: approve
- x: 0
- y: 0
- width: 1
- height: 1
```

Frontmatter identifies the document version and optional ID. Each level-two heading starts an object. Properties are Markdown bullets with plain text or numbers. Give every item a unique ID, finite x/y coordinates (top-left) and positive width/height. Write its visible label as a Markdown blockquote below the properties, using a quote marker for each line. Omit the blockquote for an unlabeled item. Keep existing IDs when editing. All text, including punctuation, is literal in the label.

Use `process`, `decision`, `note`, `text`, `service`, `container` or `lane` for shapes. Put large lanes and containers before their contents. Give items the same optional `group` string to move them together. An `arrow` binds `from` and `to` to existing non-arrow IDs. A `stroke` stores a nonempty list under `- points:`. Indent each coordinate pair by two spaces, for example `  - 12, 36`. These are offsets from its origin. Optional `color` is RGB in "#RRGGBB" form. It colors the fill of a shape or the ink of text, strokes and arrows.

For a `mermaid` section, put its source in a Mermaid fence below its properties, in place of the blockquote. Use a fence longer than backtick runs inside the source. Keep the optional base64 PNG `thumbnail` while preserving existing source. When the source changes, regenerate the thumbnail in the Mermaid editor. The optional `line-endings` property preserves CRLF and mixed line endings inside existing labels. New documents can omit it.

Reopen the file from the tree and move a connected shape to check its endpoints. Choose Export, then the entire document or the selection. The entire document supports PNG, PDF, HTML, SVG, XML (draw.io), Markdown, draw.io, Excalidraw and Mermaid (.mmd). The selection supports PNG, PDF, HTML and SVG. The save dialog suggests the board’s filename. Keep the .board workspace file for future edits. PDF uses a single A4 page. See the Mermaid reference for .mmd exchange.
