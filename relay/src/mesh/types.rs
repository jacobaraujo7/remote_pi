use serde::{Deserialize, Serialize};

/// Wire format that clients POST and that the relay returns on GET.
/// `blob` and `sig` are base64 STANDARD strings on the wire.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeshEnvelopeWire {
    pub blob: String,
    pub sig: String,
}

/// Decoded envelope after base64-decoding the wire fields.
/// The `blob` bytes are the canonical-JSON payload that was signed;
/// the relay never re-canonicalizes — it only verifies the bytes received.
#[derive(Debug, Clone)]
pub struct MeshEnvelope {
    pub blob: Vec<u8>,
    pub sig: Vec<u8>,
}

/// Full member boundary extracted from a signed Owner blob. Fields beyond
/// `remote_epk` are deserialized even though routing does not consume them so
/// one malformed member invalidates the whole contribution.
#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub(crate) struct MeshMemberHeader {
    pub(crate) remote_epk: String,
    pub(crate) relay_url: String,
    pub(crate) paired_at: String,
    pub(crate) nickname: Option<String>,
}

/// Required header extracted from the untouched signed `blob` JSON.
#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub(crate) struct MeshHeader {
    pub(crate) version: u64,
    pub(crate) owner_pk: String,
    pub(crate) issued_at: u64,
    pub(crate) members: Vec<MeshMemberHeader>,
}

/// Stored row returned by `MeshStore::get`.
#[derive(Debug, Clone)]
pub struct MeshRecord {
    pub version: u64,
    pub blob: Vec<u8>,
    pub sig: Vec<u8>,
    pub updated_at: i64,
}

/// JSON body returned on `POST /mesh/:hash` success.
#[derive(Debug, Serialize)]
pub struct PostResponse {
    pub version: u64,
    pub updated_at: i64,
}

/// JSON body returned on `GET /mesh/:hash` success.
#[derive(Debug, Serialize)]
pub struct GetResponse {
    pub blob: String, // base64
    pub sig: String,  // base64
    pub version: u64,
    pub updated_at: i64,
}

#[derive(Debug, Deserialize)]
pub struct GetQuery {
    pub since: Option<u64>,
}
