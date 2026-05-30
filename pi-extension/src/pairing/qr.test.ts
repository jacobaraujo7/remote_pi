import { describe, expect, test, vi } from "vitest";
import { buildQRUri, QRSession } from "./qr.js";

describe("QRSession", () => {
  test("issueToken records pair nonce and expiry for signed pairing", () => {
    vi.useFakeTimers();
    vi.setSystemTime(1_700_000_000_000);
    try {
      const session = new QRSession();
      const issued = session.issueToken();
      expect(Buffer.from(issued.token, "base64url")).toHaveLength(16);
      expect(Buffer.from(issued.pairNonce, "base64url")).toHaveLength(16);
      expect(issued.expiresAt).toBe(1_700_000_060_000);
      expect(session.checkToken(issued.token)).toEqual({
        status: "ok",
        pairNonce: issued.pairNonce,
        expiresAt: issued.expiresAt,
      });
      expect(session.consumeToken(issued.token)).toBe("ok");
      expect(session.checkToken(issued.token)).toEqual({ status: "consumed" });
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("buildQRUri", () => {
  test("includes signed-pairing nonce and expiry when provided", () => {
    const uri = buildQRUri(
      "AAAAAAAAAAAAAAAAAAAAAA",
      new Uint8Array(32),
      "Pi",
      "room-1",
      "AQEBAQEBAQEBAQEBAQEBAQ",
      1_700_000_000_000,
    );
    const parsed = new URL(uri);
    expect(parsed.searchParams.get("pn")).toBe("AQEBAQEBAQEBAQEBAQEBAQ");
    expect(parsed.searchParams.get("exp")).toBe("1700000000000");
  });
});
