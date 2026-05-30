import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { writePrivateFileAtomicSync } from "./secure_fs.js";

const CONFIG_DIR = path.join(os.homedir(), ".pi", "remote");
const CONFIG_FILE = path.join(CONFIG_DIR, "config.json");

/**
 * Default community relay. Stored in canonical http(s):// form — conversion
 * to ws(s):// happens at the transport layer (see `toWebSocketUrl`). The
 * community relay's reverse proxy maps `:443 → :3000` (the WS port), so the
 * URL has no explicit port and the WebSocket upgrade rides on the same TLS
 * connection as the HTTPS endpoints used by the mesh client.
 */
export const kDefaultRelayUrl = "https://relay-rp1.jacobmoura.work";

export type RemotePiConfig = { relay?: string };

export function loadConfig(): RemotePiConfig {
  try {
    const raw = fs.readFileSync(CONFIG_FILE, "utf8");
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object") return {};
    return parsed as RemotePiConfig;
  } catch {
    return {};
  }
}

export function saveConfig(patch: Partial<RemotePiConfig>): void {
  const current = loadConfig();
  const next = { ...current, ...patch };
  writePrivateFileAtomicSync(CONFIG_FILE, JSON.stringify(next, null, 2) + "\n");
}

export type RelayResolution = { url: string; source: "env" | "config" | "default" };

/**
 * Resolves the effective relay URL in **canonical http(s):// form**.
 *
 * Precedence:
 *   1. `REMOTE_PI_RELAY` env var (ops/CI escape hatch)
 *   2. `~/.pi/remote/config.json` `relay` field (set via /remote-pi set-relay)
 *   3. `kDefaultRelayUrl` (community default)
 *
 * Any ws(s):// values found (legacy configs or env overrides) are coerced
 * to http(s):// defensively — the canonical form across the codebase is
 * http(s)://, and the transport layer converts to ws(s):// at WS-open time.
 */
export function resolveRelayUrl(): RelayResolution {
  const env = process.env["REMOTE_PI_RELAY"];
  if (env && env.length > 0) return { url: toHttpUrl(env), source: "env" };
  const cfg = loadConfig();
  if (cfg.relay && cfg.relay.length > 0) return { url: toHttpUrl(cfg.relay), source: "config" };
  return { url: toHttpUrl(kDefaultRelayUrl), source: "default" };
}

/**
 * Strict validator for **user-provided** relay URLs (via `/remote-pi
 * set-relay` or `/remote-pi relay url`).
 *
 * Only accepts `http://` and `https://`. `ws://`/`wss://` are deliberately
 * **rejected** — the canonical form stored in config is http(s):// and the
 * extension converts to ws(s):// internally when opening the WebSocket.
 * Forcing a single scheme at the user boundary avoids two-form drift.
 */
export function isValidRelayUrl(url: string): boolean {
  if (!url) return false;
  const lower = url.toLowerCase();
  if (!lower.startsWith("http://") && !lower.startsWith("https://")) return false;
  try { new URL(url); return true; } catch { return false; }
}

/**
 * Returns true if the URL uses ws:// or wss:// scheme — for emitting a
 * targeted error message when the user pastes a WebSocket URL by mistake.
 */
export function isWebSocketScheme(url: string): boolean {
  const lower = url.toLowerCase();
  return lower.startsWith("ws://") || lower.startsWith("wss://");
}

/**
 * Converts an http(s):// URL to the corresponding ws(s):// form. Used by
 * the transport layer right before opening the WebSocket — config storage
 * and the mesh HTTP client both stay on http(s)://.
 *
 *   https://host  → wss://host
 *   http://host   → ws://host
 *   ws(s)://host  → pass-through (defensive — env overrides or legacy
 *                   configs may still carry ws(s)://)
 */
export function toWebSocketUrl(url: string): string {
  const lower = url.toLowerCase();
  if (lower.startsWith("https://")) return "wss://" + url.slice("https://".length);
  if (lower.startsWith("http://"))  return "ws://"  + url.slice("http://".length);
  return url;
}

/**
 * Inverse of `toWebSocketUrl`. Used by `resolveRelayUrl` to coerce any
 * ws(s):// values back to canonical http(s):// before returning them to
 * the rest of the codebase.
 */
export function toHttpUrl(url: string): string {
  const lower = url.toLowerCase();
  if (lower.startsWith("wss://")) return "https://" + url.slice("wss://".length);
  if (lower.startsWith("ws://"))  return "http://"  + url.slice("ws://".length);
  return url;
}
