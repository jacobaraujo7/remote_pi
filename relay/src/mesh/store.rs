use std::path::Path;
#[cfg(test)]
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Mutex, MutexGuard};

use rusqlite::{Connection, OptionalExtension, params};
use tracing::warn;

use super::types::MeshRecord;

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("sqlite: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("monotonic version violation: new={new} <= current={current}")]
    StaleVersion { new: u64, current: u64 },
}

const SCHEMA: &str = include_str!("../../migrations/001_mesh_versions.sql");

/// Mesh blob storage backed by SQLite. Single-table UPSERT keyed by
/// `owner_pk_hash`. Thread-safe via `std::sync::Mutex<Connection>`.
pub struct MeshStore {
    conn: Mutex<Connection>,
    #[cfg(test)]
    all_blobs_calls: AtomicUsize,
}

impl std::fmt::Debug for MeshStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("MeshStore").finish_non_exhaustive()
    }
}

impl MeshStore {
    fn connection(&self) -> MutexGuard<'_, Connection> {
        match self.conn.lock() {
            Ok(connection) => connection,
            Err(poisoned) => {
                warn!("mesh store mutex poisoned; recovering connection");
                let connection = poisoned.into_inner();
                self.conn.clear_poison();
                connection
            }
        }
    }

    /// Opens (or creates) the SQLite database at `path` and applies the
    /// schema migration idempotently. The parent directory is created if it
    /// doesn't exist — so callers can pass nested paths like `data/mesh.db`
    /// on first boot without pre-creating the folder.
    ///
    /// SQLite runs in the default (rollback-journal) mode — only `mesh.db`
    /// persists; a transient `mesh.db-journal` may appear briefly during a
    /// write transaction and is deleted on commit. WAL mode is NOT enabled.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, StoreError> {
        let path = path.as_ref();
        if let Some(parent) = path.parent()
            && !parent.as_os_str().is_empty()
        {
            std::fs::create_dir_all(parent)?;
        }
        let conn = Connection::open(path)?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self {
            conn: Mutex::new(conn),
            #[cfg(test)]
            all_blobs_calls: AtomicUsize::new(0),
        })
    }

    /// Opens an in-memory database (for tests).
    pub fn open_in_memory() -> Result<Self, StoreError> {
        let conn = Connection::open_in_memory()?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self {
            conn: Mutex::new(conn),
            #[cfg(test)]
            all_blobs_calls: AtomicUsize::new(0),
        })
    }

    /// Returns the current version for `owner_pk_hash`, or `None` if absent.
    pub fn current_version(&self, owner_pk_hash: &str) -> Result<Option<u64>, StoreError> {
        let conn = self.connection();
        let v: Option<i64> = conn
            .query_row(
                "SELECT version FROM mesh_versions WHERE owner_pk_hash = ?1",
                params![owner_pk_hash],
                |r| r.get(0),
            )
            .optional()?;
        Ok(v.map(|n| n as u64))
    }

    /// UPSERTs the row only if `new_version` is strictly greater than the
    /// current stored version. Returns `StoreError::StaleVersion` otherwise.
    /// All work runs inside a single transaction for atomicity.
    pub fn upsert(
        &self,
        owner_pk_hash: &str,
        owner_pk: &[u8],
        new_version: u64,
        blob: &[u8],
        sig: &[u8],
        updated_at_ms: i64,
    ) -> Result<(), StoreError> {
        let mut conn = self.connection();
        let tx = conn.transaction()?;
        let current: Option<i64> = tx
            .query_row(
                "SELECT version FROM mesh_versions WHERE owner_pk_hash = ?1",
                params![owner_pk_hash],
                |r| r.get(0),
            )
            .optional()?;
        if let Some(c) = current {
            let c = c as u64;
            if new_version <= c {
                return Err(StoreError::StaleVersion {
                    new: new_version,
                    current: c,
                });
            }
        }
        tx.execute(
            "INSERT INTO mesh_versions (owner_pk_hash, owner_pk, version, blob, sig, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT(owner_pk_hash) DO UPDATE SET
                 owner_pk   = excluded.owner_pk,
                 version    = excluded.version,
                 blob       = excluded.blob,
                 sig        = excluded.sig,
                 updated_at = excluded.updated_at",
            params![
                owner_pk_hash,
                owner_pk,
                new_version as i64,
                blob,
                sig,
                updated_at_ms,
            ],
        )?;
        tx.commit()?;
        Ok(())
    }

    /// Returns the raw `blob` bytes of every stored mesh version (one per
    /// Owner). Used by mesh authorization (plan 25) to find which Owner a
    /// given Pi-pubkey belongs to.
    pub fn all_blobs(&self) -> Result<Vec<Vec<u8>>, StoreError> {
        #[cfg(test)]
        self.all_blobs_calls.fetch_add(1, Ordering::Relaxed);
        let conn = self.connection();
        let mut stmt = conn.prepare("SELECT blob FROM mesh_versions")?;
        let rows: Result<Vec<Vec<u8>>, _> =
            stmt.query_map([], |r| r.get::<_, Vec<u8>>(0))?.collect();
        Ok(rows?)
    }

    #[cfg(test)]
    pub(crate) fn all_blobs_calls(&self) -> usize {
        self.all_blobs_calls.load(Ordering::Relaxed)
    }

    /// Fetches the current record for `owner_pk_hash`, or `None` if absent.
    pub fn get(&self, owner_pk_hash: &str) -> Result<Option<MeshRecord>, StoreError> {
        let conn = self.connection();
        let row = conn
            .query_row(
                "SELECT version, blob, sig, updated_at
                 FROM mesh_versions WHERE owner_pk_hash = ?1",
                params![owner_pk_hash],
                |r| {
                    Ok(MeshRecord {
                        version: r.get::<_, i64>(0)? as u64,
                        blob: r.get(1)?,
                        sig: r.get(2)?,
                        updated_at: r.get(3)?,
                    })
                },
            )
            .optional()?;
        Ok(row)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake_pk() -> Vec<u8> {
        vec![0u8; 32]
    }

    #[test]
    fn upsert_then_get_roundtrip() {
        let store = MeshStore::open_in_memory().unwrap();
        store
            .upsert("abc", &fake_pk(), 1, b"{\"version\":1}", &[0u8; 64], 100)
            .unwrap();
        let rec = store.get("abc").unwrap().unwrap();
        assert_eq!(rec.version, 1);
        assert_eq!(rec.updated_at, 100);
    }

    #[test]
    fn upsert_rejects_stale_version() {
        let store = MeshStore::open_in_memory().unwrap();
        store
            .upsert("abc", &fake_pk(), 5, b"v5", &[0u8; 64], 100)
            .unwrap();
        let err = store
            .upsert("abc", &fake_pk(), 5, b"v5", &[0u8; 64], 200)
            .unwrap_err();
        assert!(matches!(
            err,
            StoreError::StaleVersion { new: 5, current: 5 }
        ));
        let err = store
            .upsert("abc", &fake_pk(), 3, b"v3", &[0u8; 64], 200)
            .unwrap_err();
        assert!(matches!(
            err,
            StoreError::StaleVersion { new: 3, current: 5 }
        ));
        // current still 5
        assert_eq!(store.current_version("abc").unwrap(), Some(5));
    }

    #[test]
    fn upsert_advances_version() {
        let store = MeshStore::open_in_memory().unwrap();
        store
            .upsert("abc", &fake_pk(), 1, b"v1", &[0u8; 64], 100)
            .unwrap();
        store
            .upsert("abc", &fake_pk(), 2, b"v2", &[0u8; 64], 200)
            .unwrap();
        let rec = store.get("abc").unwrap().unwrap();
        assert_eq!(rec.version, 2);
        assert_eq!(rec.blob, b"v2");
        assert_eq!(rec.updated_at, 200);
    }

    #[test]
    fn get_missing_returns_none() {
        let store = MeshStore::open_in_memory().unwrap();
        assert!(store.get("nope").unwrap().is_none());
        assert_eq!(store.current_version("nope").unwrap(), None);
    }

    #[test]
    fn poisoned_connection_recovers_without_panicking() {
        let store = std::sync::Arc::new(MeshStore::open_in_memory().unwrap());
        let poisoned_store = store.clone();
        assert!(
            std::thread::spawn(move || {
                let _connection = poisoned_store.conn.lock().unwrap();
                panic!("poison connection");
            })
            .join()
            .is_err()
        );
        assert_eq!(store.current_version("missing").unwrap(), None);
        assert!(!store.conn.is_poisoned());
        // Subsequent access uses the retained connection without re-entering
        // the poison-recovery branch.
        assert_eq!(store.current_version("missing").unwrap(), None);
        assert!(!store.conn.is_poisoned());
    }
}
