use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use ed25519_dalek::{Signature, VerifyingKey};

use crate::identity::{PublicKeyDecodeError, decode_ed25519_public_key};

use super::types::{MeshEnvelope, MeshEnvelopeWire, MeshHeader};

#[derive(Debug, thiserror::Error)]
pub enum VerifyError {
    #[error("invalid base64: {0}")]
    BadBase64(String),
    #[error("blob is not valid JSON or missing required fields: {0}")]
    BadBlobJson(String),
    #[error("owner_pk in blob is not a valid 32-byte Ed25519 key")]
    BadOwnerPk,
    #[error("member remote_epk is not valid base64 or does not decode to 32 bytes")]
    BadMemberPk,
    #[error("sig is not 64 bytes")]
    BadSigLength,
    #[error("Ed25519 signature verification failed")]
    SigFailed,
}

#[derive(Debug)]
pub(crate) struct VerifiedMeshHeader {
    pub(crate) header: MeshHeader,
    pub(crate) owner_pk: [u8; 32],
}

/// Verifies the envelope's signature against the blob using the owner_pk
/// embedded in the blob, validates the complete member boundary, and returns
/// the parsed header with the already-decoded Owner bytes.
///
/// **Canonical-JSON contract**: the relay does NOT canonicalize the blob —
/// it verifies the signature against exactly the bytes received. Clients are
/// responsible for producing canonical JSON before signing: keys sorted
/// lexicographically, no whitespace, JCS-style (RFC 8785 simplified).
/// Different serializers may produce different bytes for the same logical
/// object — agree on one canonical form across Dart, Rust, TypeScript.
pub(crate) fn verify_envelope(env: &MeshEnvelope) -> Result<VerifiedMeshHeader, VerifyError> {
    let header: MeshHeader = serde_json::from_slice(&env.blob)
        .map_err(|error| VerifyError::BadBlobJson(error.to_string()))?;

    let owner_pk = match decode_ed25519_public_key(&header.owner_pk) {
        Ok(owner_pk) => owner_pk,
        Err(PublicKeyDecodeError::BadBase64) => {
            return Err(VerifyError::BadBase64("owner_pk".to_string()));
        }
        Err(PublicKeyDecodeError::BadLength { .. }) => return Err(VerifyError::BadOwnerPk),
    };
    let verifying_key = VerifyingKey::from_bytes(&owner_pk).map_err(|_| VerifyError::BadOwnerPk)?;

    let signature_bytes: [u8; 64] = env
        .sig
        .as_slice()
        .try_into()
        .map_err(|_| VerifyError::BadSigLength)?;
    let signature = Signature::from_bytes(&signature_bytes);

    verifying_key
        .verify_strict(&env.blob, &signature)
        .map_err(|_| VerifyError::SigFailed)?;

    if header
        .members
        .iter()
        .any(|member| decode_ed25519_public_key(&member.remote_epk).is_err())
    {
        return Err(VerifyError::BadMemberPk);
    }

    Ok(VerifiedMeshHeader { header, owner_pk })
}

/// Decodes the wire envelope (base64 strings) into raw bytes.
pub fn decode_wire(wire: &MeshEnvelopeWire) -> Result<MeshEnvelope, VerifyError> {
    let blob = B64
        .decode(&wire.blob)
        .map_err(|e| VerifyError::BadBase64(format!("blob: {e}")))?;
    let sig = B64
        .decode(&wire.sig)
        .map_err(|e| VerifyError::BadBase64(format!("sig: {e}")))?;
    Ok(MeshEnvelope { blob, sig })
}

/// SHA-256 of the raw owner_pk bytes, lowercase hex (matches what clients
/// embed in the URL path).
pub fn owner_pk_hash(owner_pk: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let digest = Sha256::digest(owner_pk);
    let mut out = String::with_capacity(64);
    for b in digest {
        out.push_str(&format!("{b:02x}"));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};

    fn sign_envelope(sk: &SigningKey, blob: Vec<u8>) -> MeshEnvelope {
        let sig = sk.sign(&blob).to_bytes().to_vec();
        MeshEnvelope { blob, sig }
    }

    fn make_blob_with_members(
        version: u64,
        owner_pk: &str,
        members: Vec<serde_json::Value>,
    ) -> Vec<u8> {
        // We don't strictly need canonicalization for the relay's verify path,
        // only consistent bytes. Tests sign whatever bytes they produce here.
        serde_json::to_vec(&serde_json::json!({
            "owner_pk": owner_pk,
            "version": version,
            "issued_at": 1_700_000_000_000_u64,
            "members": members,
        }))
        .unwrap()
    }

    fn make_blob(version: u64, owner_pk: &str) -> Vec<u8> {
        make_blob_with_members(version, owner_pk, vec![])
    }

    #[test]
    fn verifies_valid_envelope() {
        let sk = SigningKey::generate(&mut rand::thread_rng());
        let pk_b64 = B64.encode(sk.verifying_key().to_bytes());
        let blob = make_blob(7, &pk_b64);
        let env = sign_envelope(&sk, blob);

        let verified = verify_envelope(&env).unwrap();
        assert_eq!(verified.header.version, 7);
        assert_eq!(verified.header.owner_pk, pk_b64);
        assert_eq!(verified.owner_pk, sk.verifying_key().to_bytes());
    }

    #[test]
    fn rejects_invalid_member_key_after_signature_verification() {
        let sk = SigningKey::generate(&mut rand::thread_rng());
        let owner_pk = B64.encode(sk.verifying_key().to_bytes());
        let blob = make_blob_with_members(
            1,
            &owner_pk,
            vec![serde_json::json!({
                "remote_epk": "not base64",
                "relay_url": "wss://relay.example.test",
                "paired_at": "2025-01-01T00:00:00.000Z",
            })],
        );
        let envelope = sign_envelope(&sk, blob);

        assert!(matches!(
            verify_envelope(&envelope),
            Err(VerifyError::BadMemberPk),
        ));
    }

    #[test]
    fn rejects_tampered_blob() {
        let sk = SigningKey::generate(&mut rand::thread_rng());
        let pk_b64 = B64.encode(sk.verifying_key().to_bytes());
        let signed = sign_envelope(&sk, make_blob(7, &pk_b64));
        let bad = MeshEnvelope {
            blob: make_blob(99, &pk_b64),
            sig: signed.sig,
        };
        assert!(matches!(verify_envelope(&bad), Err(VerifyError::SigFailed)));
    }

    #[test]
    fn rejects_wrong_pk() {
        let sk = SigningKey::generate(&mut rand::thread_rng());
        let other_sk = SigningKey::generate(&mut rand::thread_rng());
        let other_pk_b64 = B64.encode(other_sk.verifying_key().to_bytes());
        // Blob says owner_pk = other, but signed by sk.
        let blob = make_blob(1, &other_pk_b64);
        let env = sign_envelope(&sk, blob);
        assert!(matches!(verify_envelope(&env), Err(VerifyError::SigFailed)));
    }

    #[test]
    fn computes_sha256_lowercase_hex() {
        // sha256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        let h = owner_pk_hash(&[]);
        assert_eq!(
            h,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }
}
