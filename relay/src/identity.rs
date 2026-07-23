use base64::{
    Engine as _,
    engine::general_purpose::{STANDARD, STANDARD_NO_PAD},
};

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub(crate) enum PublicKeyDecodeError {
    #[error("invalid public-key base64")]
    BadBase64,
    #[error("public key must decode to exactly 32 bytes (got {actual})")]
    BadLength { actual: usize },
}

pub(crate) fn decode_ed25519_public_key(encoded: &str) -> Result<[u8; 32], PublicKeyDecodeError> {
    let has_standard = encoded.bytes().any(|byte| matches!(byte, b'+' | b'/'));
    let has_url_safe = encoded.bytes().any(|byte| matches!(byte, b'-' | b'_'));
    if has_standard && has_url_safe {
        return Err(PublicKeyDecodeError::BadBase64);
    }

    let normalized = encoded.replace('-', "+").replace('_', "/");
    let decoded = STANDARD
        .decode(&normalized)
        .or_else(|_| STANDARD_NO_PAD.decode(&normalized))
        .map_err(|_| PublicKeyDecodeError::BadBase64)?;
    let actual = decoded.len();
    decoded
        .try_into()
        .map_err(|_| PublicKeyDecodeError::BadLength { actual })
}

pub(crate) fn canonical_ed25519_public_key(encoded: &str) -> Result<String, PublicKeyDecodeError> {
    Ok(STANDARD.encode(decode_ed25519_public_key(encoded)?))
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::engine::general_purpose::{STANDARD, STANDARD_NO_PAD, URL_SAFE, URL_SAFE_NO_PAD};

    const STANDARD_KEY: &str = "+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/s=";
    const URL_SAFE_KEY: &str = "-_v7-_v7-_v7-_v7-_v7-_v7-_v7-_v7-_v7-_v7-_s=";

    #[test]
    fn canonical_public_key_accepts_standard_and_url_safe_variants() {
        let expected_bytes = [0xfb; 32];
        assert_eq!(STANDARD.encode(expected_bytes), STANDARD_KEY);
        assert_eq!(URL_SAFE.encode(expected_bytes), URL_SAFE_KEY);

        let variants = [
            STANDARD_KEY.to_string(),
            STANDARD_NO_PAD.encode(expected_bytes),
            URL_SAFE_KEY.to_string(),
            URL_SAFE_NO_PAD.encode(expected_bytes),
        ];
        for encoded in variants {
            assert_eq!(
                decode_ed25519_public_key(&encoded),
                Ok(expected_bytes),
                "decode failed for {encoded}",
            );
            assert_eq!(
                canonical_ed25519_public_key(&encoded),
                Ok(STANDARD_KEY.to_string()),
                "canonicalization failed for {encoded}",
            );
        }
    }

    #[test]
    fn canonical_public_key_rejects_invalid_or_wrong_length() {
        assert_eq!(
            canonical_ed25519_public_key("not base64"),
            Err(PublicKeyDecodeError::BadBase64),
        );
        for bytes in [vec![7_u8; 31], vec![7_u8; 33]] {
            let encoded = STANDARD.encode(&bytes);
            assert_eq!(
                canonical_ed25519_public_key(&encoded),
                Err(PublicKeyDecodeError::BadLength {
                    actual: bytes.len(),
                }),
            );
        }
    }

    #[test]
    fn canonical_public_key_rejects_mixed_alphabets_padding_and_trailing_data() {
        let mixed_with_url_dash = STANDARD_KEY.replacen('+', "-", 1);
        let mixed_with_url_underscore = STANDARD_KEY.replacen('/', "_", 1);
        let interior_padding = STANDARD_KEY.replacen('/', "/=", 1);
        let invalid_cases = [
            mixed_with_url_dash,
            mixed_with_url_underscore,
            interior_padding,
            format!("{STANDARD_KEY}="),
            format!("{STANDARD_KEY}garbage"),
            format!("{STANDARD_KEY}\n"),
            format!("{STANDARD_KEY} "),
            format!("%{STANDARD_KEY}"),
        ];

        for encoded in invalid_cases {
            assert_eq!(
                canonical_ed25519_public_key(&encoded),
                Err(PublicKeyDecodeError::BadBase64),
                "accepted invalid encoding {encoded:?}",
            );
        }
    }

    #[test]
    fn canonical_public_key_rejects_noncanonical_trailing_bits() {
        let prefix = STANDARD_KEY
            .strip_suffix("s=")
            .expect("fixture must end in canonical trailing symbol and padding");
        for encoded in [format!("{prefix}t="), format!("{prefix}t")] {
            assert_eq!(
                canonical_ed25519_public_key(&encoded),
                Err(PublicKeyDecodeError::BadBase64),
                "accepted noncanonical trailing bits {encoded}",
            );
        }
    }
}
