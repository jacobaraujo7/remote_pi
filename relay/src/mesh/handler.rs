use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::{
    Json,
    extract::{Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
};
use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use tracing::warn;

use super::store::{MeshStore, StoreError};
use super::types::{GetQuery, GetResponse, MeshEnvelopeWire, PostResponse};
use super::verify::{VerifyError, decode_wire, owner_pk_hash, verify_envelope};

/// 500 KB cap on `POST /mesh/:hash` bodies (decision Q4 of plan 24).
pub const MAX_BODY_BYTES: usize = 500 * 1024;

/// Error variants surfaced to clients. Each maps to a specific HTTP status.
#[derive(Debug)]
pub enum MeshHttpError {
    BadRequest(String),
    Forbidden(String),
    NotFound,
    Conflict { current_version: u64 },
    PayloadTooLarge,
    Internal(String),
}

impl IntoResponse for MeshHttpError {
    fn into_response(self) -> Response {
        let (status, body) = match self {
            MeshHttpError::BadRequest(m) => (StatusCode::BAD_REQUEST, m),
            MeshHttpError::Forbidden(m) => (StatusCode::FORBIDDEN, m),
            MeshHttpError::NotFound => (StatusCode::NOT_FOUND, "not_found".into()),
            MeshHttpError::Conflict { current_version } => (
                StatusCode::CONFLICT,
                format!("stale_version (current={current_version})"),
            ),
            MeshHttpError::PayloadTooLarge => {
                (StatusCode::PAYLOAD_TOO_LARGE, "payload_too_large".into())
            }
            MeshHttpError::Internal(m) => {
                warn!("mesh internal error: {m}");
                (StatusCode::INTERNAL_SERVER_ERROR, "internal".into())
            }
        };
        (status, body).into_response()
    }
}

pub async fn post_mesh(
    State(store): State<Arc<MeshStore>>,
    Path(url_hash): Path<String>,
    body: axum::body::Bytes,
) -> Result<(StatusCode, Json<PostResponse>), MeshHttpError> {
    if body.len() > MAX_BODY_BYTES {
        return Err(MeshHttpError::PayloadTooLarge);
    }

    let wire: MeshEnvelopeWire = serde_json::from_slice(&body)
        .map_err(|e| MeshHttpError::BadRequest(format!("invalid json: {e}")))?;
    let env = decode_wire(&wire).map_err(|e| MeshHttpError::BadRequest(format!("decode: {e}")))?;

    let verified = verify_envelope(&env).map_err(|e| match e {
        VerifyError::SigFailed => MeshHttpError::Forbidden("sig_invalid".into()),
        VerifyError::BadOwnerPk | VerifyError::BadSigLength => {
            MeshHttpError::Forbidden(e.to_string())
        }
        other => MeshHttpError::BadRequest(other.to_string()),
    })?;

    // Confirm the URL hash matches the Owner bytes verified with the signature.
    let computed_hash = owner_pk_hash(&verified.owner_pk);
    if computed_hash != url_hash.to_lowercase() {
        return Err(MeshHttpError::Forbidden("owner_pk_hash mismatch".into()));
    }

    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;

    match store.upsert(
        &computed_hash,
        &verified.owner_pk,
        verified.header.version,
        &env.blob,
        &env.sig,
        now_ms,
    ) {
        Ok(()) => Ok((
            StatusCode::OK,
            Json(PostResponse {
                version: verified.header.version,
                updated_at: now_ms,
            }),
        )),
        Err(StoreError::StaleVersion { current, .. }) => Err(MeshHttpError::Conflict {
            current_version: current,
        }),
        Err(e) => Err(MeshHttpError::Internal(e.to_string())),
    }
}

pub async fn get_mesh(
    State(store): State<Arc<MeshStore>>,
    Path(url_hash): Path<String>,
    Query(q): Query<GetQuery>,
) -> Result<Response, MeshHttpError> {
    let hash = url_hash.to_lowercase();
    let rec = match store.get(&hash) {
        Ok(Some(r)) => r,
        Ok(None) => return Err(MeshHttpError::NotFound),
        Err(e) => return Err(MeshHttpError::Internal(e.to_string())),
    };

    if let Some(since) = q.since
        && rec.version <= since
    {
        return Ok(StatusCode::NOT_MODIFIED.into_response());
    }

    let body = GetResponse {
        blob: B64.encode(&rec.blob),
        sig: B64.encode(&rec.sig),
        version: rec.version,
        updated_at: rec.updated_at,
    };
    Ok((StatusCode::OK, Json(body)).into_response())
}
