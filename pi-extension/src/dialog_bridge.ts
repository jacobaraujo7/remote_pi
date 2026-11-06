// Forward generic extension dialogs (ctx.ui.select / confirm / input / editor)
// to paired apps over the extension_ui_request/response contract (issue #87).
//
// Any extension can block a turn on a dialog: permission gates confirming a
// tool call, ask-style tools falling back to `select`/`input` in RPC mode, etc.
// Without this, a dialog raised in a headless daemon (`pi --mode rpc`) goes to
// the supervisor's stdout and is never answered, and one raised in the TUI can
// only be answered at the desk. Either way a phone-driven session stalls.
//
// All extensions share one `ctx.ui` object (ExtensionRunner.uiContext), so we
// wrap its dialog methods in place. Each call races the original dialog
// (TUI or RPC) against the app:
//   - app answers first  -> abort the original via its signal, return the
//     app's value;
//   - original settles first (desk answer, timeout, caller abort) -> broadcast
//     a `notify` with the same id, which the app treats as "dismiss".
// Pending requests are replayed on `session_sync` for late-joining peers.

import { randomUUID } from "node:crypto";
import type {
  ExtensionUiRequestWire,
  ExtensionUiResponseWire,
  ServerMessage,
} from "./protocol/types.js";

/** Matches pi's ExtensionUIDialogOptions without importing SDK types. */
interface DialogOptions {
  signal?: AbortSignal;
  timeout?: number;
}

type SelectFn = (title: string, options: string[], opts?: DialogOptions) => Promise<string | undefined>;
type ConfirmFn = (title: string, message: string, opts?: DialogOptions) => Promise<boolean>;
type InputFn = (title: string, placeholder?: string, opts?: DialogOptions) => Promise<string | undefined>;
type EditorFn = (title: string, prefill?: string) => Promise<string | undefined>;

/** The slice of pi's ExtensionUIContext this bridge wraps. */
export interface DialogUi {
  select: SelectFn;
  confirm: ConfirmFn;
  input: InputFn;
  editor: EditorFn;
}

export interface DialogBridge {
  /** Wrap the dialog methods of `ui` (idempotent per object). */
  install(ui: unknown): void;
  /** Resolve a pending dialog. Returns false if `msg.id` is not ours. */
  respond(msg: ExtensionUiResponseWire): boolean;
  /** Requests still awaiting an answer, for `session_sync` to replay. */
  pendingRequests(): ServerMessage[];
  /** Restore wrapped methods and drop pending state (best-effort). */
  dispose(): void;
}

interface Pending {
  request: ExtensionUiRequestWire;
  answer: (msg: ExtensionUiResponseWire) => void;
}

const WRAPPED = Symbol.for("remote-pi.dialog-bridge.wrapped");

function isDialogUi(ui: unknown): ui is DialogUi {
  if (!ui || typeof ui !== "object") return false;
  const u = ui as Record<string, unknown>;
  return ["select", "confirm", "input", "editor"].every(
    (k) => typeof u[k] === "function",
  );
}

/** Abort `child` when `parent` aborts; returns a detach function. */
function linkSignal(parent: AbortSignal | undefined, child: AbortController): () => void {
  if (!parent) return () => {};
  if (parent.aborted) {
    child.abort();
    return () => {};
  }
  const onAbort = () => child.abort();
  parent.addEventListener("abort", onAbort, { once: true });
  return () => parent.removeEventListener("abort", onAbort);
}

function responseValue(msg: ExtensionUiResponseWire): string | undefined {
  if ("cancelled" in msg && msg.cancelled) return undefined;
  return "value" in msg ? String(msg.value) : undefined;
}

function responseConfirmed(msg: ExtensionUiResponseWire): boolean {
  if ("cancelled" in msg && msg.cancelled) return false;
  return "confirmed" in msg ? msg.confirmed === true : false;
}

export function createDialogBridge(
  broadcast: (msg: ServerMessage) => void,
): DialogBridge {
  const pending = new Map<string, Pending>();
  const restores: Array<() => void> = [];

  /**
   * Run `original` and the app in parallel; first answer wins. `original`
   * receives a signal the bridge aborts when the app answers first.
   */
  function race<T>(
    request: ExtensionUiRequestWire,
    callerSignal: AbortSignal | undefined,
    original: (signal: AbortSignal) => Promise<T>,
    fromResponse: (msg: ExtensionUiResponseWire) => T,
  ): Promise<T> {
    const local = new AbortController();
    const detach = linkSignal(callerSignal, local);
    let settled = false;

    return new Promise<T>((resolve, reject) => {
      const finish = (fromApp: boolean): boolean => {
        if (settled) return false;
        settled = true;
        pending.delete(request.id);
        detach();
        if (!fromApp) {
          broadcast({
            type: "extension_ui_request",
            id: request.id,
            method: "notify",
            message: "Dialog resolved.",
          });
        }
        return true;
      };

      pending.set(request.id, {
        request,
        answer: (msg) => {
          if (!finish(true)) return;
          local.abort();
          resolve(fromResponse(msg));
        },
      });
      broadcast(request);

      original(local.signal).then(
        (value) => {
          if (finish(false)) resolve(value);
        },
        (err: unknown) => {
          if (finish(false)) reject(err);
        },
      );
    });
  }

  function install(ui: unknown): void {
    if (!isDialogUi(ui)) return;
    const target = ui as DialogUi & { [WRAPPED]?: true };
    if (target[WRAPPED]) return;

    const orig: DialogUi = {
      select: target.select,
      confirm: target.confirm,
      input: target.input,
      editor: target.editor,
    };

    target.select = (title, options, opts) =>
      race(
        { type: "extension_ui_request", id: randomUUID(), method: "select", title, options },
        opts?.signal,
        (signal) => orig.select(title, options, { ...opts, signal }),
        responseValue,
      );
    target.confirm = (title, message, opts) =>
      race(
        { type: "extension_ui_request", id: randomUUID(), method: "confirm", title, message },
        opts?.signal,
        (signal) => orig.confirm(title, message, { ...opts, signal }),
        responseConfirmed,
      );
    target.input = (title, placeholder, opts) =>
      race(
        {
          type: "extension_ui_request",
          id: randomUUID(),
          method: "input",
          title,
          ...(placeholder !== undefined ? { placeholder } : {}),
        },
        opts?.signal,
        (signal) => orig.input(title, placeholder, { ...opts, signal }),
        responseValue,
      );
    // editor() takes no options, so an app answer cannot dismiss the desk
    // editor; the first answer still wins and the other is ignored.
    target.editor = (title, prefill) =>
      race(
        {
          type: "extension_ui_request",
          id: randomUUID(),
          method: "editor",
          title,
          ...(prefill !== undefined ? { prefill } : {}),
        },
        undefined,
        () => orig.editor(title, prefill),
        responseValue,
      );

    target[WRAPPED] = true;
    restores.push(() => {
      Object.assign(target, orig);
      delete target[WRAPPED];
    });
  }

  function respond(msg: ExtensionUiResponseWire): boolean {
    const entry = pending.get(msg.id);
    if (!entry) return false;
    entry.answer(msg);
    return true;
  }

  function pendingRequests(): ServerMessage[] {
    return [...pending.values()].map((p) => p.request);
  }

  function dispose(): void {
    for (const restore of restores.splice(0)) restore();
    pending.clear();
  }

  return { install, respond, pendingRequests, dispose };
}
