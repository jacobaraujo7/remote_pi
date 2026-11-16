---
name: cockpit-drawing-attachments
description: Generate a descriptively named Cockpit Canvas drawing and attach a zoomable, revision-specific image and its editable source to a document with a history of changes.
---

Read the destination document and identify the process, system or decision the drawing explains. Use cockpit-canvas to create a native Markdown .canvas file. Name it after its subject, such as aprovacao-financeira-de-reembolsos.canvas. Match the caption and link text to the language of the document.

Follow the document's existing attachment convention. If it has none, use a sibling assets directory. For a new published revision, choose the next unused version and save a snapshot of the editable source alongside the image. Keep the drawing's document and object IDs when revising the same drawing. Render the image from that exact snapshot with cockpit-export. For a document that supports SVG, attach the vector image. Otherwise use a high-resolution PNG sized for the intended zoom.

For Markdown, use relative paths from the document. Example:

```markdown
![Aprovação financeira de reembolsos](assets/aprovacao-financeira-de-reembolsos-v2.svg)

[Ampliar o desenho](assets/aprovacao-financeira-de-reembolsos-v2.svg) · [Editar a revisão 2](assets/aprovacao-financeira-de-reembolsos-v2.canvas)
```

For other document formats, use the document's native image attachment and include a source link or attachment accessible to its readers. Add the revision, date and a short description of the change to the document's history, preserving earlier image and source links. Reuse the existing revision if the same snapshot is already attached. Open the document to verify the figure, zoom and source link before reporting the paths.
