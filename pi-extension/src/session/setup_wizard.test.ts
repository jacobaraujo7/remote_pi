import { describe, expect, test, vi } from "vitest";
import { mkdtempSync, existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runSetupWizard, type WizardUI } from "./setup_wizard.js";
import {
  defaultAgentName,
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

describe("runSetupWizard (2 prompts + confirm)", () => {
  test("1) accepts answers end-to-end → returns config (no daemon prompt)", async () => {
    // Sequence: agent name (input), use_relay (Yes), confirm (Yes)
    const ui = makeUI(["my-agent", YES, YES]);
    const cfg = await runSetupWizard(ui, {
      agent_name: "default-name",
      use_relay: true,
    });
    expect(cfg).toEqual({
      agent_name: "my-agent",
      auto_start_relay: true,
    });
  });

  test("2) empty agent_name submission accepts the default", async () => {
    // Empty input → wizard takes the default ("foo"), then relay Yes, confirm Yes.
    const ui = makeUI(["", YES, YES]);
    const cfg = await runSetupWizard(ui, {
      agent_name: "foo",
      use_relay: true,
    });
    expect(cfg).toEqual({
      agent_name: "foo",
      auto_start_relay: true,
    });
  });

  test("2b) prompt labels surface the default as hint; no daemon prompt", async () => {
    const ui = makeUI(["my-agent", YES, YES]);
    await runSetupWizard(ui, {
      agent_name: "default-name",
      use_relay: true,
    });
    expect(ui.inputCalls.map((c) => c.title)).toEqual([
      "Agent name: (default: default-name)",
    ]);
    expect(ui.selectCalls.map((c) => c.title)).toEqual([
      "Use the relay on this terminal to connect to the remote mesh (mobile + PCs)?",
      "Save and activate?",
    ]);
  });

  test("3a) cancel on first prompt → returns null", async () => {
    const ui = makeUI([undefined]);
    const cfg = await runSetupWizard(ui, {
      agent_name: "foo", use_relay: true,
    });
    expect(cfg).toBeNull();
  });

  test("3b) cancel on relay prompt → returns null", async () => {
    const ui = makeUI(["agent", undefined]);
    const cfg = await runSetupWizard(ui, {
      agent_name: "foo", use_relay: true,
    });
    expect(cfg).toBeNull();
  });

  test("3c) cancel on final confirm → returns null (NO chosen)", async () => {
    const ui = makeUI(["agent", YES, NO]);
    const cfg = await runSetupWizard(ui, {
      agent_name: "foo", use_relay: true,
    });
    expect(cfg).toBeNull();
  });

  test("4) use_relay=No produces auto_start_relay=false", async () => {
    // When default is false, the picker shows [No, Yes]. We answer with the
    // first ("No") to confirm the off path. Then confirm Yes.
    const ui = makeUI(["agent", NO, YES]);
    const cfg = await runSetupWizard(ui, {
      agent_name: "foo", use_relay: false,
    });
    expect(cfg).toEqual({
      agent_name: "agent",
      auto_start_relay: false,
    });
  });

  test("5) relay-prompt informational notify precedes its question", async () => {
    const ui = makeUI(["agent", YES, YES]);
    await runSetupWizard(ui, {
      agent_name: "foo", use_relay: true,
    });
    // The relay-context notify must appear in the notify log.
    expect(
      ui.notifies.some((n) =>
        n.msg.includes("relay forwards encrypted messages") ||
        n.msg.includes("Remote Pi mobile app"),
      ),
    ).toBe(true);
    // No daemon-context notify — daemon mode was removed from the wizard.
    expect(
      ui.notifies.some((n) => n.msg.includes("Daemon mode")),
    ).toBe(false);
  });
});

describe("localConfig integration with the wizard", () => {
  test("localConfigExists() reflects fresh cwd (config absent before save)", () => {
    const cwd = tmpCwd();
    expect(localConfigExists(cwd)).toBe(false);
    saveLocalConfig(cwd, {
      agent_name: "x",
      auto_start_relay: true,
    });
    expect(localConfigExists(cwd)).toBe(true);
    const persisted = loadLocalConfig(cwd);
    expect(persisted).toMatchObject({
      agent_name: "x",
      auto_start_relay: true,
    });
  });

  test("/remote-pi setup with existing config: wizard uses current as defaults", async () => {
    // Simulates the data flow without invoking the real handler.
    const cwd = tmpCwd();
    saveLocalConfig(cwd, {
      agent_name: "old", auto_start_relay: false,
    });
    const current = loadLocalConfig(cwd);
    expect(current.auto_start_relay).toBe(false);

    const ui = makeUI(["new", YES, YES]);
    const cfg = await runSetupWizard(ui, {
      agent_name: current.agent_name!,
      use_relay: effectiveAutoStartRelay(current),
    });
    expect(cfg).toEqual({
      agent_name: "new",
      auto_start_relay: true,
    });
    // The wizard now returns a plain LocalConfig — persist it directly.
    saveLocalConfig(cwd, cfg!);
    const updated = loadLocalConfig(cwd);
    expect(updated.agent_name).toBe("new");
    expect(updated.auto_start_relay).toBe(true);
  });

  test("legacy config without auto_start_relay → treated as true", () => {
    const cwd = tmpCwd();
    const cfgPath = join(cwd, ".pi", "remote-pi", "config.json");
    const { mkdirSync, writeFileSync } = require("node:fs") as typeof import("node:fs");
    mkdirSync(join(cwd, ".pi", "remote-pi"), { recursive: true });
    writeFileSync(
      cfgPath,
      JSON.stringify({ agent_name: "legacy" }, null, 2),
    );

    const loaded = loadLocalConfig(cwd);
    expect(loaded.auto_start_relay).toBeUndefined();
    expect(effectiveAutoStartRelay(loaded)).toBe(true);

    saveLocalConfig(cwd, { agent_name: "legacy-renamed" });
    const reloaded = loadLocalConfig(cwd);
    expect(reloaded.auto_start_relay).toBe(true);
    expect(reloaded.agent_name).toBe("legacy-renamed");
    expect(existsSync(cfgPath)).toBe(true);
    const raw = JSON.parse(readFileSync(cfgPath, "utf8")) as Record<string, unknown>;
    expect(raw["auto_start_relay"]).toBe(true);
  });

  test("legacy config with session_name field is silently dropped on load", () => {
    // Pre-refactor configs carried session_name. After the surface cleanup,
    // local UDS mesh is always a single fixed session — the field has no
    // meaning. Load should ignore it without error and not persist it back.
    const cwd = tmpCwd();
    const cfgPath = join(cwd, ".pi", "remote-pi", "config.json");
    const { mkdirSync, writeFileSync } = require("node:fs") as typeof import("node:fs");
    mkdirSync(join(cwd, ".pi", "remote-pi"), { recursive: true });
    writeFileSync(
      cfgPath,
      JSON.stringify({
        agent_name: "legacy",
        session_name: "old-session",
        auto_start_relay: true,
      }, null, 2),
    );

    const loaded = loadLocalConfig(cwd);
    expect(loaded.agent_name).toBe("legacy");
    expect((loaded as Record<string, unknown>)["session_name"]).toBeUndefined();
    expect(loaded.auto_start_relay).toBe(true);
  });
});

describe("defaultAgentName", () => {
  test("returns parent/folder when both are meaningful", () => {
    expect(defaultAgentName("/Users/jacob/Projects/remote_pi")).toBe("Projects/remote_pi");
    expect(defaultAgentName("/home/dev/myapp/backend")).toBe("myapp/backend");
  });

  test("returns just folder when parent isn't meaningful", () => {
    expect(defaultAgentName("/")).toBe("agent");
    expect(defaultAgentName("/foo")).toBe("foo");  // parent is "/"
  });

  test("falls back to 'agent' for empty/root edge cases", () => {
    expect(defaultAgentName("/")).toBe("agent");
  });
});
