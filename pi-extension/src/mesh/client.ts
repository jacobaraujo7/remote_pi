import type { MeshEnvelope } from "./types.js";

export class MeshFetchUnavailableError extends Error {
  override readonly name = "MeshFetchUnavailableError";
}

export class MeshFetchInvalidResponseError extends Error {
  override readonly name = "MeshFetchInvalidResponseError";
}

export interface MeshClientOptions {
  /** Finite deadline covering response headers and body parsing. */
  readonly requestTimeoutMs?: number;
}

const DEFAULT_REQUEST_TIMEOUT_MS = 5_000;
const ED25519_SIGNATURE_BYTES = 64;

function invalidResponse(): MeshFetchInvalidResponseError {
  return new MeshFetchInvalidResponseError("mesh response is invalid");
}

function unavailable(): MeshFetchUnavailableError {
  return new MeshFetchUnavailableError("mesh request is unavailable");
}

function decodeStrictBase64(raw: string): Uint8Array {
  if (raw.length === 0) throw invalidResponse();
  const hasStandardOnlyCharacters = /[+/]/.test(raw);
  const hasUrlSafeOnlyCharacters = /[-_]/.test(raw);
  if (hasStandardOnlyCharacters && hasUrlSafeOnlyCharacters) {
    throw invalidResponse();
  }

  const firstPaddingIndex = raw.indexOf("=");
  const body = firstPaddingIndex === -1 ? raw : raw.slice(0, firstPaddingIndex);
  const padding = firstPaddingIndex === -1 ? "" : raw.slice(firstPaddingIndex);
  const bodyPattern = hasUrlSafeOnlyCharacters
    ? /^[A-Za-z0-9_-]+$/
    : /^[A-Za-z0-9+/]+$/;
  if (
    !bodyPattern.test(body) ||
    (padding !== "" && !/^={1,2}$/.test(padding))
  ) {
    throw invalidResponse();
  }

  const requiredPaddingLength = (4 - (body.length % 4)) % 4;
  if (
    requiredPaddingLength === 3 ||
    (padding.length > 0 && padding.length !== requiredPaddingLength)
  ) {
    throw invalidResponse();
  }

  const normalizedBody = body.replaceAll("-", "+").replaceAll("_", "/");
  const bytes = new Uint8Array(
    Buffer.from(
      normalizedBody + "=".repeat(requiredPaddingLength),
      "base64",
    ),
  );
  const canonicalPadded = Buffer.from(bytes).toString("base64");
  const canonicalUnpadded = canonicalPadded.replace(/=+$/, "");
  const normalizedInput = normalizedBody + padding;
  if (
    normalizedInput !== canonicalPadded &&
    normalizedInput !== canonicalUnpadded
  ) {
    throw invalidResponse();
  }
  return bytes;
}

/** Finite-deadline HTTP client for Relay mesh membership envelopes. */
export class MeshClient {
  private readonly baseUrl: string;
  private readonly requestTimeoutMs: number;

  constructor(relayUrl: string, options: MeshClientOptions = {}) {
    const requestTimeoutMs =
      options.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;
    if (!Number.isFinite(requestTimeoutMs) || requestTimeoutMs <= 0) {
      throw new RangeError("requestTimeoutMs must be finite and positive");
    }
    this.baseUrl = relayUrl.replace(/\/+$/, "");
    this.requestTimeoutMs = requestTimeoutMs;
  }

  async get(hash: string, since?: number): Promise<MeshEnvelope | null> {
    const query =
      since !== undefined ? `?since=${encodeURIComponent(since)}` : "";
    const url = `${this.baseUrl}/mesh/${encodeURIComponent(hash)}${query}`;
    const controller = new AbortController();
    let rejectOnAbort: (() => void) | null = null;
    const aborted = new Promise<never>((_resolve, reject) => {
      rejectOnAbort = () => reject(unavailable());
      controller.signal.addEventListener("abort", rejectOnAbort, { once: true });
    });
    const timeout = setTimeout(
      () => controller.abort(),
      this.requestTimeoutMs,
    );

    try {
      let response: Response;
      try {
        response = await Promise.race([
          fetch(url, { method: "GET", signal: controller.signal }),
          aborted,
        ]);
      } catch (error) {
        if (error instanceof MeshFetchUnavailableError) throw error;
        throw unavailable();
      }

      if (response.status === 304 || response.status === 404) return null;
      if (
        response.status === 408 ||
        response.status === 425 ||
        response.status === 429 ||
        (response.status >= 500 && response.status <= 599)
      ) {
        throw unavailable();
      }
      if (response.status !== 200) throw invalidResponse();

      let payload: unknown;
      try {
        payload = await Promise.race([response.json(), aborted]);
      } catch (error) {
        if (error instanceof SyntaxError) throw invalidResponse();
        throw unavailable();
      }
      if (
        !payload ||
        typeof payload !== "object" ||
        typeof (payload as { blob?: unknown }).blob !== "string" ||
        typeof (payload as { sig?: unknown }).sig !== "string"
      ) {
        throw invalidResponse();
      }

      const body = payload as { blob: string; sig: string };
      const blob = decodeStrictBase64(body.blob);
      const sig = decodeStrictBase64(body.sig);
      if (blob.length === 0 || sig.length !== ED25519_SIGNATURE_BYTES) {
        throw invalidResponse();
      }
      return { blob, sig };
    } finally {
      clearTimeout(timeout);
      if (rejectOnAbort) {
        controller.signal.removeEventListener("abort", rejectOnAbort);
      }
    }
  }
}
