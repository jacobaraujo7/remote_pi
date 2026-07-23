use base64::{
    Engine as _,
    engine::general_purpose::{STANDARD as B64, STANDARD_NO_PAD, URL_SAFE, URL_SAFE_NO_PAD},
};
use ed25519_dalek::{Signer as _, SigningKey};

use super::challenge::{AuthError, gen_nonce, parse_hello, verify_auth};

/// First message is not "hello" → NoHello error.
#[test]
fn sem_hello() {
    // Send an "auth" message before any hello
    let line = r#"{"type":"auth","sig":"AAAA"}"#;
    let err = parse_hello(line).unwrap_err();
    assert!(matches!(err, AuthError::NoHello));
}

#[test]
fn hello_accepts_standard_and_url_safe_padded_and_unpadded_keys() {
    let sk = SigningKey::from_bytes(&[2_u8; 32]);
    let expected = sk.verifying_key();
    let key_bytes = expected.to_bytes();
    let standard = B64.encode(key_bytes);
    assert!(
        standard.contains('+') && standard.contains('/'),
        "fixture must exercise both base64 alphabets",
    );

    for encoded in [
        standard,
        STANDARD_NO_PAD.encode(key_bytes),
        URL_SAFE.encode(key_bytes),
        URL_SAFE_NO_PAD.encode(key_bytes),
    ] {
        let line = serde_json::json!({"type": "hello", "pubkey": encoded}).to_string();
        assert_eq!(parse_hello(&line).unwrap(), expected);
    }
}

#[test]
fn hello_rejects_malformed_or_wrong_length_keys() {
    let malformed = serde_json::json!({"type": "hello", "pubkey": "not base64"}).to_string();
    assert!(parse_hello(&malformed).is_err());

    for bytes in [vec![7_u8; 31], vec![7_u8; 33]] {
        for encoded in [B64.encode(&bytes), URL_SAFE_NO_PAD.encode(&bytes)] {
            let line = serde_json::json!({"type": "hello", "pubkey": encoded}).to_string();
            assert!(parse_hello(&line).is_err());
        }
    }
}

/// Valid key pair but signature covers wrong bytes → InvalidSig.
#[test]
fn sig_invalida() {
    let (nonce, _) = gen_nonce();
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let vk = sk.verifying_key();

    // Sign something other than the nonce
    let wrong_sig = sk.sign(b"not the nonce");
    let sig_b64 = B64.encode(wrong_sig.to_bytes());
    let line = format!(r#"{{"type":"auth","sig":"{}"}}"#, sig_b64);

    let err = verify_auth(&nonce, &vk, &line).unwrap_err();
    assert!(matches!(err, AuthError::InvalidSig));
}

/// Valid key pair, signature covers the correct nonce bytes → success.
#[test]
fn sig_valida() {
    let (nonce, _) = gen_nonce();
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let vk = sk.verifying_key();

    let sig = sk.sign(&nonce);
    let sig_b64 = B64.encode(sig.to_bytes());
    let line = format!(r#"{{"type":"auth","sig":"{}"}}"#, sig_b64);

    verify_auth(&nonce, &vk, &line).unwrap();
}
