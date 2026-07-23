// Types not yet wired into the WS handler — will be connected in routing step.
#![allow(dead_code)]

use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use ed25519_dalek::{Signature, VerifyingKey};
use rand::RngCore as _;
use serde::{Deserialize, Serialize};

use crate::identity::decode_ed25519_public_key;

/// Max milliseconds to wait for a "hello" before closing the connection.
pub const HELLO_TIMEOUT_MS: u64 = 5_000;

/// Messages that a peer sends during the auth handshake.
#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientAuthMsg {
    Hello { pubkey: String },
    Auth { sig: String },
}

/// Messages that the relay sends during the auth handshake.
#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerAuthMsg {
    Challenge { nonce: String },
}

#[derive(Debug, thiserror::Error)]
pub enum AuthError {
    #[error("expected hello, got other message")]
    NoHello,
    #[error("invalid pubkey: {0}")]
    InvalidPubkey(String),
    #[error("base64 decode error: {0}")]
    Base64(#[from] base64::DecodeError),
    #[error("invalid signature")]
    InvalidSig,
    #[error("unexpected message type in auth step")]
    UnexpectedMsg,
    #[error("json parse error: {0}")]
    Json(#[from] serde_json::Error),
}

/// Generates a fresh 32-byte random nonce. Returns (raw bytes, base64 string).
pub fn gen_nonce() -> ([u8; 32], String) {
    let mut nonce = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut nonce);
    let b64 = B64.encode(nonce);
    (nonce, b64)
}

/// Parses a JSONL "hello" line and returns the peer's Ed25519 verifying key.
/// Returns [`AuthError::NoHello`] if the line is not a hello message.
pub fn parse_hello(line: &str) -> Result<VerifyingKey, AuthError> {
    let msg: ClientAuthMsg = serde_json::from_str(line)?;
    match msg {
        ClientAuthMsg::Hello { pubkey } => {
            let public_key = decode_ed25519_public_key(&pubkey)
                .map_err(|error| AuthError::InvalidPubkey(error.to_string()))?;
            VerifyingKey::from_bytes(&public_key)
                .map_err(|error| AuthError::InvalidPubkey(error.to_string()))
        }
        _ => Err(AuthError::NoHello),
    }
}

/// Serialises the challenge message to a JSONL string (no trailing newline).
pub fn challenge_line(nonce_b64: &str) -> String {
    serde_json::to_string(&ServerAuthMsg::Challenge {
        nonce: nonce_b64.to_owned(),
    })
    .expect("ServerAuthMsg serialisation is infallible")
}

/// Parses an "auth" line and verifies the Ed25519 signature against `nonce`.
/// Relay never decodes `ct` — this only verifies the auth-handshake signature.
pub fn verify_auth(nonce: &[u8; 32], vk: &VerifyingKey, line: &str) -> Result<(), AuthError> {
    let msg: ClientAuthMsg = serde_json::from_str(line)?;
    let sig_b64 = match msg {
        ClientAuthMsg::Auth { sig } => sig,
        _ => return Err(AuthError::UnexpectedMsg),
    };
    let sig_bytes = B64.decode(&sig_b64)?;
    let sig_arr: [u8; 64] = sig_bytes.try_into().map_err(|_| AuthError::InvalidSig)?;
    let sig = Signature::from_bytes(&sig_arr);
    use ed25519_dalek::Verifier as _;
    vk.verify(nonce, &sig).map_err(|_| AuthError::InvalidSig)
}
