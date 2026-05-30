use serde_json::{Map, Value};

const SENSITIVE_KEYS: &[&str] = &[
    "ct",
    "token",
    "t",
    "sig",
    "signature",
    "auth",
    "secret",
    "sk",
    "privateKey",
    "private_key",
    "prompt",
    "reply",
    "response",
    "text",
    "message",
    "body",
    "payload",
    "qr",
    "uri",
];

pub fn short_id(value: &str) -> String {
    let visible = 8;
    let mut chars = value.chars();
    let prefix: String = chars.by_ref().take(visible).collect();
    if chars.next().is_none() {
        value.to_string()
    } else {
        format!("{prefix}…")
    }
}

pub fn safe_log_string(value: &str) -> String {
    if value.starts_with("remotepi://") {
        return "[redacted-uri]".to_string();
    }
    if value.len() > 48
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '/' | '=' | '_' | '-'))
    {
        return format!("{}…({} chars)", &value[..8], value.len());
    }
    value.to_string()
}

pub fn safe_frame_type(value: &str) -> String {
    if value.len() <= 64 && value.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
        value.to_string()
    } else {
        "[redacted-type]".to_string()
    }
}

pub fn redact_for_log(value: &Value) -> Value {
    redact_value(None, value)
}

fn redact_value(key: Option<&str>, value: &Value) -> Value {
    if key.is_some_and(|k| SENSITIVE_KEYS.contains(&k)) {
        return Value::String("[redacted]".to_string());
    }

    match value {
        Value::String(s) => Value::String(safe_log_string(s)),
        Value::Array(values) => {
            Value::Array(values.iter().map(|v| redact_value(None, v)).collect())
        }
        Value::Object(map) => {
            let redacted = map
                .iter()
                .map(|(entry_key, entry_value)| {
                    (
                        entry_key.clone(),
                        redact_value(Some(entry_key), entry_value),
                    )
                })
                .collect::<Map<String, Value>>();
            Value::Object(redacted)
        }
        other => other.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_protocol_payloads_tokens_signatures_and_message_bodies() {
        let redacted = redact_for_log(&serde_json::json!({
            "type": "pair_request",
            "id": "msg-1",
            "ct": "base64-ciphertext",
            "token": "pair-token-secret",
            "sig": "auth-signature-secret",
            "body": { "type": "user_message", "text": "please leak this prompt" },
            "payload": { "response": "assistant reply secret" },
        }));

        let rendered = redacted.to_string();
        assert!(rendered.contains("pair_request"));
        assert!(rendered.contains("msg-1"));
        for secret in [
            "base64-ciphertext",
            "pair-token-secret",
            "auth-signature-secret",
            "please leak this prompt",
            "assistant reply secret",
        ] {
            assert!(!rendered.contains(secret), "leaked {secret}");
        }
    }

    #[test]
    fn redacts_qr_uris_and_abbreviates_long_peer_keys() {
        assert_eq!(
            safe_log_string("remotepi://pair?t=secret&epk=peer"),
            "[redacted-uri]"
        );
        assert_eq!(
            safe_log_string("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=="),
            "ABCDEFGH…(66 chars)"
        );
        assert_eq!(short_id("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), "ABCDEFGH…");
    }

    #[test]
    fn safe_frame_type_only_allows_compact_identifiers() {
        assert_eq!(safe_frame_type("rooms_check"), "rooms_check");
        assert_eq!(
            safe_frame_type("pair-token-secret-with/slashes"),
            "[redacted-type]"
        );
    }
}
