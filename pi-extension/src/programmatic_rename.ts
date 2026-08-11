import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** Event emitted by another Pi extension to request a live Remote Pi rename. */
export const REMOTE_PI_RENAME_REQUEST_EVENT = "remote-pi:rename-request";

export interface RemotePiRenameRequest {
  version: 1;
  name: string;
}

type RenameAgent = (name: string) => Promise<boolean>;
type EventBus = ExtensionAPI["events"];

function parseRenameRequest(raw: unknown): RemotePiRenameRequest | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;

  const request = raw as { version?: unknown; name?: unknown };
  if (request.version !== 1 || typeof request.name !== "string") return null;

  const name = request.name.trim();
  return name ? { version: 1, name } : null;
}

/**
 * Exposes live rename over Pi's shared extension event bus.
 *
 * Requests are serialized because a rename temporarily leaves the mesh and cycles
 * the relay room. Overlapping requests would race those shared lifecycle handles.
 */
export function createProgrammaticRenameApi(
  pi: ExtensionAPI,
  renameAgent: RenameAgent,
): (() => void) | null {
  const eventsRaw = (pi as { events?: EventBus }).events;
  if (!eventsRaw || typeof eventsRaw.on !== "function") return null;

  const events: EventBus = eventsRaw;
  let active = true;
  let queue = Promise.resolve();

  const unsubscribe = events.on(REMOTE_PI_RENAME_REQUEST_EVENT, (raw: unknown) => {
    const request = parseRenameRequest(raw);
    if (!request) return;

    queue = queue
      .then(async () => {
        if (!active) return;
        await renameAgent(request.name);
      })
      .catch((error: unknown) => {
        const message = error instanceof Error ? error.message : String(error);
        console.warn(`[remote-pi] programmatic rename failed: ${message}`);
      });
  });

  return () => {
    if (!active) return;
    active = false;
    unsubscribe();
  };
}
