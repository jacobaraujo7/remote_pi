/**
 * Plan/28 — ModelRegistry access for the action handlers.
 *
 * The host hands every extension a ready `ModelRegistry` on
 * `ExtensionContext.modelRegistry` — the same instance `AgentSession` uses
 * internally. That is the ONLY source we read.
 *
 * History (issue #112): this module used to build its own registry via
 * `ModelRegistry.create(AuthStorage.create())`. Both factories were removed
 * from `@earendil-works/pi-coding-agent` in pi 0.83, so the import crashed the
 * whole pi process on the first `model_set`/`list_models` from the app
 * (`undefined is not an object (evaluating 'AuthStorage.create')`, thrown from
 * the WebSocket line handler). Reading the registry off the live ctx drops the
 * dependency on that package's factory surface entirely, so a future breaking
 * change there cannot crash the extension the same way again.
 *
 * Two hazards this handles:
 *
 * 1. A ctx captured before a session replacement/reload is **stale**, and even
 *    *reading* `.modelRegistry` on it throws (`assertActive`). Every read is
 *    wrapped.
 * 2. There may be no live ctx at all (daemon boot, control channel). Rather
 *    than throw from a WS callback — an uncaught exception that exits pi — we
 *    fall back to the last registry that worked, then to a stub whose methods
 *    never throw and report an empty catalog.
 */

import type { ActionModelRegistry } from "./handlers.js";

/** Anything carrying the host registry — `ExtensionContext` and friends. */
interface RegistryBearingCtx {
  modelRegistry?: ActionModelRegistry;
}

let _lastGoodRegistry: ActionModelRegistry | null = null;

/**
 * Never-throwing empty catalog. Used only when no ctx has ever been seen —
 * callers get an empty model list instead of a crashed agent.
 */
const _stubRegistry: ActionModelRegistry = {
  refresh() {},
  getAvailable() { return []; },
  find() { return undefined; },
};

/**
 * Resolve the live host `ModelRegistry` from the most recent extension ctx.
 * Falls back to the last one that worked, then to an inert stub.
 */
export function ensureModelRegistry(ctx?: RegistryBearingCtx | null): ActionModelRegistry {
  try {
    const live = ctx?.modelRegistry;
    if (live) {
      _lastGoodRegistry = live;
      return live;
    }
  } catch {
    // stale ctx after session replacement — reading the property throws.
  }
  return _lastGoodRegistry ?? _stubRegistry;
}

/** Test seam — drop the cached registry so tests can rebuild with fakes. */
export function _resetModelRegistryForTests(): void {
  _lastGoodRegistry = null;
}
