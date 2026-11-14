# Editable Gallery Canvas Board

Create the document from the Gallery or write UTF-8 Markdown to a file with the `.board` extension. Preserve document and item IDs when revising. Generate a fresh document ID for new files (the Gallery uses 32 hexadecimal digits). Legacy JSON version 1 opens directly. Saving an edit writes Markdown version 2.

```markdown
# Canvas Board

- version: 2
- id: "45fb1dd29ec34876a25a37c11212c950"

## process

- id: "request"
- x: 80
- y: 80
- width: 160
- height: 64
- color: "#6EA8FE"
- label: "Receber pedido"

## decision

- id: "approve"
- x: 360
- y: 80
- width: 160
- height: 80
- label: "Pedido aprovado?"

## arrow

- id: "link"
- from: "request"
- to: "approve"
- x: 0
- y: 0
- width: 1
- height: 1
- label: ""
```

Each level-two heading starts an object. Properties are Markdown list items in the form `- key: value`. Each value uses JSON literal syntax so quoted text, numbers, arrays and escaped newlines round-trip exactly. The header accepts `version` and an optional document `id`. Every item needs a unique nonempty string ID, finite x/y coordinates measured from its top-left corner, positive width/height and a string label.

Use `process`, `decision`, `note`, `text`, `service`, `container` or `lane` for shapes. Put large lanes and containers before their contents. Give items the same optional `group` string to move them together. An `arrow` binds `from` and `to` to existing non-arrow IDs. A `stroke` stores a nonempty `points` array of [x,y] offsets from its origin. Optional `color` is RGB in "#RRGGBB" form. It colors the fill of a shape or the ink of text, strokes and arrows.

For a `mermaid` section, put its source in a Mermaid fence below its properties, in place of the label bullet. Use a fence longer than backtick runs inside the source. Keep the optional base64 PNG `thumbnail` while preserving existing source. When the source changes, regenerate the thumbnail in the Mermaid editor. The quoted `label` form also accepts Mermaid with exact CRLF line endings.

Reopen the file from the tree and move a connected shape to check its endpoints. Export Markdown for native data, XML or .drawio for diagrams.net, and HTML, SVG, PNG or PDF for viewing. See the Mermaid reference for .mmd exchange.
