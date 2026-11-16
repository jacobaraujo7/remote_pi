---
name: cockpit-export
description: Export a workspace drawing or document into a requested image or publication format using local tools. Use for agent-generated previews, high-resolution document attachments and format conversion.
---

Choose the converter for the source and the reader's destination. Keep the editable source. Write the derivative under a distinct name with the requested extension.

For Cockpit Markdown Canvas files, render SVG with the bundled Dart renderer. In an installed skill, use the renderer directory as the working directory. Run `dart pub get` there once and then `dart run tool/export_canvas.dart "<absolute input.canvas>" "<absolute output.svg>"`. In a Cockpit checkout the same command runs directly from the `cockpit` package after dependencies are resolved. The output path must be new. This renderer also opens older Cockpit .board files.

Use SVG for zoomable diagrams where the document viewer supports it. Native labels, arrows and shapes remain vector geometry. For raster-only destinations, rasterize the SVG at the intended display width multiplied by the requested zoom. For example, a 1,200 px figure intended for 4× zoom needs a 4,800 px PNG. With Inkscape available, run `inkscape "preview.svg" --export-type=png --export-filename="preview.png" --export-width=4800`. Preserve aspect ratio. Raster thumbnails already embedded in the source keep their original resolution.

For other source types, use their native renderer or a locally available converter that reads the actual format. Open the generated file in a compatible viewer, verify its format and dimensions, and inspect labels, arrows and clipping at the target zoom. Where a destination resizes or compresses images, check the embedded result too. Return the output path and report any loss of fidelity that matters to the reader.
