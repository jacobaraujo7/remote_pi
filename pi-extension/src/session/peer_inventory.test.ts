import { describe, expect, test } from "vitest";
import { formatPeerInventory } from "./peer_inventory.js";

describe("formatPeerInventory", () => {
  test("local peer with no colon", () => {
    expect(formatPeerInventory(["sess-1"])).toBe("  local:\n    sess-1");
  });

  test("remote peer with pc_label prefix", () => {
    expect(formatPeerInventory(["casa:sess-3"])).toBe(
      "  local:\n    (none)\n\n  remote:casa\n    sess-3",
    );
  });

  test("excludes selfName", () => {
    expect(formatPeerInventory(["sess-1", "sess-2"], "sess-1")).toBe(
      "  local:\n    sess-2",
    );
  });

  // Regression test: on Windows, a local peer's cwd-derived address embeds a
  // drive-letter colon (e.g. "C:\Users\ich\project@agent-1"). Before the
  // drive-letter guard, the first colon (right after "C") was mistaken for a
  // "<pc_label>:" remote prefix, so every local Windows peer rendered as a
  // bogus remote peer under a one-letter pc label "C" with a mangled path as
  // its "peer name" (e.g. "remote:C" / "\Users\ich\project@agent-1").
  test("Windows local peer address (drive-letter cwd) stays local", () => {
    const peers = ["C:\\Users\\ich\\Documents\\claude\\Trading Bot@Trading-Bot"];
    expect(formatPeerInventory(peers)).toBe(
      "  local:\n    C:\\Users\\ich\\Documents\\claude\\Trading Bot@Trading-Bot",
    );
  });

  test("Windows local peer address with forward slashes stays local", () => {
    const peers = ["D:/repos/project@agent-1"];
    expect(formatPeerInventory(peers)).toBe("  local:\n    D:/repos/project@agent-1");
  });

  test("real remote label still works alongside Windows local peers", () => {
    const peers = [
      "C:\\Users\\ich\\project@agent-1",
      "casa:sess-3",
    ];
    expect(formatPeerInventory(peers)).toBe(
      [
        "  local:",
        "    C:\\Users\\ich\\project@agent-1",
        "",
        "  remote:casa",
        "    sess-3",
      ].join("\n"),
    );
  });
});
