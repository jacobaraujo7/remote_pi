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
  use_relay: boolean;
}

const YES = "Yes";
const NO = "No";
const CANCEL_TOKEN = "__cancel__";

/**
 * Runs the 2-question setup wizard. Returns the chosen config on confirm, or
 * null when the user cancels any prompt.
 *
 * Prompts:
 *   1. Agent name (default: parent/folder of cwd)
 *   2. Use the relay on this terminal? (yes/no) — gates connection to the
 *      remote mesh (mobile devices + other PCs over the relay). "No" means
 *      local-only: this Pi joins the UDS mesh but doesn't open WSS.
 *   Final: review + confirm "Save and activate?" yes/no
 *
 * Daemon mode (run agents 24/7 via systemd/launchd) is intentionally NOT in
 * the wizard — it's an explicit, separate opt-in via `/remote-pi install`.
 *
 * The local UDS mesh is always single per machine ("local" session) — no
 * session question. All Pis on the same machine see each other through
 * the same broker.
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

  ui.notify?.(
    "The relay forwards encrypted messages to the Remote Pi mobile app and other PCs in your mesh. Skip this if you only want a local-only mesh on this machine.",
    "info",
  );
  const useRelayChoice = await ui.select(
    "Use the relay on this terminal to connect to the remote mesh (mobile + PCs)?",
    defaults.use_relay ? [YES, NO] : [NO, YES],
  );
  if (!useRelayChoice) return null;
  const auto_start_relay = useRelayChoice === YES;

  // Review + confirm
  const summary = [
    `  Agent name:    ${agent_name}`,
    `  Use relay:     ${auto_start_relay ? YES : NO}`,
  ].join("\n");
  ui.notify?.(`Summary:\n${summary}`, "info");

  const confirm = await ui.select("Save and activate?", [YES, NO]);
  if (confirm !== YES) return null;

  return { agent_name, auto_start_relay };
}

/**
 * Asks the user for free text. The Pi SDK's `ui.input` does not pre-fill the
 * field with `defaultValue` (the SDK ignores that option), so we surface the
 * default in the prompt label and treat an empty submission as "accept the
 * default" — the standard CLI convention. Falls back to `select` when the
 * SDK doesn't expose `input` at all.
 */
async function _askText(
  ui: WizardUI,
  title: string,
  defaultValue: string,
): Promise<string | null> {
  const titleWithHint = `${title} (default: ${defaultValue})`;
  const raw = ui.input
    ? await ui.input(titleWithHint, { defaultValue })
    : await ui.select(titleWithHint, [defaultValue, CANCEL_TOKEN]);
  if (raw === undefined) return null;
  if (raw === CANCEL_TOKEN) return null;
  const trimmed = raw.trim();
  // Empty submission = accept the default. No re-prompt, no warning — the
  // user explicitly asked for the default by hitting enter.
  return trimmed.length > 0 ? trimmed : defaultValue;
}
