import { describe, expect, test } from "vitest";
import type { AckResult } from "../session/peer.js";
import { formatMeshAckResult } from "./mesh_result.js";

function resultText(result: ReturnType<typeof formatMeshAckResult>): string {
  return result.content.map((item) => item.text).join("\n");
}

describe("formatMeshAckResult", () => {
  test.each([
    [{ status: "received", id: "id", target: "backend" }, false, "Delivered"],
    [{ status: "timeout", id: "id" }, true, "timeout"],
    [{ status: "timeout", id: "id", reason: "offline", error: "transport_error: offline" }, true, "offline"],
    [{ status: "denied", id: "id", reason: "not_authorized", error: "transport_error: not_authorized" }, true, "not_authorized"],
    [{ status: "denied", id: "id", reason: "bad_envelope", error: "transport_error: bad_envelope" }, true, "bad_envelope"],
  ] satisfies readonly [AckResult, boolean, string][])(
    "preserves the public status and error boundary for %#",
    (ack, isError, marker) => {
      const result = formatMeshAckResult("backend", ack);
      expect(result.isError === true).toBe(isError);
      expect(resultText(result)).toContain(marker);
    },
  );
});
