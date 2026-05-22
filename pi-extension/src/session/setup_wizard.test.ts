import { describe, expect, test, vi } from "vitest";
import { mkdtempSync, existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runSetupWizard, type WizardUI } from "./setup_wizard.js";
import {
  loadLocalConfig,
  localConfigExists,
  saveLocalConfig,
  effectiveAutoStartRelay,
} from "./local_config.js";

const YES = "Yes";
const NO = "No";

function tmpCwd(): string {
  return mkdtempSync(join(tmpdir(), "pi-wiz-"));
}

/** Sequencing helper: returns a UI mock that replays canned answers in order. */
function makeUI(answers: Array<string | undefined>): WizardUI & {
  inputCalls: Array<{ title: string; defaultValue?: string }>;
  selectCalls: Array<{ title: string; options: string[] }>;
  notifies: Array<{ msg: string; kind: string }>;
} {
  const queue = [...answers];
  const inputCalls: Array<{ title: string; defaultValue?: string }> = [];
  const selectCalls: Array<{ title: string; options: string[] }> = [];
  const notifies: Array<{ msg: string; kind: string }> = [];
  return {
    inputCalls,
    selectCalls,
    notifies,
    input: vi.fn().mockImplementation(async (title: string, opts?: { defaultValue?: string }) => {
      inputCalls.push({ title, defaultValue: opts?.defaultValue });
      return queue.shift();
    }),
    select: vi.fn().mockImplementation(async (title: string, options: string[]) => {
      selectCalls.push({ title, options });
      return queue.shift();
    }),
    notify: vi.fn().mockImplementation((msg: string, kind: string) => {
      notifies.push({ msg, kind });
    }),
  };
}

describe("runSetupWizard", () => {
  test("1) accepts defaults end-to-end → returns LocalConfig", async () => {
    const ui = makeUI(["my-agent", "my-session", YES, YES]);
    const cfg = await runSetupWizard(ui, {
      agent_name: "default-name",
      session_name: "default-session",
      auto_start_relay: true,
    });
    expect(cfg).toEqual({
      agent_name: "my-agent",
      session_name: "my-session",
      auto_start_relay: true,
    });
  });

  test("2) empty agent_name → re-prompts once, then 2nd blank cancels", async () => {
    const ui = makeUI(["   ", "", YES, YES]);
    const cfg = await runSetupWizard(ui, {
      agent_name: "foo",
      session_name: "foo",
      auto_start_relay: true,
    });
    // Both attempts blank → wizard returns null.
    expect(cfg).toBeNull();
    expect(ui.notifies.some((n) => n.msg.includes("empty"))).toBe(true);
  });

  test("3a) cancel on first prompt → returns null", async () => {
    const ui = makeUI([undefined]);
    const cfg = await runSetupWizard(ui, {
      agent_name: "foo", session_name: "foo", auto_start_relay: true,
    });
    expect(cfg).toBeNull();
  });

  test("3b) cancel on final confirm → returns null (NO chosen)", async () => {
    const ui = makeUI(["agent", "session", YES, NO]);
    const cfg = await runSetupWizard(ui, {
      agent_name: "foo", session_name: "foo", auto_start_relay: true,
    });
    expect(cfg).toBeNull();
  });

  test("4) localConfigExists() reflects fresh cwd (config absent before save)", () => {
    const cwd = tmpCwd();
    expect(localConfigExists(cwd)).toBe(false);
    saveLocalConfig(cwd, {
      agent_name: "x",
      session_name: "y",
      auto_start_relay: true,
    });
    expect(localConfigExists(cwd)).toBe(true);
    const persisted = loadLocalConfig(cwd);
    expect(persisted).toMatchObject({
      agent_name: "x",
      session_name: "y",
      auto_start_relay: true,
    });
  });

  test("5) /remote-pi setup with existing config: wizard uses current as defaults", async () => {
    // We don't invoke the real /remote-pi setup handler here (that wires
    // through index.ts); instead we simulate the data flow: pre-existing
    // config + wizard run with those defaults.
    const cwd = tmpCwd();
    saveLocalConfig(cwd, {
      agent_name: "old", session_name: "old-session", auto_start_relay: false,
    });
    const current = loadLocalConfig(cwd);
    expect(current.auto_start_relay).toBe(false);

    const ui = makeUI(["new", "new-session", YES, YES]);
    const cfg = await runSetupWizard(ui, {
      agent_name: current.agent_name!,
      session_name: current.session_name!,
      auto_start_relay: effectiveAutoStartRelay(current),
    });
    expect(cfg).toMatchObject({
      agent_name: "new",
      session_name: "new-session",
      auto_start_relay: true,
    });
    saveLocalConfig(cwd, cfg!);
    const updated = loadLocalConfig(cwd);
    expect(updated.agent_name).toBe("new");
    expect(updated.auto_start_relay).toBe(true);
  });

  test("6) legacy config without auto_start_relay → treated as true", () => {
    const cwd = tmpCwd();
    // Write a legacy file without auto_start_relay
    const cfgPath = join(cwd, ".pi", "remote-pi", "config.json");
    // saveLocalConfig fills it in, so write raw to disk
    const { mkdirSync, writeFileSync } = require("node:fs") as typeof import("node:fs");
    mkdirSync(join(cwd, ".pi", "remote-pi"), { recursive: true });
    writeFileSync(
      cfgPath,
      JSON.stringify({ agent_name: "legacy", session_name: "legacy-sess" }, null, 2),
    );

    const loaded = loadLocalConfig(cwd);
    expect(loaded.auto_start_relay).toBeUndefined();
    expect(effectiveAutoStartRelay(loaded)).toBe(true);

    // After re-save (anything), auto_start_relay gets locked in:
    saveLocalConfig(cwd, { agent_name: "legacy-renamed" });
    const reloaded = loadLocalConfig(cwd);
    expect(reloaded.auto_start_relay).toBe(true);
    expect(reloaded.agent_name).toBe("legacy-renamed");
    expect(existsSync(cfgPath)).toBe(true);
    // Verify on-disk content
    const raw = JSON.parse(readFileSync(cfgPath, "utf8")) as Record<string, unknown>;
    expect(raw["auto_start_relay"]).toBe(true);
  });
});
