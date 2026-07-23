/**
 * Ping → Pong roundtrip test.
 *
 * Verifies the full flow: app sends a `ping` ClientMessage over the relay,
 * the extension handler calls `_peerChannel.send({ type: "pong", … })`,
 * and the pong is sent back to the correct peer with the matching id.
 */
import { describe, expect, test, vi, beforeEach } from "vitest";
import { EventEmitter } from "node:events";

// ── Mock RelayClient ──────────────────────────────────────────────────────────

const relayRef: { current: MockRelay | null } = { current: null };

class MockRelay extends EventEmitter {
  static OPEN = 1;
  readyState = MockRelay.OPEN;
  connect     = vi.fn();
  send        = vi.fn();
  sendControl = vi.fn();
  close       = vi.fn();
  constructor() { super(); relayRef.current = this; }
}

// ── Mock storage (empty — no peer persistence tests here) ─────────────────────

vi.mock("../src/pairing/storage.js", async (importOriginal) => {
  const orig = await importOriginal<typeof import("../src/pairing/storage.js")>();
  return {
    ...orig,
    getOrCreateEd25519Keypair: vi.fn().mockResolvedValue({
      publicKey: new Uint8Array(32),
      secretKey: new Uint8Array(32),
    }),
    listPeers: vi.fn().mockResolvedValue([]),
    snapshotOwnerPubkeys: vi.fn().mockRejectedValue(
      new Error("strict Owner snapshot unavailable"),
    ),
    addPeer: vi.fn(),
    removePeer: vi.fn(),
  };
});

// ── Mock config ───────────────────────────────────────────────────────────────

vi.mock("../src/config.js", async (importOriginal) => {
  const orig = await importOriginal<typeof import("../src/config.js")>();
  return {
    ...orig,
    loadConfig: vi.fn().mockReturnValue({}),
    saveConfig: vi.fn(),
    resolveRelayUrl: vi.fn().mockReturnValue({
      url: "ws://localhost:3000",
      source: "default" as const,
    }),
  };
});

// ── Mock qr ───────────────────────────────────────────────────────────────────

vi.mock("../src/pairing/qr.js", async (importOriginal) => {
  const orig = await importOriginal<typeof import("../src/pairing/qr.js")>();
  return {
    ...orig,
    displayQR: vi.fn(),
    qrSession: {
      issueToken: vi.fn().mockReturnValue({ token: "test-token", expiresAt: Date.now() + 60_000 }),
      consumeToken: vi.fn().mockReturnValue("ok"),
      clear: vi.fn(),
      generateToken: vi.fn().mockReturnValue("test-token"),
    },
  };
});

// Mock RelayClient *after* qr import (so module resolution order is consistent)
vi.mock("../src/transport/relay_client.js", () => ({
  RelayClient: MockRelay,
}));

// ── Import the extension after mocks ──────────────────────────────────────────

const {
  default: extension,
  _getState,
  routeClientMessage,
  _startRelayForTest,
  _stopForTest,
} = await import("../src/index.js");

import type { ExtensionAPI, ExtensionFactory } from "@mariozechner/pi-coding-agent";

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeMockCtx() {
  return { ui: { notify: vi.fn() }, cwd: "/tmp/test", abort: vi.fn() };
}

function makeInnerLine(peer: string, inner: object): string {
  const ct = Buffer.from(JSON.stringify(inner)).toString("base64");
  return JSON.stringify({ peer, ct });
}

function decodeSentCt(raw: string): { peer: string; inner: Record<string, unknown> } {
  const outer = JSON.parse(raw) as { peer: string; ct: string };
  const inner = JSON.parse(Buffer.from(outer.ct, "base64").toString("utf8"));
  return { peer: outer.peer, inner };
}

/**
 * Pair the extension by emitting a `start` command then injecting a
 * `pair_request` via the relay mock.
 */
async function pairUp(): Promise<void> {
  // Bring just the relay up (no UDS mesh — this test is relay-focused).
  // The 2026-05-23 surface cleanup removed `remote-pi relay start`; the
  // equivalent for tests is `_startRelayForTest`.
  const pi = {
    on: () => undefined,
    registerCommand: () => undefined,
    registerTool: () => undefined,
    registerShortcut: () => undefined,
    registerFlag: () => undefined,
    getFlag: () => undefined,
    registerMessageRenderer: () => undefined,
    sendMessage: () => undefined,
    sendUserMessage: () => undefined,
  } as unknown as ExtensionAPI;
  (extension as ExtensionFactory)(pi);

  await _startRelayForTest(makeMockCtx());
  expect(_getState()).toBe("started");

  // Inject a pair_request
  relayRef.current!.emit("message", makeInnerLine("app-peer-001", {
    type: "pair_request",
    id: "pair-req-1",
    token: "test-token",
    device_name: "Test Phone",
  }));

  // Wait for paired
  await vi.waitFor(() => expect(_getState()).toBe("paired"), { timeout: 2000 });
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("ping → pong roundtrip", () => {
  beforeEach(async () => {
    vi.clearAllMocks();
    relayRef.current = null;

    // Stop any active session first (idempotent — safe when already idle).
    await _stopForTest(makeMockCtx());
  });

  test("ping from paired peer → pong sent back with matching in_reply_to", async () => {
    await pairUp();
    expect(_getState()).toBe("paired");

    const sendsBefore = relayRef.current!.send.mock.calls.length;

    // App sends a ping
    relayRef.current!.emit("message", makeInnerLine("app-peer-001", {
      type: "ping",
      id: "ping-abc-123",
    }));

    // Small delay for async handler
    await new Promise((r) => setTimeout(r, 30));

    const sent = relayRef.current!.send.mock.calls
      .slice(sendsBefore)
      .map((c: unknown[]) => c[0] as string);

    // Find pong frames directed to our peer
    const pongs = sent
      .map(decodeSentCt)
      .filter((d) => d.inner.type === "pong");

    expect(pongs).toHaveLength(1);
    expect(pongs[0]!.peer).toBe("app-peer-001");
    expect(pongs[0]!.inner).toMatchObject({
      type: "pong",
      in_reply_to: "ping-abc-123",
    });
  });

  test("ping from unknown peer → no pong sent (ignored by routeClientMessage)", async () => {
    await pairUp();

    const sendsBefore = relayRef.current!.send.mock.calls.length;

    // Unknown peer sends a ping (not the paired one)
    relayRef.current!.emit("message", makeInnerLine("some-rando-peer", {
      type: "ping",
      id: "ping-rando",
    }));

    await new Promise((r) => setTimeout(r, 30));

    const sent = relayRef.current!.send.mock.calls
      .slice(sendsBefore)
      .map((c: unknown[]) => c[0] as string);

    const pongs = sent
      .map(decodeSentCt)
      .filter((d) => d.inner.type === "pong");

    expect(pongs).toHaveLength(0);
  });

  test("two pings → two pongs, each with correct in_reply_to", async () => {
    await pairUp();

    const sendsBefore = relayRef.current!.send.mock.calls.length;

    relayRef.current!.emit("message", makeInnerLine("app-peer-001", {
      type: "ping", id: "ping-001",
    }));
    relayRef.current!.emit("message", makeInnerLine("app-peer-001", {
      type: "ping", id: "ping-002",
    }));

    await new Promise((r) => setTimeout(r, 30));

    const sent = relayRef.current!.send.mock.calls
      .slice(sendsBefore)
      .map((c: unknown[]) => c[0] as string);

    const pongs = sent
      .map(decodeSentCt)
      .filter((d) => d.inner.type === "pong");

    expect(pongs).toHaveLength(2);

    const replyToIds = pongs.map((d) => d.inner["in_reply_to"]);
    expect(replyToIds).toEqual(["ping-001", "ping-002"]);
  });

  test("ping in idle state (no relay) → no crash, no pong", async () => {
    // Don't start at all — state is "idle"
    expect(_getState()).toBe("idle");

    // routeClientMessage with no _peerChannel should return early
    routeClientMessage(
      { type: "ping", id: "ping-idle" },
      { abort: vi.fn() },
    );

    // No relay was ever created, so no send could have been called
    expect(relayRef.current).toBeNull();
  });

  test(
    "ping → pong within 5 seconds",
    async () => {
      await pairUp();

      const sendsBefore = relayRef.current!.send.mock.calls.length;

      relayRef.current!.emit("message", makeInnerLine("app-peer-001", {
        type: "ping", id: "ping-5sec",
      }));

      // Wait 5 seconds to ensure async handler completes in time
      await new Promise((r) => setTimeout(r, 5000));

      const sent = relayRef.current!.send.mock.calls
        .slice(sendsBefore)
        .map((c: unknown[]) => c[0] as string);

      const pongs = sent
        .map(decodeSentCt)
        .filter((d) => d.inner.type === "pong");

      expect(pongs).toHaveLength(1);
      expect(pongs[0]!.inner).toMatchObject({
        type: "pong",
        in_reply_to: "ping-5sec",
      });
    },
    10_000,
  );
});
