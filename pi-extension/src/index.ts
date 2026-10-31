#!/usr/bin/env node
/**
 * Package entry for both Pi and the shell.
 *
 * - Loaded by Pi (`pi -e dist/index.js`, the `pi.extensions` dir): default-
 *   exports the extension factory from extension.ts.
 * - Run directly (the `remote-pi` bin, the `~/.local/bin/remote-pi` link from
 *   `/remote-pi install` or install.sh, `node dist/index.js <cmd>` from the
 *   Cockpit): runs the standalone CLI (cli.ts).
 *
 * The extension imports the host packages (`@earendil-works/pi-*`, `typebox`)
 * at runtime. They are peerDependencies and Pi-managed installs omit them, so
 * this file loads extension.ts lazily and only when Pi imports it — the CLI
 * path never touches the host (enforced by `cli_imports.test.ts`).
 */

import type { ExtensionFactory } from "@earendil-works/pi-coding-agent";
import { isDirectRun, runCli } from "./cli.js";

export { probeListPeers, _restartSupervisorCommand, type RestartStep } from "./commands.js";
export type { RelayConnectivity, RemoteState } from "./extension.js";

let extension: ExtensionFactory | undefined;
if (isDirectRun(import.meta.url)) {
  await runCli(process.argv.slice(2));
} else {
  extension = (await import("./extension.js")).default;
}

export default extension;
