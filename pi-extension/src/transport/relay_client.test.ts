import { describe, expect, test, vi, beforeEach } from "vitest";
import { EventEmitter } from "node:events";
import { generateEd25519Keypair } from "../pairing/crypto.js";

// ── WS mock (class-based, vitest-hoisted) ─────────────────────────────────────
// Must use a proper class so `new WebSocket(...)` works inside RelayClient.

// Shared reference: set by the MockWS constructor so tests can access it.
const wsRef: { current: MockWS | null } = { current: null };

// `autoOpen: false` models a peer that takes the TCP connection and then never
// completes the WS upgrade — the case `ws` reports with NO `open` and NO `error`.
const wsConfig = { autoOpen: true };

class MockWS extends EventEmitter {
  static OPEN = 1;
  readyState = MockWS.OPEN;
  readonly sent: string[] = [];

  constructor(_url: string) {
    super();
    wsRef.current = this;
    // Defer 'open' so RelayClient has time to attach its handlers first.
    if (wsConfig.autoOpen) setTimeout(() => this.emit("open"), 0);
  }

  send(data: string): void { this.sent.push(data); }
  close(): void {
    this.readyState = 3;
    this.emit("close");
  }
  terminate(): void {
    this.readyState = 3;
    this.emit("close");
  }
}

vi.mock("ws", () => ({ default: MockWS }));

// Import AFTER the mock so RelayClient picks up the mocked ws module.
const { RelayClient } = await import("./relay_client.js");

// ── Helpers ───────────────────────────────────────────────────────────────────

function currentWs(): MockWS {
  if (!wsRef.current) throw new Error("no MockWS instance created yet");
  return wsRef.current;
}

function simulateChallenge(ws: MockWS, nonceByte = 0xab): void {
  const nonce = Buffer.alloc(32, nonceByte);
  ws.emit(
    "message",
    Buffer.from(JSON.stringify({ type: "challenge", nonce: nonce.toString("base64") })),
  );
}

async function connectWithAuth(client: InstanceType<typeof RelayClient>, nonceByte = 0xab): Promise<void> {
  const p = client.connect();
  await vi.waitFor(() => expect(currentWs().sent.length).toBeGreaterThan(0));
  simulateChallenge(currentWs(), nonceByte);
  await p;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("RelayClient", () => {
  let keypair: ReturnType<typeof generateEd25519Keypair>;

  beforeEach(() => {
    keypair = generateEd25519Keypair();
    wsRef.current = null;
    wsConfig.autoOpen = true;
  });

  test("isOpen reflects the real WebSocket lifecycle", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair);
    expect(client.isOpen()).toBe(false);

    await connectWithAuth(client);
    expect(client.isOpen()).toBe(true);

    client.close();
    expect(client.isOpen()).toBe(false);
  });

  test("connect: sends hello with correct Ed25519 pubkey", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair);
    await connectWithAuth(client);

    const ws = currentWs();
    const hello = JSON.parse(ws.sent[0]) as { type: string; pubkey: string };
    expect(hello.type).toBe("hello");
    expect(hello.pubkey).toBe(Buffer.from(keypair.publicKey).toString("base64"));

    client.close();
  });

  test("connect: sends auth with 64-byte Ed25519 signature", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair);
    await connectWithAuth(client);

    const ws = currentWs();
    const auth = JSON.parse(ws.sent[1]) as { type: string; sig: string };
    expect(auth.type).toBe("auth");
    expect(Buffer.from(auth.sig, "base64")).toHaveLength(64);

    client.close();
  });

  test("connect: auth messages (hello + auth) are exactly 2 sends", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair);
    await connectWithAuth(client);

    // hello + auth = 2 sends during auth phase only
    expect(currentWs().sent).toHaveLength(2);
    client.close();
  });

  test("connect: challenge message NOT forwarded as public 'message' event", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair);
    const received: string[] = [];
    client.on("message", (line) => received.push(line));

    await connectWithAuth(client);

    // Challenge should NOT appear in public events
    expect(received.some((l) => l.includes("challenge"))).toBe(false);
    client.close();
  });

  test("connect: post-auth outer envelopes are forwarded as 'message' events", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair);
    const received: string[] = [];
    client.on("message", (line) => received.push(line));

    await connectWithAuth(client);

    const outer = JSON.stringify({ peer: "app_peer_1", ct: "AAAA" });
    currentWs().emit("message", Buffer.from(outer));

    expect(received).toContain(outer);
    client.close();
  });

  test("send: writes raw line to the WebSocket", async () => {
    const client = new RelayClient("ws://localhost:9999", keypair);
    await connectWithAuth(client);

    const ws = currentWs();
    const before = ws.sent.length;
    const outer = JSON.stringify({ peer: "x", ct: "BQID" });
    client.send(outer);
    expect(ws.sent[before]).toBe(outer);

    client.close();
  });

  // ── Liveness watchdog ───────────────────────────────────────────────────────
  // Regression for "daemon shows online but is dead after a few idle hours":
  // a silently half-open WS never fires `close`, so reconnect never triggers.

  async function connectFake(client: InstanceType<typeof RelayClient>): Promise<void> {
    const p = client.connect();
    await vi.advanceTimersByTimeAsync(1);  // MockWS defers 'open' via setTimeout(0)
    simulateChallenge(currentWs());        // resolves auth's _nextMsg
    await p;
  }

  test("liveness: force-closes (→ reconnect) after silence past the timeout", async () => {
    vi.useFakeTimers();
    try {
      const client = new RelayClient("ws://localhost:9999", keypair);
      await connectFake(client);
      let closed = false;
      client.on("close", () => { closed = true; });

      // No inbound frame for > 70s → watchdog terminates → close.
      await vi.advanceTimersByTimeAsync(90_000);
      expect(closed).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });

  // ── Handshake deadline (everything before `open`) ───────────────────────────
  // Regression: `connect()` modelled only two outcomes — `open` (success) and
  // `error` (refusal). A relay that ACCEPTS the TCP connection and then says
  // nothing (hung process, black-holing firewall, LB with a dead upstream)
  // fires neither, so `connect()` never settled. Because `connect()` is awaited
  // inside the `/remote-pi` handler, and hosts run extension commands one at a
  // time, that one unsettled promise silenced every later command — including
  // `/remote-pi stop` — for the life of the process.

  test("handshake: rejects when the peer never completes the WS upgrade", async () => {
    vi.useFakeTimers();
    try {
      wsConfig.autoOpen = false;
      const client = new RelayClient("ws://localhost:9999", keypair);

      const outcome = client.connect().then(
        () => "resolved" as const,
        (err: Error) => err,
      );
      await vi.advanceTimersByTimeAsync(10_000);

      const err = await outcome;
      expect(err).not.toBe("resolved");
      expect((err as Error).message).toMatch(/handshake timeout after 10000ms/);
      // The dead socket is terminated, not left open as a leaked handle.
      expect(currentWs().readyState).toBe(3);
    } finally {
      vi.useRealTimers();
      wsConfig.autoOpen = true;
    }
  });

  test("handshake: rejects when the peer hangs up before the upgrade completes", async () => {
    wsConfig.autoOpen = false;
    const client = new RelayClient("ws://localhost:9999", keypair);

    // connect() attaches its listeners synchronously, so a close right here is
    // a clean FIN with no accompanying `error` event.
    const outcome = client.connect().then(
      () => "resolved" as const,
      (err: Error) => err,
    );
    currentWs().close();

    const err = await outcome;
    expect(err).not.toBe("resolved");
    expect((err as Error).message).toMatch(/closed before the WebSocket handshake completed/);
  });

  test("handshake: deadline is cleared once the upgrade is open", async () => {
    vi.useFakeTimers();
    try {
      const client = new RelayClient("ws://localhost:9999", keypair);
      await connectFake(client);

      let closed = false;
      client.on("close", () => { closed = true; });

      // Past the handshake deadline but inside the 70s liveness window: a timer
      // left armed here would terminate() a perfectly healthy connection.
      await vi.advanceTimersByTimeAsync(30_000);
      expect(closed).toBe(false);
      expect(client.isOpen()).toBe(true);

      client.close();
    } finally {
      vi.useRealTimers();
    }
  });

  test("liveness: relay's ~25s pings keep it alive (no spurious close)", async () => {
    vi.useFakeTimers();
    try {
      const client = new RelayClient("ws://localhost:9999", keypair);
      await connectFake(client);
      let closed = false;
      client.on("close", () => { closed = true; });

      // Simulate the relay's keepalive ping every 25s for 2.5 min.
      for (let i = 0; i < 6; i++) {
        await vi.advanceTimersByTimeAsync(25_000);
        currentWs().emit("ping");
      }
      expect(closed).toBe(false);
      client.close();
    } finally {
      vi.useRealTimers();
    }
  });
});
