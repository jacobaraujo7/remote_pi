const SENSITIVE_KEYS = new Set([
  "ct",
  "token",
  "t",
  "sig",
  "signature",
  "auth",
  "secret",
  "sk",
  "privateKey",
  "private_key",
  "prompt",
  "reply",
  "response",
  "text",
  "message",
  "body",
  "payload",
  "qr",
  "uri",
]);

const REDACTED = "[redacted]";
const REDACTED_URI = "[redacted-uri]";

export function shortId(value: string, visible = 8): string {
  if (value.length <= visible) return value;
  return `${value.slice(0, visible)}…`;
}

export function safeLogString(value: string): string {
  if (value.startsWith("remotepi://")) return REDACTED_URI;
  if (value.length > 48 && /^[A-Za-z0-9+/=_-]+$/.test(value)) {
    return `${value.slice(0, 8)}…(${value.length} chars)`;
  }
  return value;
}

export function redactForLog(value: unknown): unknown {
  return redactValue(value, undefined);
}

function redactValue(value: unknown, key: string | undefined): unknown {
  if (key && SENSITIVE_KEYS.has(key)) return REDACTED;
  if (typeof value === "string") return safeLogString(value);
  if (Array.isArray(value)) return value.map((item) => redactValue(item, undefined));
  if (!value || typeof value !== "object") return value;

  const out: Record<string, unknown> = {};
  for (const [entryKey, entryValue] of Object.entries(value)) {
    out[entryKey] = redactValue(entryValue, entryKey);
  }
  return out;
}
