import { describe, expect, test } from "vitest";
import { buildQRUri } from "./qr.js";

describe("buildQRUri", () => {
  test("advertises signed_inner_v1 support with si=1", () => {
    const uri = new URL(buildQRUri("AAAAAAAAAAAAAAAAAAAAAA", new Uint8Array(32), "Pi", "room-1"));
    expect(uri.protocol).toBe("remotepi:");
    expect(uri.searchParams.get("si")).toBe("1");
    expect(uri.searchParams.get("rm")).toBe("room-1");
  });
});
