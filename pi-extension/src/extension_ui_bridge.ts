// Plan/57 — Bridge interactive clarification flows to the paired app over the
// extension_ui_request/response contract.
//
// Two producers are supported:
//
//   @eko24ive/pi-ask events — Pi's ask_user extension emits a same-process
//     event contract that this bridge forwards to the app.
//   OMP's built-in ask tool — OMP exposes its rich askDialog through the
//     ExtensionContext UI object. When present, this bridge wraps that method
//     and races the desktop dialog against the paired app.
//
// Both flows use the same wire envelope. The app already renders the envelope
// as a native multi-question/multi-select surface; only the producer differs.

import { randomUUID } from "node:crypto";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type {
  AskAnswerWire,
  AskEnrichmentWire,
  AskOptionWire,
  AskQuestionWire,
  AskQuestionWireType,
  AskResponseEnrichmentWire,
  ExtensionUiResponseWire,
  ServerMessage,
} from "./protocol/types.js";

const PI_ASK_STARTED = "@eko24ive/pi-ask:started";
const PI_ASK_COMPLETED = "@eko24ive/pi-ask:completed";
const PI_ASK_SUBMIT = "@eko24ive/pi-ask:submit";
const PI_ASK_SUBMIT_RESULT = "@eko24ive/pi-ask:submit-result";
const OMP_ASK_FLOW_PREFIX = "omp:ask:";

/** Drop an unanswered flow after ten minutes. */
const FLOW_TTL_MS = 10 * 60 * 1000;

/** Minimal view of `pi.events` this bridge needs. */
type EventBus = ExtensionAPI["events"];

/** Structural copy of OMP's rich ask UI types.
 *
 * Remote Pi is compiled against Pi's public extension types, while OMP loads
 * legacy Pi extensions through its compatibility layer. Keeping these types
 * structural avoids a hard dependency on OMP.
 */
export interface OmpAskDialogOption {
  label: string;
  description?: string;
  preview?: string;
}

export interface OmpAskDialogQuestion {
  id: string;
  question: string;
  header?: string;
  options: OmpAskDialogOption[];
  multi?: boolean;
  recommended?: number;
}

export interface OmpAskDialogResultItem {
  id: string;
  question: string;
  options: string[];
  multi: boolean;
  selectedOptions: string[];
  customInput?: string;
  note?: string;
  timedOut?: boolean;
}

export type OmpAskDialogResult =
  | { kind: "submit"; results: OmpAskDialogResultItem[] }
  | { kind: "chat" };

interface OmpDialogOptions {
  signal?: AbortSignal;
  timeout?: number;
  onTimeout?: () => void;
  [key: string]: unknown;
}

type OmpAskDialog = (
  questions: OmpAskDialogQuestion[],
  options?: OmpDialogOptions,
) => Promise<OmpAskDialogResult | undefined>;

type RemoteOmpResult =
  | { kind: "answer"; value: OmpAskDialogResult | undefined }
  | { kind: "unavailable" };

interface OmpDialogWinner {
  source: "local" | "remote";
  value: OmpAskDialogResult | undefined;
}
interface ActiveOmpFlow {
  flowId: string;
  title: string | null;
  questions: AskQuestionWire[];
  resolve: (result: RemoteOmpResult) => void;
}

/** One pi-ask flow we've surfaced to the app and are awaiting an answer for. */
interface ActiveFlow {
  flowId: string;
  toolCallId: string | null;
  source: string;
  title: string | null;
  questions: AskQuestionWire[];
}

export interface ExtensionUiBridgeOptions {
  /** Return true when at least one paired app can receive a prompt. */
  hasActivePeer?: () => boolean;
}

export interface ExtensionUiBridge {
  /** Route an inbound extension_ui_response from a peer. */
  respond(msg: ExtensionUiResponseWire): void;
  /** Wrap OMP's optional rich askDialog UI method when the host provides it. */
  attachOmpAskDialog(ui: unknown): void;
  /**
   * Requests for flows still awaiting an answer, for session_sync to replay.
   *
   * The started broadcast fires exactly once. A peer that connects after a
   * flow opened never saw it, so replay the interactive frame after history.
   */
  pendingRequests(): ServerMessage[];
  /** Drop all subscriptions, wrappers, timers, and pending state. */
  dispose(): void;
}

/**
 * Wire Pi ask_user events and OMP's built-in ask dialog to the relay's
 * extension_ui_request/response frames. Returns null only when the SDK exposes
 * no usable events bus.
 */
export function createExtensionUiBridge(
  pi: ExtensionAPI,
  broadcast: (msg: ServerMessage) => void,
  options: ExtensionUiBridgeOptions = {},
): ExtensionUiBridge | null {

  const eventsRaw = (pi as { events?: EventBus }).events;
  if (
    !eventsRaw ||
    typeof eventsRaw.on !== "function" ||
    typeof eventsRaw.emit !== "function"
  ) {
    return null;
  }
  // Assign to a freshly-typed const so the narrowed (non-undefined) type is
  // preserved inside nested closures below (TS re-widens the raw capture).
  const events: EventBus = eventsRaw;

  // flowId → flow. Kept so a label-only (degraded) response can map back to the
  // option value, and so completed/submit-result can be tolerated if they arrive
  // after the app already answered.
  const activeFlows = new Map<string, ActiveFlow>();
  const activeOmpFlows = new Map<string, ActiveOmpFlow>();
  const ompFlowTimers = new Map<string, NodeJS.Timeout>();
  let restoreOmpAskDialog: (() => void) | null = null;
  const hasActivePeer = options.hasActivePeer ?? (() => true);
  // Per-flow TTL timers (FLOW_TTL_MS). pi-ask disposes flows on session_shutdown
  // WITHOUT emitting `completed`, so without this the `activeFlows` map would
  // leak one entry per abandoned flow. Bounded, defensive.
  const flowTimers = new Map<string, NodeJS.Timeout>();

  function clearFlowTtl(flowId: string): void {
    const t = flowTimers.get(flowId);
    if (t !== undefined) {
      clearTimeout(t);
      flowTimers.delete(flowId);
    }
  }
  function armFlowTtl(flowId: string): void {
    clearFlowTtl(flowId);
    flowTimers.set(
      flowId,
      setTimeout(() => {
        if (!activeFlows.delete(flowId)) return; // already resolved
        flowTimers.delete(flowId);
        // Tell the app the bridge forgot this flow instead of stranding its
        // modal silently: a matching WARNING notify keeps the modal open with
        // a retry hint. Rich clients can still retry (the response carries
        // flow_id and pi-ask's flow may still be pending on the desktop);
        // degraded clients at least get closure.
        broadcast({
          type: "extension_ui_request",
          id: flowId,
          method: "notify",
          message:
            "Clarification expired on the bridge — retry or answer on desktop.",
          notify_type: "warning",
        });
      }, FLOW_TTL_MS),
    );
  }
  function clearOmpFlowTtl(flowId: string): void {
    const timer = ompFlowTimers.get(flowId);
    if (timer !== undefined) {
      clearTimeout(timer);
      ompFlowTimers.delete(flowId);
    }
  }

  function settleOmpFlow(
    flowId: string,
    result: RemoteOmpResult,
    notify = true,
  ): void {
    const flow = activeOmpFlows.get(flowId);
    if (!flow) return;
    activeOmpFlows.delete(flowId);
    clearOmpFlowTtl(flowId);
    flow.resolve(result);
    if (notify) {
      broadcast({
        type: "extension_ui_request",
        id: flowId,
        method: "notify",
        message: "Clarification resolved.",
      });
    }
  }

  function armOmpFlowTtl(flowId: string): void {
    clearOmpFlowTtl(flowId);
    ompFlowTimers.set(
      flowId,
      setTimeout(() => {
        settleOmpFlow(flowId, { kind: "unavailable" });
      }, FLOW_TTL_MS),
    );
  }

  function requestOmpAskDialog(
    questions: OmpAskDialogQuestion[],
    dialogOptions?: OmpDialogOptions,
  ): Promise<RemoteOmpResult> {
    if (dialogOptions?.signal?.aborted) {
      return Promise.resolve({ kind: "unavailable" });
    }

    const flowId = `${OMP_ASK_FLOW_PREFIX}${randomUUID()}`;
    const flow: ActiveOmpFlow = {
      flowId,
      title: null,
      questions: toOmpWireQuestions(questions),
      resolve: () => {},
    };
    let resolveResult: (result: RemoteOmpResult) => void = () => {};
    const result = new Promise<RemoteOmpResult>((resolve) => {
      resolveResult = resolve;
    });
    flow.resolve = resolveResult;
    activeOmpFlows.set(flowId, flow);
    armOmpFlowTtl(flowId);

    const onAbort = (): void => {
      settleOmpFlow(flowId, { kind: "unavailable" });
    };
    dialogOptions?.signal?.addEventListener("abort", onAbort, { once: true });

    try {
      broadcast(requestForOmpFlow(flow));
    } catch {
      onAbort();
    }

    return result.finally(() => {
      dialogOptions?.signal?.removeEventListener("abort", onAbort);
    });
  }

  function attachOmpAskDialog(ui: unknown): void {
    restoreOmpAskDialog?.();
    restoreOmpAskDialog = null;
    if (!ui || typeof ui !== "object") return;

    const candidate = ui as { askDialog?: OmpAskDialog };
    const original = candidate.askDialog;
    if (typeof original !== "function") return;

    const wrapped: OmpAskDialog = async (questions, dialogOptions) => {
      let remoteAvailable = false;
      try {
        remoteAvailable = hasActivePeer();
      } catch {
        remoteAvailable = false;
      }
      if (!remoteAvailable) return original(questions, dialogOptions);

      const localAbort = new AbortController();
      const remoteAbort = new AbortController();
      const parentSignal = dialogOptions?.signal;
      const localSignal = parentSignal
        ? AbortSignal.any([parentSignal, localAbort.signal])
        : localAbort.signal;
      const remoteSignal = parentSignal
        ? AbortSignal.any([parentSignal, remoteAbort.signal])
        : remoteAbort.signal;

      const localPromise = Promise.resolve().then(() =>
        original(questions, { ...dialogOptions, signal: localSignal }),
      );
      const localWinner: Promise<OmpDialogWinner> = localPromise.then(
        (value): OmpDialogWinner => ({
          source: "local",
          value,
        }),
      );
      const remoteWinner: Promise<OmpDialogWinner> = requestOmpAskDialog(
        questions,
        {
          ...dialogOptions,
          signal: remoteSignal,
        },
      ).then((outcome): OmpDialogWinner | PromiseLike<OmpDialogWinner> =>
        outcome.kind === "unavailable"
          ? localWinner
          : { source: "remote", value: outcome.value },
      );

      try {
        const winner = await Promise.race([localWinner, remoteWinner]);
        return winner.value;
      } finally {
        localAbort.abort();
        remoteAbort.abort();
      }
    };

    try {
      candidate.askDialog = wrapped;
    } catch {
      return;
    }
    restoreOmpAskDialog = () => {
      if (candidate.askDialog === wrapped) candidate.askDialog = original;
    };
  }

  const unsubStarted = events.on(PI_ASK_STARTED, (raw: unknown) => {
    const event = parseStartedEvent(raw);
    if (!event) return;
    const flow: ActiveFlow = {
      flowId: event.flowId,
      toolCallId: event.toolCallId ?? null,
      source: event.source ?? "tool",
      title: event.title ?? null,
      questions: event.questions,
    };
    activeFlows.set(flow.flowId, flow);
    armFlowTtl(flow.flowId);
    broadcast(requestForFlow(flow));
  });

  const unsubCompleted = events.on(PI_ASK_COMPLETED, (raw: unknown) => {
    const e = raw as { version?: number; flowId?: unknown } | null;
    if (!e || e.version !== 1 || typeof e.flowId !== "string") return;
    const flowId = e.flowId;
    clearFlowTtl(flowId);
    activeFlows.delete(flowId);
    // Same id as the originating request (the flowId). The app treats a `notify`
    // whose id matches an open interactive request as "that flow resolved —
    // dismiss it". Covers the non-submitting owner in a multi-owner setup.
    broadcast({
      type: "extension_ui_request",
      id: flowId,
      method: "notify",
      message: "Clarification resolved.",
    });
  });

  // submit-result is per-request feedback. On error (invalid answer / flow
  // gone) surface a warning so the submitting owner can retry. The notify reuses
  // the flowId as its id (same as the originating request) so the app correlates
  // it to its open modal; notify_type "warning" distinguishes it from the
  // `completed` dismiss (same id, absent/other notify_type). Success is covered
  // by `completed`, so ok is a no-op here.
  const unsubResult = events.on(PI_ASK_SUBMIT_RESULT, (raw: unknown) => {
    const e = raw as {
      version?: number;
      requestId?: unknown;
      flowId?: unknown;
      ok?: unknown;
      error?: unknown;
      message?: unknown;
    } | null;
    if (!e || e.version !== 1 || e.ok === true) return;
    const message =
      typeof e.message === "string"
        ? e.message
        : typeof e.error === "string"
          ? e.error
          : "Clarification answer was not accepted.";
    const flowId =
      typeof e.flowId === "string"
        ? e.flowId
        : activeFlows.size === 1
          // Defensive: pi-ask always carries flowId. If it's ever absent, an
          // unambiguous single active flow is a safe attribution; with zero or
          // several, the warning is uncorrelatable and the app ignores
          // unmatched notifies — drop it instead of broadcasting a random id
          // no client can act on.
          ? activeFlows.keys().next().value
          : undefined;
    if (!flowId) return;
    broadcast({
      type: "extension_ui_request",
      id: flowId,
      method: "notify",
      message,
      notify_type: "warning",
    });
  });

  function respondToOmpFlow(msg: ExtensionUiResponseWire): boolean {
    const ask = msg.ask;
    const flowId =
      ask?.flow_id ?? (activeOmpFlows.has(msg.id) ? msg.id : undefined);
    if (!flowId) return false;
    const flow = activeOmpFlows.get(flowId);
    if (!flow) return false;

    if (
      ("cancelled" in msg && msg.cancelled === true) ||
      (ask !== undefined && ask.kind === "cancel")
    ) {
      settleOmpFlow(flowId, { kind: "answer", value: undefined });
      return true;
    }

    if (ask !== undefined && ask.kind === "answer") {
      settleOmpFlow(flowId, {
        kind: "answer",
        value: ompResultFromAnswer(flow, ask),
      });
      return true;
    }

    if ("value" in msg) {
      settleOmpFlow(flowId, {
        kind: "answer",
        value: ompResultFromLabel(flow, String(msg.value)),
      });
      return true;
    }

    return true;
  }

  function respond(msg: ExtensionUiResponseWire): void {
    if (respondToOmpFlow(msg)) return;
    const ask = msg.ask;

    // Explicit cancel — with or without the ask envelope. A strict client
    // (no envelope) only carries the request id, which IS the flowId by this
    // bridge's contract; confirm via activeFlows before trusting it.
    if (
      ("cancelled" in msg && msg.cancelled === true) ||
      (ask !== undefined && ask.kind === "cancel")
    ) {
      const flowId =
        ask?.flow_id ?? (activeFlows.has(msg.id) ? msg.id : null);
      if (!flowId) return;
      emitSubmit(msg.id, flowId, { kind: "cancel" });
      return;
    }

    // Rich path: the ask envelope carries the structured answer (option values).
    if (ask !== undefined && ask.kind === "answer") {
      emitSubmit(msg.id, ask.flow_id, {
        kind: "answer",
        mode: ask.mode,
        answers: ask.answers,
      });
      return;
    }

    // Degraded path: a response without the ask envelope (e.g. a generic client
    // that rendered only the SDK `select`). Map the chosen label back to the
    // option value for the flow's first question.
    const flow = activeFlows.get(msg.id);
    if (!flow || flow.questions.length === 0) return;
    const question = flow.questions[0];
    if (!question) return;
    const label = "value" in msg ? String(msg.value) : "";
    // NB: pi-ask's schema doesn't forbid duplicate labels — on a collision the
    // first match wins. Inherent ambiguity of a label-only (degraded) client.
    const match = question.options.find((o) => o.label === label);
    const answers: Record<string, AskAnswerWire> = {
      [question.id]: match
        ? { values: [match.value] }
        : label
          ? { customText: label }
          : {},
    };
    emitSubmit(msg.id, flow.flowId, {
      kind: "answer",
      mode: "submit",
      answers,
    });
  }

  function emitSubmit(
    requestId: string,
    flowId: string,
    response:
      | {
          kind: "answer";
          mode?: "submit" | "elaborate";
          answers: Record<string, AskAnswerWire>;
        }
      | { kind: "cancel" },
  ): void {
    try {
      events.emit(PI_ASK_SUBMIT, {
        version: 1,
        requestId,
        flowId,
        response,
      });
    } catch {
      // pi-ask not installed or bus gone — nothing useful to do; the flow will
      // either resolve locally (desktop TUI) or time out on its own.
    }
  }

  return {
    respond,
    attachOmpAskDialog,
    pendingRequests: () => [
      ...[...activeFlows.values()].map(requestForFlow),
      ...[...activeOmpFlows.values()].map(requestForOmpFlow),
    ],
    dispose() {
      restoreOmpAskDialog?.();
      restoreOmpAskDialog = null;
      unsubStarted();
      unsubCompleted();
      unsubResult();
      for (const t of flowTimers.values()) clearTimeout(t);
      flowTimers.clear();
      for (const flowId of [...activeOmpFlows.keys()]) {
        settleOmpFlow(flowId, { kind: "unavailable" }, false);
      }
      for (const t of ompFlowTimers.values()) clearTimeout(t);
      ompFlowTimers.clear();
      activeFlows.clear();
      activeOmpFlows.clear();
    },
  };
}

/** Build the single extension_ui_request that represents a whole ask flow. */
function requestForFlow(flow: ActiveFlow): ServerMessage {
  const first = flow.questions[0];
  const title = flow.title ?? first?.prompt ?? "Clarification";
  const options = first ? first.options.map((o) => o.label) : [];
  const ask: AskEnrichmentWire = {
    flow_id: flow.flowId,
    tool_call_id: flow.toolCallId,
    source: flow.source,
    title: flow.title,
    questions: flow.questions,
  };
  // A pure-text question (pi-ask allows an empty options array) degrades to
  // `input` — a strict client renders a text field instead of an empty select.
  if (options.length === 0) {
    return {
      type: "extension_ui_request",
      // One request per flow → reuse the flowId as the correlation id. The
      // app's response carries the same id (and ask.flow_id) for routing.
      id: flow.flowId,
      method: "input",
      title,
      placeholder: first?.prompt,
      ask,
    };
  }
  return {
    type: "extension_ui_request",
    // One request per flow → reuse the flowId as the correlation id. The app's
    // response carries the same id (and ask.flow_id) so the bridge can route.
    id: flow.flowId,
    method: "select",
    title,
    options,
    ask,
  };
}
/** Build the same envelope for an OMP `ask` flow. */
function requestForOmpFlow(flow: ActiveOmpFlow): ServerMessage {
  const first = flow.questions[0];
  const title = flow.title ?? first?.prompt ?? "Clarification";
  const options = first ? first.options.map((o) => o.label) : [];
  const ask: AskEnrichmentWire = {
    flow_id: flow.flowId,
    tool_call_id: null,
    source: "omp-ask",
    title: flow.title,
    questions: flow.questions,
  };
  if (options.length === 0) {
    return {
      type: "extension_ui_request",
      id: flow.flowId,
      method: "input",
      title,
      placeholder: first?.prompt,
      ask,
    };
  }
  return {
    type: "extension_ui_request",
    id: flow.flowId,
    method: "select",
    title,
    options,
    ask,
  };
}

function toOmpWireQuestions(
  questions: OmpAskDialogQuestion[],
): AskQuestionWire[] {
  return questions.map((question) => {
    const hasPreview = question.options.some(
      (option) => typeof option.preview === "string" && option.preview.length > 0,
    );
    const isMulti = question.multi === true;
    const type: AskQuestionWireType = hasPreview
      ? "preview"
      : isMulti
        ? "multi"
        : "single";
    return {
      id: question.id,
      label: question.header ?? question.question,
      prompt: question.question,
      type,
      required: false,
      ...(isMulti && hasPreview ? { presentedType: "multi" as const } : {}),
      requestedType: isMulti ? "multi" : type,
      options: question.options.map((option, index) => ({
        value: `${question.id}:${index}`,
        label: option.label,
        description: option.description,
        preview: option.preview,
      })),
    };
  });
}
function ompResultFromAnswer(
  flow: ActiveOmpFlow,
  answer: AskResponseEnrichmentWire & { kind: "answer" },
): OmpAskDialogResult {
  return {
    kind: "submit",
    results: flow.questions.map((question) => {
      const response = answer.answers[question.id] ?? {};
      const values = new Set(response.values ?? []);
      const selectedOptions = question.options
        .map((option, index) => ({
          label: option.label,
          value: `${question.id}:${index}`,
        }))
        .filter((option) => values.has(option.value) || values.has(option.label))
        .map((option) => option.label);
      return {
        id: question.id,
        question: question.prompt,
        options: question.options.map((option) => option.label),
        multi: question.type === "multi" || question.presentedType === "multi",
        selectedOptions,
        customInput: response.customText,
        note: response.note,
      };
    }),
  };
}

function ompResultFromLabel(
  flow: ActiveOmpFlow,
  label: string,
): OmpAskDialogResult {
  return {
    kind: "submit",
    results: flow.questions.map((question, index) => {
      const selected =
        index === 0
          ? question.options.find((option) => option.label === label)?.label
          : undefined;
      return {
        id: question.id,
        question: question.prompt,
        options: question.options.map((option) => option.label),
        multi: question.type === "multi" || question.presentedType === "multi",
        selectedOptions: selected ? [selected] : [],
        customInput: index === 0 && !selected && label ? label : undefined,
      };
    }),
  };
}


// ── pi-ask event parsing (defensive — shapes come from a third-party package) ──

interface StartedEvent {
  flowId: string;
  toolCallId?: string;
  source?: string;
  title?: string;
  questions: AskQuestionWire[];
}

function parseStartedEvent(raw: unknown): StartedEvent | null {
  if (!isRecord(raw)) return null;
  if (raw.version !== 1) return null;
  if (typeof raw.flowId !== "string") return null;
  if (!Array.isArray(raw.questions)) return null;
  const questions: AskQuestionWire[] = [];
  for (const q of raw.questions) {
    const parsed = parseQuestion(q);
    if (!parsed) return null;
    questions.push(parsed);
  }
  if (questions.length === 0) return null;
  return {
    flowId: raw.flowId,
    toolCallId: asString(raw.toolCallId),
    source: asString(raw.source),
    title: asString(raw.title),
    questions,
  };
}

function parseQuestion(value: unknown): AskQuestionWire | null {
  if (!isRecord(value)) return null;
  if (typeof value.id !== "string" || typeof value.prompt !== "string") return null;
  if (!Array.isArray(value.options)) return null;
  const options: AskOptionWire[] = [];
  for (const o of value.options) {
    const opt = parseOption(o);
    if (!opt) return null;
    options.push(opt);
  }
  // Empty options is valid: pi-ask's schema has no minItems — a question can be
  // pure text (custom answer only). The request degrades to `input` upstream.
  return {
    id: value.id,
    label: typeof value.label === "string" ? value.label : value.prompt,
    prompt: value.prompt,
    type: asQuestionType(value.type) ?? "single",
    required: value.required === true,
    presentedType: asQuestionType(value.presentedType),
    requestedType: asQuestionType(value.requestedType),
    options,
  };
}

function parseOption(value: unknown): AskOptionWire | null {
  if (!isRecord(value)) return null;
  // pi-ask's schema marks value/label Optional on input, but a started event
  // always carries resolved values. Be lenient: fall back label→value.
  const val = typeof value.value === "string" ? value.value : asString(value.label);
  const label = typeof value.label === "string" ? value.label : val;
  if (!val || !label) return null;
  return {
    value: val,
    label,
    description: asString(value.description),
    preview: asString(value.preview),
    freeform: value.freeform === true ? true : undefined,
  };
}

function asQuestionType(value: unknown): AskQuestionWireType | undefined {
  return value === "single" || value === "multi" || value === "preview"
    ? value
    : undefined;
}

function asString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

// Re-exported so callers (and tests) can build responses without re-deriving the
// pi-ask response shape.
export type { AskResponseEnrichmentWire, ExtensionUiResponseWire };
