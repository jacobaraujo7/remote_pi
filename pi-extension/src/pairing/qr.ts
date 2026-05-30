import { randomBytes } from "node:crypto";
import qrTerminal from "qrcode-terminal";

const TOKEN_TTL_MS = 60_000;

interface ActiveToken {
  token: string;
  expiresAt: number;
  consumed: boolean;
}

/** Encapsulates the single active QR token. One instance per Pi process. */
export class QRSession {
  private active: ActiveToken | null = null;

  /** Generates a fresh 16-byte random token encoded as base64url. */
  generateToken(): string {
    return randomBytes(16).toString("base64url");
  }

  /**
   * Issues a new active token, invalidating any previous one.
   * Returns the token and its expiry timestamp.
   */
  issueToken(): { token: string; expiresAt: number } {
    const token = this.generateToken();
    const expiresAt = Date.now() + TOKEN_TTL_MS;
    this.active = { token, expiresAt, consumed: false };
    return { token, expiresAt };
  }

  /** Validates and atomically consumes a token. */
  consumeToken(
    token: string,
  ): "ok" | "expired" | "consumed" | "unknown" {
    if (!this.active || this.active.token !== token) return "unknown";
    if (this.active.consumed) return "consumed";
    if (Date.now() > this.active.expiresAt) return "expired";
    this.active.consumed = true;
    return "ok";
  }

  clear(): void {
    this.active = null;
  }
}

export const qrSession = new QRSession();

// ── URI + display ─────────────────────────────────────────────────────────────

export function buildQRUri(
  token: string,
  longtermEdPk: Uint8Array, // Ed25519 — only peer ID after E2E rollback
  sessionName: string,
  /**
   * Pi room id (12 chars, base64url) derived from cwd. App routes pair_request
   * to this room so the relay delivers it to the right Pi instance among N
   * paralelos com mesmo epk. Adicionado no fix do plano 17 (sem `rm` o app
   * cai em room=main e o relay drops com "dest not found").
   */
  roomId?: string,
): string {
  // `r` (relay URL) removed in plano 14 — relay now comes from app config /
  // pi-ext env|config|default chain. Keeps QR ~30-50 chars shorter.
  // `n` (session name) is kept: the app uses it for the pre-pair_ok preview
  // screen (showing the agent name immediately after scan, before the
  // handshake completes). Dropping it briefly shrank the QR but the QR
  // size no longer matters now that the copy-paste URI is rendered via
  // `pi.sendMessage` into the chat panel (not the QR overflow area).
  const epkB64 = Buffer.from(longtermEdPk).toString("base64url");
  const params = new URLSearchParams({
    t: token,
    epk: epkB64,
    n: sessionName.slice(0, 80),
  });
  if (roomId) params.set("rm", roomId);
  // Capability advertised in QR so a relay cannot silently strip the
  // pair_request capability and downgrade a new app/Pi pair to unsigned
  // inner traffic. Legacy QRs omit this and remain compatible.
  params.set("si", "1");
  return `remotepi://pair?${params.toString()}`;
}

/**
 * Returns the QR ASCII as a string (pure Unicode block characters —
 * `█ ▀ ▄` and space, NO ANSI escapes — qrcode-terminal v0.12 small mode
 * is escape-free, see lib/main.js:48-53).
 *
 * The caller can either write the string to stderr (legacy path, breaks
 * the Pi TUI layout) or inject it via `pi.sendMessage` (renders inside
 * the chat panel as proper content).
 */
export function renderQRAscii(uri: string): string {
  let out = "";
  qrTerminal.generate(uri, { small: true }, (qrcode) => { out = qrcode; });
  return out;
}

/**
 * Legacy stderr writer — kept for the standalone CLI mode
 * (`pi-extension/src/index.ts` bottom block, which runs outside a Pi TUI).
 * Inside the Pi TUI extension flow, use `renderQRAscii` + `pi.sendMessage`
 * instead — direct stderr writes from inside an extension break the TUI's
 * scrollable output widget (the QR overflows the panel and other writes
 * collide with the prompt area).
 */
export function displayQR(uri: string): void {
  const qrcode = renderQRAscii(uri);
  process.stderr.write(`\n📱 Scan to pair:\n\n${qrcode}\n`);
}

/**
 * Starts a rotating QR session: generates a new QR every 60s, printing it
 * to stdout. Returns a `stop()` function that cancels the rotation and clears
 * the active token.
 */
export function startQRRotation(
  longtermEdPk: Uint8Array,
  sessionName: string,
  roomId?: string,
): () => void {
  let timer: ReturnType<typeof setTimeout> | null = null;
  let stopped = false;

  const rotate = () => {
    if (stopped) return;
    const { token, expiresAt } = qrSession.issueToken();
    const uri = buildQRUri(token, longtermEdPk, sessionName, roomId);
    displayQR(uri);
    console.log(
      `⏱  Renews at ${new Date(expiresAt).toLocaleTimeString()} — waiting for scan…`,
    );
    timer = setTimeout(rotate, TOKEN_TTL_MS);
  };

  rotate();

  return () => {
    stopped = true;
    if (timer !== null) clearTimeout(timer);
    qrSession.clear();
  };
}
