/**
 * Pi-only extension entry point.
 *
 * Pi resolves its bundled core packages for static imports from this manifest
 * entry. Keep the CLI in `index.ts` free of those imports: its `remote-pi`
 * executable is also used outside a Pi extension host.
 */
import { SettingsManager, convertToPng } from "@earendil-works/pi-coding-agent";
import { Box, Container, Image, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import extension, { configurePiRuntime } from "./index.js";

configurePiRuntime({
  SettingsManager,
  convertToPng,
  Box,
  Container,
  Image,
  Text,
  Type,
});

export default extension;
