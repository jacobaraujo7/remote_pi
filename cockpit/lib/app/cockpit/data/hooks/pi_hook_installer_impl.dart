import 'dart:io';

import 'package:cockpit/app/cockpit/data/hooks/hook_installer_base.dart';

/// Pi auto-loads individual TypeScript files from its extensions directory.
/// This extension reports only lifecycle/identity, and is inert outside a
/// Cockpit terminal. It does not require the Remote Pi extension or an LLM.
class PiHookInstallerImpl extends HookInstallerBase {
  const PiHookInstallerImpl();

  @override
  String get harnessName => 'pi';

  @override
  Future<void> writeConfig({
    required String home,
    required String command,
  }) async {
    final root = Directory('$home/.pi');
    if (!await root.exists()) return;
    final extension = File('${root.path}/agent/extensions/cockpit-status.ts');
    await extension.parent.create(recursive: true);
    if (await extension.exists() && await extension.readAsString() == source) {
      return;
    }
    await extension.writeAsString(source);
  }

  static const source =
      r'''// Managed by Cockpit. Reports no prompts or credentials in terminal output.
import { createConnection } from "node:net";
import { existsSync } from "node:fs";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  async function report(ctx: ExtensionContext, event: string, status: string) {
    const paneId = process.env.COCKPIT_TAB_ID || process.env.COCKPIT_PANE_ID;
    const path = process.env.COCKPIT_STATUS_SOCK;
    const port = Number(process.env.COCKPIT_STATUS_PORT);
    const tok = process.env.COCKPIT_STATUS_TOKEN;
    if (!paneId || (!path && !(tok && port > 0 && port < 65536))) return;
    const sessionFile = ctx.sessionManager.getSessionFile();
    const payload = JSON.stringify({
      paneId, tok, hn: "pi", ev: event, st: status,
      sid: ctx.sessionManager.getSessionId(),
      tx: sessionFile && existsSync(sessionFile) ? sessionFile : undefined,
      pids: [process.pid],
    }) + "\n";
    await new Promise<void>((resolve) => {
      const socket = createConnection(path ? { path } : { host: "127.0.0.1", port });
      const finish = () => { socket.destroy(); resolve(); };
      socket.setTimeout(500, finish);
      socket.on("error", finish);
      socket.on("connect", () => socket.end(payload));
      socket.on("close", resolve);
    });
  }
  pi.on("session_start", async (_event, ctx) => report(ctx, "SessionStart", "idle"));
  pi.on("agent_start", async (_event, ctx) => report(ctx, "UserPromptSubmit", "working"));
  pi.on("agent_end", async (_event, ctx) => report(ctx, "Stop", "idle"));
  pi.on("session_shutdown", async (_event, ctx) => report(ctx, "SessionEnd", "idle"));
}
''';
}
