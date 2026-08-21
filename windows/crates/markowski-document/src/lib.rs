//! Platform-neutral document lifecycle and revision safety.
//!
//! The crate deliberately knows nothing about Tauri, Windows handles, or a
//! concrete filesystem.  A platform adapter supplies stable reads and
//! compare-before-write atomic writes through [`DocumentFileSystem`].

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fmt;
use std::path::{Path, PathBuf};
use thiserror::Error;

const DEFAULT_NEWLINE: NewlineStyle = NewlineStyle::CrLf;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Error)]
#[serde(tag = "code", rename_all = "snake_case")]
pub enum DocumentError {
    #[error("Choose a Markdown (.md) or Mermaid (.mmd) file.")]
    UnsupportedExtension { extension: String },
    #[error("The selected document path is invalid.")]
    InvalidPath,
    #[error("The document does not exist.")]
    FileMissing,
    #[error("The document could not be read.")]
    ReadFailed,
    #[error("The document is not valid UTF-8.")]
    UnsupportedEncoding,
    #[error("The file changed outside Markowski; your changes were not overwritten.")]
    DiskConflict,
    #[error("The open file was deleted outside Markowski; use Save As to recover your changes.")]
    ExternallyDeleted,
    #[error(
        "The open file was renamed or moved outside Markowski; use Save As to choose a safe path."
    )]
    ExternallyRenamed,
    #[error("The document could not be written safely.")]
    WriteFailed,
    #[error("Markowski could not atomically replace the document.")]
    AtomicReplaceFailed,
    #[error("A file already exists at the selected Save As path.")]
    TargetExists,
    #[error("The Save As target changed before it could be written.")]
    TargetChanged,
    #[error("The document is in a conflict state; reload or use Save As before saving.")]
    ConflictActive,
    #[error("There is no saved path for this document; use Save As.")]
    UntitledSave,
    #[error("A document save is already in progress.")]
    SaveInProgress,
    #[error("The document has unsaved changes; confirm discard before switching documents.")]
    UnsavedChanges,
    #[error("The requested document action was cancelled.")]
    DialogCancelled,
    #[error("File watching is unavailable; Markowski will still check the file before saving.")]
    WatcherFailed,
    #[error("The document could not be reloaded because the file is unavailable.")]
    ReloadFailed,
    #[error("The file could not be written because access was denied.")]
    PermissionDenied,
    #[error("The file changed while Markowski was reading it.")]
    ReadRace,
}

impl DocumentError {
    pub const fn code(&self) -> &'static str {
        match self {
            Self::UnsupportedExtension { .. } => "unsupported_extension",
            Self::InvalidPath => "invalid_path",
            Self::FileMissing => "file_missing",
            Self::ReadFailed => "read_failed",
            Self::UnsupportedEncoding => "unsupported_encoding",
            Self::DiskConflict => "disk_conflict",
            Self::ExternallyDeleted => "externally_deleted",
            Self::ExternallyRenamed => "externally_renamed",
            Self::WriteFailed => "write_failed",
            Self::AtomicReplaceFailed => "atomic_replace_failed",
            Self::TargetExists => "target_exists",
            Self::TargetChanged => "target_changed",
            Self::ConflictActive => "conflict_active",
            Self::UntitledSave => "untitled_save",
            Self::SaveInProgress => "save_in_progress",
            Self::UnsavedChanges => "unsaved_changes",
            Self::DialogCancelled => "dialog_cancelled",
            Self::WatcherFailed => "watcher_failed",
            Self::ReloadFailed => "reload_failed",
            Self::PermissionDenied => "permission_denied",
            Self::ReadRace => "read_race",
        }
    }

    pub fn user_message(&self) -> String {
        self.to_string()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentPath(PathBuf);

impl DocumentPath {
    pub fn new(path: impl Into<PathBuf>) -> Result<Self, DocumentError> {
        let path = path.into();
        if path.as_os_str().is_empty() || !path.is_absolute() {
            return Err(DocumentError::InvalidPath);
        }

        let extension = path
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or_default();
        if !is_supported_extension(extension) {
            return Err(DocumentError::UnsupportedExtension {
                extension: extension.to_owned(),
            });
        }

        Ok(Self(path))
    }

    pub fn as_path(&self) -> &Path {
        &self.0
    }

    pub fn into_path_buf(self) -> PathBuf {
        self.0
    }

    pub fn file_name(&self) -> String {
        self.0
            .file_name()
            .map(|value| value.to_string_lossy().into_owned())
            .unwrap_or_else(|| "Untitled".to_owned())
    }

    pub fn extension(&self) -> String {
        self.0
            .extension()
            .map(|value| value.to_string_lossy().to_ascii_lowercase())
            .unwrap_or_default()
    }

    pub fn display_path(&self) -> String {
        self.0.to_string_lossy().into_owned()
    }
}

impl fmt::Display for DocumentPath {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.display().fmt(formatter)
    }
}

pub fn is_supported_extension(extension: &str) -> bool {
    extension.eq_ignore_ascii_case("md") || extension.eq_ignore_ascii_case("mmd")
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DocumentEncoding {
    Utf8,
    Utf8Bom,
}

impl DocumentEncoding {
    pub const fn label(self) -> &'static str {
        match self {
            Self::Utf8 => "UTF-8",
            Self::Utf8Bom => "UTF-8 BOM",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NewlineStyle {
    None,
    Lf,
    CrLf,
    Mixed,
}

impl NewlineStyle {
    pub const fn label(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::Lf => "LF",
            Self::CrLf => "CRLF",
            Self::Mixed => "mixed",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentContent {
    text: String,
    encoding: DocumentEncoding,
    newline_style: NewlineStyle,
}

impl DocumentContent {
    pub fn new() -> Self {
        Self {
            text: String::new(),
            encoding: DocumentEncoding::Utf8,
            newline_style: DEFAULT_NEWLINE,
        }
    }

    pub fn from_disk_bytes(bytes: &[u8]) -> Result<Self, DocumentError> {
        let (encoding, source) = if let Some(source) = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]) {
            (DocumentEncoding::Utf8Bom, source)
        } else {
            (DocumentEncoding::Utf8, bytes)
        };

        let source = std::str::from_utf8(source).map_err(|_| DocumentError::UnsupportedEncoding)?;
        let newline_style = detect_newline_style(source);

        Ok(Self {
            text: normalize_newlines(source),
            encoding,
            newline_style,
        })
    }

    pub fn text(&self) -> &str {
        &self.text
    }

    pub fn encoding(&self) -> DocumentEncoding {
        self.encoding
    }

    pub fn newline_style(&self) -> NewlineStyle {
        self.newline_style
    }

    pub fn set_text(&mut self, text: impl Into<String>) -> bool {
        let text = normalize_newlines(&text.into());
        if self.text == text {
            return false;
        }
        self.text = text;
        true
    }

    pub fn encoded_bytes(&self) -> Vec<u8> {
        encode_text(&self.text, self.encoding, self.newline_style)
    }

    pub fn memory_hash(&self) -> String {
        sha256_text(&self.text)
    }
}

impl Default for DocumentContent {
    fn default() -> Self {
        Self::new()
    }
}

fn normalize_newlines(text: &str) -> String {
    text.replace("\r\n", "\n").replace('\r', "\n")
}

fn detect_newline_style(text: &str) -> NewlineStyle {
    let crlf_count = text.matches("\r\n").count();
    let without_crlf = text.replace("\r\n", "");
    let lf_count = without_crlf.matches('\n').count();
    let lone_cr_count = without_crlf.matches('\r').count();

    if (crlf_count > 0 && lf_count > 0) || lone_cr_count > 0 {
        NewlineStyle::Mixed
    } else if crlf_count > 0 {
        NewlineStyle::CrLf
    } else if lf_count > 0 {
        NewlineStyle::Lf
    } else {
        NewlineStyle::None
    }
}

fn encode_text(text: &str, encoding: DocumentEncoding, newline_style: NewlineStyle) -> Vec<u8> {
    let normalized = normalize_newlines(text);
    let separator = match newline_style {
        NewlineStyle::CrLf => "\r\n",
        NewlineStyle::None | NewlineStyle::Lf | NewlineStyle::Mixed => "\n",
    };
    let mut output = if separator == "\n" {
        normalized.into_bytes()
    } else {
        normalized.replace('\n', separator).into_bytes()
    };

    if matches!(encoding, DocumentEncoding::Utf8Bom) {
        let mut with_bom = Vec::with_capacity(output.len() + 3);
        with_bom.extend_from_slice(&[0xEF, 0xBB, 0xBF]);
        with_bom.append(&mut output);
        with_bom
    } else {
        output
    }
}

pub fn sha256_bytes(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

pub fn sha256_text(text: &str) -> String {
    sha256_bytes(text.as_bytes())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileFingerprint {
    pub byte_len: u64,
    pub modified_nanos: Option<u128>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiskRead {
    pub bytes: Vec<u8>,
    pub fingerprint: FileFingerprint,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiskSnapshot {
    pub path: DocumentPath,
    pub fingerprint: FileFingerprint,
    pub content_hash: String,
    pub encoding: DocumentEncoding,
    pub newline_style: NewlineStyle,
}

pub fn snapshot_from_read(
    path: DocumentPath,
    read: DiskRead,
) -> Result<(DocumentContent, DiskSnapshot), DocumentError> {
    let content = DocumentContent::from_disk_bytes(&read.bytes)?;
    let snapshot = DiskSnapshot {
        path,
        fingerprint: read.fingerprint,
        content_hash: sha256_bytes(&read.bytes),
        encoding: content.encoding(),
        newline_style: content.newline_style(),
    };
    Ok((content, snapshot))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DocumentStatus {
    Untitled,
    Saved,
    Dirty,
    Saving,
    ExternalChanged,
    Conflict,
    Missing,
    ExternallyRenamed,
    SaveError,
}

impl DocumentStatus {
    pub const fn label(self) -> &'static str {
        match self {
            Self::Untitled => "Untitled",
            Self::Saved => "Saved",
            Self::Dirty => "Unsaved",
            Self::Saving => "Saving",
            Self::ExternalChanged => "External change",
            Self::Conflict => "Conflict",
            Self::Missing => "Deleted/missing",
            Self::ExternallyRenamed => "Externally renamed",
            Self::SaveError => "Save error",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExternalChangeKind {
    Changed,
    Removed,
    Renamed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DocumentState {
    pub status: DocumentStatus,
    pub dirty: bool,
    pub file_name: String,
    pub file_extension: Option<String>,
    pub path: Option<String>,
    pub content: Option<String>,
    pub memory_generation: u64,
    pub memory_hash: String,
    pub persisted_hash: Option<String>,
    pub disk_hash: Option<String>,
    pub encoding: DocumentEncoding,
    pub newline_style: NewlineStyle,
    pub message: Option<String>,
}

impl DocumentState {
    pub fn untitled() -> Self {
        DocumentSession::new().state(true)
    }
}

#[derive(Debug, Clone)]
pub struct SaveAttempt {
    pub target: DocumentPath,
    pub bytes: Vec<u8>,
    pub memory_generation: u64,
    pub memory_hash: String,
    pub expected_disk: Option<DiskSnapshot>,
    previous_status: DocumentStatus,
}

#[derive(Debug, Clone)]
pub struct DocumentSession {
    path: Option<DocumentPath>,
    content: DocumentContent,
    memory_generation: u64,
    persisted_memory_hash: String,
    persisted_disk: Option<DiskSnapshot>,
    current_disk: Option<DiskSnapshot>,
    status: DocumentStatus,
    last_error: Option<DocumentError>,
}

impl DocumentSession {
    pub fn new() -> Self {
        let content = DocumentContent::new();
        Self {
            persisted_memory_hash: content.memory_hash(),
            content,
            path: None,
            memory_generation: 0,
            persisted_disk: None,
            current_disk: None,
            status: DocumentStatus::Untitled,
            last_error: None,
        }
    }

    pub fn from_disk(path: DocumentPath, content: DocumentContent, snapshot: DiskSnapshot) -> Self {
        Self {
            persisted_memory_hash: content.memory_hash(),
            content,
            path: Some(path),
            memory_generation: 0,
            persisted_disk: Some(snapshot.clone()),
            current_disk: Some(snapshot),
            status: DocumentStatus::Saved,
            last_error: None,
        }
    }

    pub fn content(&self) -> &str {
        self.content.text()
    }

    pub fn path(&self) -> Option<&DocumentPath> {
        self.path.as_ref()
    }

    pub fn status(&self) -> DocumentStatus {
        self.status
    }

    pub fn is_dirty(&self) -> bool {
        self.content.memory_hash() != self.persisted_memory_hash
    }

    pub fn update_content(&mut self, text: impl Into<String>) {
        if !self.content.set_text(text) {
            return;
        }
        self.memory_generation = self.memory_generation.saturating_add(1);
        self.last_error = None;

        self.status = match self.status {
            DocumentStatus::Conflict | DocumentStatus::ExternallyRenamed => self.status,
            DocumentStatus::Missing => DocumentStatus::Missing,
            DocumentStatus::Saving => DocumentStatus::Saving,
            _ if self.path.is_none() => DocumentStatus::Untitled,
            _ if self.is_dirty() => DocumentStatus::Dirty,
            _ => DocumentStatus::Saved,
        };
    }

    pub fn begin_save(&mut self) -> Result<SaveAttempt, DocumentError> {
        let target = self.path.clone().ok_or(DocumentError::UntitledSave)?;
        if self.status == DocumentStatus::Saving {
            return Err(DocumentError::SaveInProgress);
        }
        match self.status {
            DocumentStatus::Conflict => return Err(DocumentError::ConflictActive),
            DocumentStatus::ExternalChanged => return Err(DocumentError::DiskConflict),
            DocumentStatus::Missing => return Err(DocumentError::ExternallyDeleted),
            DocumentStatus::ExternallyRenamed => return Err(DocumentError::ExternallyRenamed),
            _ => {}
        }

        self.begin_attempt(target, self.persisted_disk.clone())
    }

    pub fn begin_save_as(
        &mut self,
        target: DocumentPath,
        overwrite_confirmed: bool,
    ) -> Result<SaveAttempt, DocumentError> {
        if self.status == DocumentStatus::Saving {
            return Err(DocumentError::SaveInProgress);
        }
        if !overwrite_confirmed && self.path.as_ref() == Some(&target) {
            return Err(DocumentError::TargetExists);
        }

        let expected_disk = if self.path.as_ref() == Some(&target) {
            self.persisted_disk.clone()
        } else {
            None
        };
        self.begin_attempt(target, expected_disk)
    }

    fn begin_attempt(
        &mut self,
        target: DocumentPath,
        expected_disk: Option<DiskSnapshot>,
    ) -> Result<SaveAttempt, DocumentError> {
        let previous_status = self.status;
        self.status = DocumentStatus::Saving;
        self.last_error = None;
        Ok(SaveAttempt {
            target,
            bytes: self.content.encoded_bytes(),
            memory_generation: self.memory_generation,
            memory_hash: self.content.memory_hash(),
            expected_disk,
            previous_status,
        })
    }

    pub fn complete_save(&mut self, attempt: SaveAttempt, snapshot: DiskSnapshot) {
        self.path = Some(attempt.target);
        self.persisted_memory_hash = attempt.memory_hash;
        self.persisted_disk = Some(snapshot.clone());
        self.current_disk = Some(snapshot.clone());
        self.content.encoding = snapshot.encoding;
        self.content.newline_style = snapshot.newline_style;
        self.last_error = None;
        self.status = if self.is_dirty() {
            DocumentStatus::Dirty
        } else {
            DocumentStatus::Saved
        };
    }

    pub fn fail_save(&mut self, attempt: &SaveAttempt, error: DocumentError) {
        self.status = match error {
            DocumentError::DiskConflict
            | DocumentError::TargetChanged
            | DocumentError::ConflictActive => DocumentStatus::Conflict,
            DocumentError::ExternallyDeleted | DocumentError::FileMissing => {
                DocumentStatus::Missing
            }
            DocumentError::ExternallyRenamed => DocumentStatus::ExternallyRenamed,
            _ => match attempt.previous_status {
                DocumentStatus::Conflict => DocumentStatus::Conflict,
                DocumentStatus::ExternalChanged => DocumentStatus::ExternalChanged,
                DocumentStatus::Missing => DocumentStatus::Missing,
                DocumentStatus::ExternallyRenamed => DocumentStatus::ExternallyRenamed,
                DocumentStatus::Untitled if self.path.is_none() => DocumentStatus::Untitled,
                _ => DocumentStatus::SaveError,
            },
        };
        self.last_error = Some(error);
    }

    pub fn reload(&mut self, content: DocumentContent, snapshot: DiskSnapshot) {
        self.content = content;
        self.memory_generation = self.memory_generation.saturating_add(1);
        self.persisted_memory_hash = self.content.memory_hash();
        self.persisted_disk = Some(snapshot.clone());
        self.current_disk = Some(snapshot);
        self.last_error = None;
        self.status = DocumentStatus::Saved;
    }

    pub fn reconcile_snapshot(&mut self, snapshot: DiskSnapshot) {
        if self.status == DocumentStatus::Saving {
            return;
        }

        let unchanged = self
            .persisted_disk
            .as_ref()
            .is_some_and(|expected| expected.content_hash == snapshot.content_hash);
        self.current_disk = Some(snapshot);
        self.last_error = None;
        self.status = if unchanged {
            if self.is_dirty() {
                DocumentStatus::Dirty
            } else {
                DocumentStatus::Saved
            }
        } else if self.is_dirty() {
            DocumentStatus::Conflict
        } else {
            DocumentStatus::ExternalChanged
        };
    }

    pub fn reconcile_missing(&mut self, renamed: bool) {
        if self.status == DocumentStatus::Saving {
            return;
        }
        self.current_disk = None;
        let error = if renamed {
            DocumentError::ExternallyRenamed
        } else {
            DocumentError::ExternallyDeleted
        };
        self.status = if renamed {
            DocumentStatus::ExternallyRenamed
        } else {
            DocumentStatus::Missing
        };
        self.last_error = Some(error);
    }

    pub fn reconcile_error(&mut self, error: DocumentError) {
        if self.status == DocumentStatus::Saving {
            return;
        }
        self.status = DocumentStatus::Conflict;
        self.last_error = Some(error);
    }

    pub fn state(&self, include_content: bool) -> DocumentState {
        let (file_name, file_extension, path) = match &self.path {
            Some(path) => (
                path.file_name(),
                Some(path.extension()),
                Some(path.display_path()),
            ),
            None => ("Untitled".to_owned(), None, None),
        };
        DocumentState {
            status: self.status,
            dirty: self.is_dirty(),
            file_name,
            file_extension,
            path,
            content: include_content.then(|| self.content.text().to_owned()),
            memory_generation: self.memory_generation,
            memory_hash: self.content.memory_hash(),
            persisted_hash: self
                .persisted_disk
                .as_ref()
                .map(|snapshot| snapshot.content_hash.clone()),
            disk_hash: self
                .current_disk
                .as_ref()
                .map(|snapshot| snapshot.content_hash.clone()),
            encoding: self.content.encoding(),
            newline_style: self.content.newline_style(),
            message: self.last_error.as_ref().map(DocumentError::user_message),
        }
    }
}

impl Default for DocumentSession {
    fn default() -> Self {
        Self::new()
    }
}

pub trait DocumentFileSystem: Send + Sync + 'static {
    fn read_document(&self, path: &DocumentPath) -> Result<DiskRead, DocumentError>;

    fn write_atomic(
        &self,
        path: &DocumentPath,
        bytes: &[u8],
        expected: Option<&DiskSnapshot>,
        overwrite_confirmed: bool,
    ) -> Result<DiskRead, DocumentError>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExternalChangeSignal {
    Changed,
    Removed,
    Renamed,
}

pub struct DocumentCoordinator<F> {
    filesystem: F,
    session: DocumentSession,
}

impl<F: DocumentFileSystem> DocumentCoordinator<F> {
    pub fn new(filesystem: F) -> Self {
        Self {
            filesystem,
            session: DocumentSession::new(),
        }
    }

    pub fn new_document(&mut self) {
        self.session = DocumentSession::new();
    }

    pub fn open(&mut self, path: DocumentPath) -> Result<(), DocumentError> {
        let read = self.filesystem.read_document(&path)?;
        let (content, snapshot) = snapshot_from_read(path.clone(), read)?;
        self.session = DocumentSession::from_disk(path, content, snapshot);
        Ok(())
    }

    pub fn update_content(&mut self, text: impl Into<String>) {
        self.session.update_content(text);
    }

    pub fn state(&self, include_content: bool) -> DocumentState {
        self.session.state(include_content)
    }

    pub fn path(&self) -> Option<DocumentPath> {
        self.session.path().cloned()
    }

    pub fn save(&mut self) -> Result<DocumentState, DocumentError> {
        if self.session.status() == DocumentStatus::Saved && !self.session.is_dirty() {
            return Ok(self.session.state(false));
        }
        let attempt = self.session.begin_save()?;
        self.finish_save(attempt, true)
    }

    pub fn save_as(
        &mut self,
        path: DocumentPath,
        overwrite_confirmed: bool,
    ) -> Result<DocumentState, DocumentError> {
        let attempt = self.session.begin_save_as(path, overwrite_confirmed)?;
        self.finish_save(attempt, overwrite_confirmed)
    }

    fn finish_save(
        &mut self,
        attempt: SaveAttempt,
        overwrite_confirmed: bool,
    ) -> Result<DocumentState, DocumentError> {
        let result = self.filesystem.write_atomic(
            &attempt.target,
            &attempt.bytes,
            attempt.expected_disk.as_ref(),
            overwrite_confirmed,
        );
        match result {
            Ok(read) => match snapshot_from_read(attempt.target.clone(), read) {
                Ok((_, snapshot)) => {
                    self.session.complete_save(attempt, snapshot);
                    Ok(self.session.state(false))
                }
                Err(error) => {
                    self.session.fail_save(&attempt, error.clone());
                    Err(error)
                }
            },
            Err(error) => {
                self.session.fail_save(&attempt, error.clone());
                Err(error)
            }
        }
    }

    pub fn reload(&mut self) -> Result<DocumentState, DocumentError> {
        let path = self
            .session
            .path()
            .cloned()
            .ok_or(DocumentError::ReloadFailed)?;
        let read = self
            .filesystem
            .read_document(&path)
            .map_err(|error| match error {
                DocumentError::FileMissing => DocumentError::ExternallyDeleted,
                _ => DocumentError::ReloadFailed,
            })?;
        let (content, snapshot) = snapshot_from_read(path, read)?;
        self.session.reload(content, snapshot);
        Ok(self.session.state(true))
    }

    pub fn reconcile(&mut self, signal: ExternalChangeSignal) -> DocumentState {
        if self.session.path().is_none() {
            return self.session.state(false);
        }

        let path = self.session.path().cloned().expect("path checked above");
        match self.filesystem.read_document(&path) {
            Ok(read) => match snapshot_from_read(path, read) {
                Ok((_, snapshot)) => self.session.reconcile_snapshot(snapshot),
                Err(error) => self.session.reconcile_error(error),
            },
            Err(DocumentError::FileMissing) => {
                self.session
                    .reconcile_missing(matches!(signal, ExternalChangeSignal::Renamed));
            }
            Err(error) => self.session.reconcile_error(error),
        }
        self.session.state(false)
    }
}

impl<F: DocumentFileSystem> fmt::Debug for DocumentCoordinator<F>
where
    F: fmt::Debug,
{
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DocumentCoordinator")
            .field("filesystem", &self.filesystem)
            .field("session", &self.session)
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[derive(Debug, Clone, Default)]
    struct FakeFileSystem {
        bytes: Arc<Mutex<Option<Vec<u8>>>>,
    }

    impl DocumentFileSystem for FakeFileSystem {
        fn read_document(&self, _path: &DocumentPath) -> Result<DiskRead, DocumentError> {
            let bytes = self
                .bytes
                .lock()
                .expect("fake filesystem lock")
                .clone()
                .ok_or(DocumentError::FileMissing)?;
            Ok(DiskRead {
                fingerprint: FileFingerprint {
                    byte_len: bytes.len() as u64,
                    modified_nanos: None,
                },
                bytes,
            })
        }

        fn write_atomic(
            &self,
            _path: &DocumentPath,
            bytes: &[u8],
            expected: Option<&DiskSnapshot>,
            overwrite_confirmed: bool,
        ) -> Result<DiskRead, DocumentError> {
            let mut current = self.bytes.lock().expect("fake filesystem lock");
            if let Some(expected) = expected {
                let current_bytes = current.clone().ok_or(DocumentError::FileMissing)?;
                if sha256_bytes(&current_bytes) != expected.content_hash {
                    return Err(DocumentError::DiskConflict);
                }
            } else if current.is_some() && !overwrite_confirmed {
                return Err(DocumentError::TargetExists);
            }
            *current = Some(bytes.to_vec());
            Ok(DiskRead {
                fingerprint: FileFingerprint {
                    byte_len: bytes.len() as u64,
                    modified_nanos: None,
                },
                bytes: bytes.to_vec(),
            })
        }
    }

    fn path(name: &str) -> DocumentPath {
        DocumentPath::new(PathBuf::from(format!("C:\\markowski-tests\\{name}.md")))
            .expect("test path")
    }

    fn opened_session(text: &str) -> (DocumentSession, DiskSnapshot) {
        let path = path("opened");
        let bytes = text.as_bytes().to_vec();
        let (content, snapshot) = snapshot_from_read(
            path.clone(),
            DiskRead {
                fingerprint: FileFingerprint {
                    byte_len: bytes.len() as u64,
                    modified_nanos: None,
                },
                bytes,
            },
        )
        .expect("snapshot");
        (
            DocumentSession::from_disk(path, content, snapshot.clone()),
            snapshot,
        )
    }

    #[test]
    fn new_document_is_untitled_and_clean_until_edited() {
        let mut session = DocumentSession::new();
        assert_eq!(session.status(), DocumentStatus::Untitled);
        assert!(!session.is_dirty());

        session.update_content("# Hello");
        assert_eq!(session.status(), DocumentStatus::Untitled);
        assert!(session.is_dirty());
    }

    #[test]
    fn extensions_are_case_insensitive_but_binary_paths_are_rejected() {
        assert!(DocumentPath::new(PathBuf::from("C:\\notes\\FLOW.MMD")).is_ok());
        assert!(DocumentPath::new(PathBuf::from("C:\\notes\\README.MD")).is_ok());
        assert!(matches!(
            DocumentPath::new(PathBuf::from("C:\\notes\\archive.txt")),
            Err(DocumentError::UnsupportedExtension { .. })
        ));
    }

    #[test]
    fn utf8_bom_and_newlines_are_detected_and_preserved_on_encode() {
        let content = DocumentContent::from_disk_bytes(b"\xEF\xBB\xBFone\r\ntwo\r\n")
            .expect("valid UTF-8 BOM");
        assert_eq!(content.encoding(), DocumentEncoding::Utf8Bom);
        assert_eq!(content.newline_style(), NewlineStyle::CrLf);
        assert_eq!(content.text(), "one\ntwo\n");
        assert_eq!(content.encoded_bytes(), b"\xEF\xBB\xBFone\r\ntwo\r\n");
    }

    #[test]
    fn mixed_newlines_are_deterministically_normalized_after_edit() {
        let mut content =
            DocumentContent::from_disk_bytes(b"one\r\ntwo\nthree").expect("valid mixed document");
        assert_eq!(content.newline_style(), NewlineStyle::Mixed);
        content.set_text("one\ntwo\nthree\nfour");
        assert_eq!(content.encoded_bytes(), b"one\ntwo\nthree\nfour");
    }

    #[test]
    fn edit_during_save_keeps_newer_memory_revision_dirty() {
        let (mut session, snapshot) = opened_session("A");
        session.update_content("B");
        let attempt = session.begin_save().expect("save begins");
        session.update_content("C");
        session.complete_save(attempt, snapshot);

        assert_eq!(session.content(), "C");
        assert!(session.is_dirty());
        assert_eq!(session.status(), DocumentStatus::Dirty);
    }

    #[test]
    fn external_change_is_conflict_for_dirty_memory_and_blocks_save() {
        let (mut session, _) = opened_session("A");
        session.update_content("local B");
        let path = session.path().cloned().expect("path");
        let external_bytes = b"external C".to_vec();
        let (_, external_snapshot) = snapshot_from_read(
            path,
            DiskRead {
                fingerprint: FileFingerprint {
                    byte_len: external_bytes.len() as u64,
                    modified_nanos: Some(2),
                },
                bytes: external_bytes,
            },
        )
        .expect("external snapshot");
        session.reconcile_snapshot(external_snapshot);

        assert_eq!(session.status(), DocumentStatus::Conflict);
        assert!(matches!(
            session.begin_save(),
            Err(DocumentError::ConflictActive)
        ));
    }

    #[test]
    fn clean_external_change_can_reload_without_losing_memory() {
        let (mut session, _) = opened_session("A");
        let path = session.path().cloned().expect("path");
        let external_bytes = b"external B".to_vec();
        let (external_content, external_snapshot) = snapshot_from_read(
            path,
            DiskRead {
                fingerprint: FileFingerprint {
                    byte_len: external_bytes.len() as u64,
                    modified_nanos: Some(2),
                },
                bytes: external_bytes,
            },
        )
        .expect("external snapshot");
        session.reconcile_snapshot(external_snapshot.clone());
        assert_eq!(session.status(), DocumentStatus::ExternalChanged);
        session.reload(external_content, external_snapshot);
        assert_eq!(session.content(), "external B");
        assert_eq!(session.status(), DocumentStatus::Saved);
        assert!(!session.is_dirty());
    }

    #[test]
    fn external_delete_keeps_memory_and_requires_save_as() {
        let (mut session, _) = opened_session("keep me");
        session.update_content("keep my edit");
        session.reconcile_missing(false);
        assert_eq!(session.status(), DocumentStatus::Missing);
        assert_eq!(session.content(), "keep my edit");
        assert!(matches!(
            session.begin_save(),
            Err(DocumentError::ExternallyDeleted)
        ));
    }

    #[test]
    fn coordinator_save_as_transitions_untitled_document() {
        let filesystem = FakeFileSystem::default();
        let mut coordinator = DocumentCoordinator::new(filesystem);
        coordinator.update_content("hello");
        let state = coordinator
            .save_as(path("new"), false)
            .expect("save as succeeds");
        assert_eq!(state.status, DocumentStatus::Saved);
        assert!(!state.dirty);
        assert_eq!(state.file_name, "new.md");
    }

    #[test]
    fn coordinator_refuses_stale_disk_revision() {
        let filesystem = FakeFileSystem::default();
        let bytes = b"A".to_vec();
        *filesystem.bytes.lock().expect("fake filesystem lock") = Some(bytes);
        let mut coordinator = DocumentCoordinator::new(filesystem.clone());
        coordinator.open(path("opened")).expect("open succeeds");
        coordinator.update_content("C");
        *filesystem.bytes.lock().expect("fake filesystem lock") = Some(b"B".to_vec());

        let error = coordinator.save().expect_err("stale save is blocked");
        assert_eq!(error, DocumentError::DiskConflict);
        assert_eq!(coordinator.state(true).content.as_deref(), Some("C"));
        assert_eq!(coordinator.state(false).status, DocumentStatus::Conflict);
    }
}
