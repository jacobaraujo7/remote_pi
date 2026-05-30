import { describe, expect, test } from "vitest";
import { redactForLog, safeLogString, shortId } from "./log_safety.js";

describe("log safety helpers", () => {
  test("redacts protocol payloads, tokens, signatures, and message bodies", () => {
    const redacted = redactForLog({
      type: "pair_request",
      id: "msg-1",
      ct: "base64-ciphertext",
      token: "pair-token-secret",
      sig: "auth-signature-secret",
      body: { type: "user_message", text: "please leak this prompt" },
      payload: { response: "assistant reply secret" },
    });

    const rendered = JSON.stringify(redacted);
    expect(rendered).toContain("pair_request");
    expect(rendered).toContain("msg-1");
    for (const secret of [
      "base64-ciphertext",
      "pair-token-secret",
      "auth-signature-secret",
      "please leak this prompt",
      "assistant reply secret",
    ]) {
      expect(rendered).not.toContain(secret);
    }
  });

  test("redacts QR URIs and abbreviates long peer keys", () => {
    expect(safeLogString("remotepi://pair?t=secret&epk=peer")).toBe("[redacted-uri]");
    expect(safeLogString("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=="))
      .toBe("ABCDEFGH…(66 chars)");
    expect(shortId("ABCDEFGHIJKLMNOPQRSTUVWXYZ", 10)).toBe("ABCDEFGHIJ…");
  });
});
