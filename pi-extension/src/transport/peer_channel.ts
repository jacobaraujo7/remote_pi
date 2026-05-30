import type { ClientMessage, ServerMessage } from "../protocol/types.js";
import {
  isSignedInnerV1,
  signInnerV1,
  SignedInnerReplayCache,
  verifyInnerV1,
} from "../protocol/signed_inner.js";
import type { Ed25519Keypair } from "../pairing/crypto.js";
import type { RelayClient } from "./relay_client.js";

/** Sink for ServerMessage outbound to the remote app. */
export interface PeerChannel {
  send(msg: ServerMessage): void;
}

/**
 * Outer envelope shape forwarded by the relay.
 * { "peer": "<sender_peer_id>", "room"?: "<room_id>", "ct": "<base64 JSON inner>" }
 *
 * Post rollback (plano 06): `ct` is base64(JSON.stringify(inner)) — no cipher,
 * no MAC. Relay continues opaque (never JSON.parses ct).
 *
 * `room` (plano 17): identifies which Pi room sent the envelope. Lets the
 * relay multiplex N peers with the same Ed25519 pubkey but distinct cwds.
 * Optional for backward-compat with single-room relays.
 */
interface OuterEnvelope {
  peer: string;
  room?: string;
  ct: string;
}

/**
 * Plaintext PeerChannel backed by a RelayClient WebSocket.
 *
 * Usage (after pair_request handshake completes):
 *   const channel = new PlainPeerChannel(relay, appPeerId, myRoomId, onMsg)
 *   channel.send(serverMessage)          // base64-encodes JSON, routes via relay
 *   // incoming relay messages destined for appPeerId are auto-decoded
 *   // and delivered via onMessage callback
 *
 * `myRoomId` is the *local* Pi's room id — sent on every outbound envelope
 * so the app can correlate which Pi sent it (multi-pi support, plano 17).
 */
export interface SignedInnerOptions {
  localKeypair: Ed25519Keypair;
  expectedRemotePubkey: string;
  roomId: string;
  requireSigned?: boolean;
  replayCache?: SignedInnerReplayCache;
}

export class PlainPeerChannel implements PeerChannel {
  private readonly _unsubscribe: () => void;
  private readonly _signed?: Required<SignedInnerOptions>;

  constructor(
    private readonly relay: RelayClient,
    private readonly remotePeerId: string,
    /**
     * This Pi's room id. Currently NOT injected in the outer envelope
     * (defensive — relay/app not yet ready). Kept in the constructor for
     * forward-compat so callers don't need to change again when we re-enable.
     */
    myRoomId: string | undefined,
    private readonly onMessage: (msg: ClientMessage) => void,
    /** Called when this specific peer connection is considered lost. */
    _onDisconnect?: () => void,
    signed?: SignedInnerOptions,
  ) {
    const listener = (line: string) => this._onLine(line);
    relay.on("message", listener);
    this._unsubscribe = () => relay.off("message", listener);
    if (signed) {
      this._signed = {
        ...signed,
        requireSigned: signed.requireSigned ?? true,
        replayCache: signed.replayCache ?? new SignedInnerReplayCache(),
      };
    }
    void _onDisconnect;
    void myRoomId;  // intentionally unused — see send() comment
  }

  // ── PeerChannel interface ──────────────────────────────────────────────────

  send(msg: ServerMessage): void {
    const inner = this._signed
      ? signInnerV1({
          payload: msg as Record<string, unknown>,
          sender: this._signed.localKeypair,
          recipientPk: this._signed.expectedRemotePubkey,
          roomId: this._signed.roomId,
        })
      : msg;
    const ct = Buffer.from(JSON.stringify(inner)).toString("base64");
    // NOTE: `room` removed from the outer envelope until relay (W1.A) + app
    // (W1.C) accept the field. Multi-Pi multiplexing already works via
    // `room_id`/`room_meta` in the WS-level `hello` — outer routing stays by
    // `peer` alone. Re-add the field once downstream is ready.
    const outer: OuterEnvelope = { peer: this.remotePeerId, ct };
    this.relay.send(JSON.stringify(outer));
  }

  /** Routes an already-received relay line through this channel's verifier. */
  acceptRelayLine(line: string): void {
    this._onLine(line);
  }

  /** Detaches from relay (does not close the relay itself). */
  detach(): void {
    this._unsubscribe();
  }

  // ── Incoming line from relay ────────────────────────────────────────────────

  private _onLine(line: string): void {
    let outer: OuterEnvelope;
    try {
      outer = JSON.parse(line) as OuterEnvelope;
    } catch {
      return; // malformed line
    }

    if (outer.peer !== this.remotePeerId) return;
    if (!outer.ct) return;

    let plaintext: string;
    try {
      plaintext = Buffer.from(outer.ct, "base64").toString("utf8");
    } catch {
      return;
    }

    let msg: unknown;
    try {
      msg = JSON.parse(plaintext);
    } catch {
      return;
    }

    if (
      !msg ||
      typeof msg !== "object" ||
      typeof (msg as Record<string, unknown>).type !== "string"
    ) {
      return;
    }

    if (isSignedInnerV1(msg)) {
      if (!this._signed) return;
      const localPk = Buffer.from(this._signed.localKeypair.publicKey).toString("base64");
      let verified: ReturnType<typeof verifyInnerV1>;
      try {
        verified = verifyInnerV1({
          frame: msg,
          expectedSenderPk: this._signed.expectedRemotePubkey,
          expectedRecipientPk: localPk,
          expectedRoomId: this._signed.roomId,
          replay: this._signed.replayCache,
        });
      } catch {
        return;
      }
      if (!verified.ok) return;
      this.onMessage(verified.payload as ClientMessage);
      return;
    }

    if (this._signed?.requireSigned) return;
    this.onMessage(msg as ClientMessage);
  }
}
