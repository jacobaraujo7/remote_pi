import type { LocalConfig } from "./local_config.js";

/**
 * Pi SDK UI surface needed by the wizard. Subset of `ExtensionUIContext` —
 * declared inline so tests can mock cleanly without dragging the full
 * ExtensionContext shape.
 */
export interface WizardUI {
  /** Free-text prompt. Returns the entered string, or undefined if cancelled. */
  input?: (title: string, options?: { defaultValue?: string }) => Promise<string | undefined>;
  /** Picker. Returns the picked option, or undefined if cancelled. */
  select: (title: string, options: string[]) => Promise<string | undefined>;
  /** Non-blocking notification. Used for inline validation feedback. */
  notify?: (msg: string, kind: "info" | "warning" | "error") => void;
}

export interface WizardDefaults {
  agent_name: string;
  session_name: string;
  auto_start_relay: boolean;
}

const YES = "Yes";
const NO = "No";
const CANCEL_TOKEN = "__cancel__";

/**
 * Runs the 3-question setup wizard. Returns the chosen config on confirm,
 * or null when the user cancels any prompt.
 *
 * Prompts:
 *   1. Agent name (default: basename of cwd)
 *   2. Session name (default: basename of cwd)
 *   3. Auto-start relay? (yes/no) — relay lets the mobile app connect to this Pi
 *   Final: review + confirm "Save and activate?" yes/no
 */
export async function runSetupWizard(
  ui: WizardUI,
  defaults: WizardDefaults,
): Promise<LocalConfig | null> {
  const agent_name = await _askText(
    ui,
    "Agent name:",
    defaults.agent_name,
  );
  if (agent_name === null) return null;

  const session_name = await _askText(
    ui,
    "Default session:",
    defaults.session_name,
  );
  if (session_name === null) return null;

  ui.notify?.(
    "The relay lets the Remote Pi mobile app connect to this Pi over the network. Enable it to allow the app to send prompts and receive responses; disable for local-only use.",
    "info",
  );
  const autoChoice = await ui.select(
    "Auto-start the relay (for mobile app access)?",
    defaults.auto_start_relay ? [YES, NO] : [NO, YES],
  );
  if (!autoChoice) return null;
  const auto_start_relay = autoChoice === YES;

  // Review + confirm
  const summary = [
    `  Agent name:       ${agent_name}`,
    `  Default session:  ${session_name}`,
    `  Auto-start relay: ${auto_start_relay ? YES : NO}`,
  ].join("\n");
  ui.notify?.(`Summary:\n${summary}`, "info");

  const confirm = await ui.select("Save and activate?", [YES, NO]);
  if (confirm !== YES) return null;

  return { agent_name, session_name, auto_start_relay };
}

/**
 * Asks the user for free text. Falls back to `select` with the default as the
 * only option when the SDK doesn't expose `input` (some Pi modes). Re-prompts
 * once on empty/whitespace input; second blank counts as cancel.
 */
async function _askText(
  ui: WizardUI,
  title: string,
  defaultValue: string,
): Promise<string | null> {
  for (let attempt = 0; attempt < 2; attempt++) {
    const raw = ui.input
      ? await ui.input(title, { defaultValue })
      : await ui.select(`${title} (default: ${defaultValue})`, [defaultValue, CANCEL_TOKEN]);
    if (raw === undefined) return null;
    if (raw === CANCEL_TOKEN) return null;
    const trimmed = raw.trim();
    if (trimmed.length > 0) return trimmed;
    ui.notify?.("Value required — cannot be empty.", "warning");
  }
  // 2 blanks in a row → treat as cancel
  return null;
}
