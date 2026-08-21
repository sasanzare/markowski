//! Windows filesystem and watcher boundary.
//!
//! All filesystem authority stays here.  The document crate receives only
//! validated byte snapshots and typed outcomes, never Win32 handles or raw
//! operating-system errors.

use markowski_document::{
    sha256_bytes, DiskRead, DiskSnapshot, DocumentError, DocumentFileSystem, DocumentPath,
    ExternalChangeSignal, FileFingerprint,
};
use notify::event::{ModifyKind, RenameMode};
use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::thread::{self, JoinHandle};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);
const WATCH_DEBOUNCE: Duration = Duration::from_millis(250);

#[derive(Debug, Clone, Copy, Default)]
pub struct WindowsFileSystem;

impl WindowsFileSystem {
    pub fn new() -> Self {
        Self
    }

    fn stable_read(&self, path: &DocumentPath) -> Result<DiskRead, DocumentError> {
        for _ in 0..3 {
            let before = metadata(path.as_path())?;
            let bytes = fs::read(path.as_path()).map_err(map_read_error)?;
            let after = metadata(path.as_path())?;
            let before_fingerprint = fingerprint(&before);
            let after_fingerprint = fingerprint(&after);
            if before_fingerprint == after_fingerprint
                && after_fingerprint.byte_len == bytes.len() as u64
            {
                return Ok(DiskRead {
                    bytes,
                    fingerprint: after_fingerprint,
                });
            }
        }

        Err(DocumentError::ReadRace)
    }

    fn temp_path(path: &DocumentPath) -> Result<PathBuf, DocumentError> {
        let parent = path.as_path().parent().ok_or(DocumentError::InvalidPath)?;
        if !parent.is_dir() {
            return Err(DocumentError::InvalidPath);
        }
        let file_name = path
            .as_path()
            .file_name()
            .ok_or(DocumentError::InvalidPath)?
            .to_string_lossy();
        let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or_default();
        Ok(parent.join(format!(
            ".{file_name}.markowski-{timestamp}-{}-{sequence}.tmp",
            std::process::id()
        )))
    }

    fn write_temp(path: &Path, bytes: &[u8]) -> Result<(), DocumentError> {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)
            .map_err(map_write_error)?;
        if let Err(error) = file.write_all(bytes).and_then(|_| file.sync_all()) {
            let _ = fs::remove_file(path);
            return Err(map_write_error(error));
        }
        close_file(file)
    }
}

impl DocumentFileSystem for WindowsFileSystem {
    fn read_document(&self, path: &DocumentPath) -> Result<DiskRead, DocumentError> {
        self.stable_read(path)
    }

    fn write_atomic(
        &self,
        path: &DocumentPath,
        bytes: &[u8],
        expected: Option<&DiskSnapshot>,
        overwrite_confirmed: bool,
    ) -> Result<DiskRead, DocumentError> {
        let existing = match self.read_document(path) {
            Ok(read) => Some(read),
            Err(DocumentError::FileMissing) => None,
            Err(error) => return Err(error),
        };

        if let Some(expected) = expected {
            let current = existing.as_ref().ok_or(DocumentError::FileMissing)?;
            if sha256_bytes(&current.bytes) != expected.content_hash {
                return Err(DocumentError::DiskConflict);
            }
        } else if existing.is_some() && !overwrite_confirmed {
            return Err(DocumentError::TargetExists);
        }

        // Validate the destination immediately before the replacement.  The
        // Windows replacement itself remains atomic on the same volume, and a
        // conflicting hash is surfaced before the original path is touched.
        if let Some(expected) = expected {
            let current = self.read_document(path).map_err(|error| match error {
                DocumentError::FileMissing => DocumentError::ExternallyDeleted,
                other => other,
            })?;
            if sha256_bytes(&current.bytes) != expected.content_hash {
                return Err(DocumentError::DiskConflict);
            }
        }

        let temporary = Self::temp_path(path)?;
        Self::write_temp(&temporary, bytes)?;
        if let Err(error) = atomic_replace(&temporary, path.as_path()) {
            // The temporary file is a complete duplicate of in-memory content.
            // Keep it when replacement is ambiguous so a recovery tool can
            // inspect it; deterministic temp-write failures are cleaned above.
            tracing_free_error(error);
            return Err(DocumentError::AtomicReplaceFailed);
        }

        let final_read = self.read_document(path)?;
        if sha256_bytes(&final_read.bytes) != sha256_bytes(bytes) {
            return Err(DocumentError::AtomicReplaceFailed);
        }
        Ok(final_read)
    }
}

fn close_file(file: File) -> Result<(), DocumentError> {
    drop(file);
    Ok(())
}

fn metadata(path: &Path) -> Result<fs::Metadata, DocumentError> {
    fs::metadata(path).map_err(map_read_error)
}

fn fingerprint(metadata: &fs::Metadata) -> FileFingerprint {
    let modified_nanos = metadata
        .modified()
        .ok()
        .and_then(|modified| modified.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_nanos());
    FileFingerprint {
        byte_len: metadata.len(),
        modified_nanos,
    }
}

fn map_read_error(error: io::Error) -> DocumentError {
    match error.kind() {
        io::ErrorKind::NotFound => DocumentError::FileMissing,
        io::ErrorKind::PermissionDenied => DocumentError::PermissionDenied,
        _ => DocumentError::ReadFailed,
    }
}

fn map_write_error(error: io::Error) -> DocumentError {
    match error.kind() {
        io::ErrorKind::PermissionDenied => DocumentError::PermissionDenied,
        io::ErrorKind::NotFound => DocumentError::InvalidPath,
        _ => DocumentError::WriteFailed,
    }
}

// The native operation is intentionally isolated to this function.  The
// source and target are both validated paths in the same directory, and the
// temporary file is closed and flushed before this call. `MoveFileExW` with
// REPLACE_EXISTING and WRITE_THROUGH is the Windows replace-oriented move used
// for both first saves and existing-file saves; no original-file truncation is
// performed.
#[cfg(windows)]
fn atomic_replace(source: &Path, target: &Path) -> Result<(), io::Error> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{
        MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH,
    };

    let source: Vec<u16> = source
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    let target: Vec<u16> = target
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    let flags = MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH;
    let result = unsafe { MoveFileExW(source.as_ptr(), target.as_ptr(), flags) };
    if result == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(not(windows))]
fn atomic_replace(source: &Path, target: &Path) -> Result<(), io::Error> {
    fs::rename(source, target)
}

// Keep the error out of the public error model and out of logs.  The concrete
// OS error can contain a user path; callers receive only AtomicReplaceFailed.
fn tracing_free_error(_error: io::Error) {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WatchSignal {
    Changed,
    Removed,
    Renamed,
}

impl WatchSignal {
    fn merge(self, other: Self) -> Self {
        match (self, other) {
            (Self::Renamed, _) | (_, Self::Renamed) => Self::Renamed,
            (Self::Removed, _) | (_, Self::Removed) => Self::Removed,
            _ => Self::Changed,
        }
    }
}

pub struct WindowsWatcherHandle {
    stop: Option<Sender<()>>,
    thread: Option<JoinHandle<()>>,
}

impl WindowsWatcherHandle {
    pub fn watch(
        path: &DocumentPath,
        callback: impl Fn(WatchSignal) + Send + 'static,
    ) -> Result<Self, DocumentError> {
        let parent = path
            .as_path()
            .parent()
            .ok_or(DocumentError::InvalidPath)?
            .to_path_buf();
        if !parent.is_dir() {
            return Err(DocumentError::WatcherFailed);
        }

        let target = path.as_path().to_path_buf();
        let (raw_sender, raw_receiver) = mpsc::channel::<notify::Result<Event>>();
        let (stop_sender, stop_receiver) = mpsc::channel::<()>();
        let (ready_sender, ready_receiver) = mpsc::sync_channel::<Result<(), DocumentError>>(1);

        let thread = thread::spawn(move || {
            let sender = raw_sender.clone();
            let watcher_result = RecommendedWatcher::new(
                move |event| {
                    let _ = sender.send(event);
                },
                Config::default(),
            );
            let mut watcher = match watcher_result {
                Ok(watcher) => watcher,
                Err(_) => {
                    let _ = ready_sender.send(Err(DocumentError::WatcherFailed));
                    return;
                }
            };

            if watcher.watch(&parent, RecursiveMode::NonRecursive).is_err() {
                let _ = ready_sender.send(Err(DocumentError::WatcherFailed));
                return;
            }
            let _ = ready_sender.send(Ok(()));

            watcher_loop(&target, raw_receiver, stop_receiver, callback);
        });

        match ready_receiver.recv() {
            Ok(Ok(())) => Ok(Self {
                stop: Some(stop_sender),
                thread: Some(thread),
            }),
            Ok(Err(error)) => {
                let _ = thread.join();
                Err(error)
            }
            Err(_) => {
                let _ = thread.join();
                Err(DocumentError::WatcherFailed)
            }
        }
    }
}

impl Drop for WindowsWatcherHandle {
    fn drop(&mut self) {
        if let Some(sender) = self.stop.take() {
            let _ = sender.send(());
        }
        if let Some(thread) = self.thread.take() {
            if thread.thread().id() != thread::current().id() {
                let _ = thread.join();
            }
        }
    }
}

fn watcher_loop(
    target: &Path,
    raw_receiver: Receiver<notify::Result<Event>>,
    stop_receiver: Receiver<()>,
    callback: impl Fn(WatchSignal),
) {
    loop {
        if stop_receiver.try_recv().is_ok() {
            return;
        }

        let first = match raw_receiver.recv_timeout(Duration::from_millis(100)) {
            Ok(event) => event,
            Err(RecvTimeoutError::Timeout) => continue,
            Err(RecvTimeoutError::Disconnected) => return,
        };

        let mut signal = signal_for_event(target, &first);
        let deadline = std::time::Instant::now() + WATCH_DEBOUNCE;
        while let Some(remaining) = deadline.checked_duration_since(std::time::Instant::now()) {
            match raw_receiver.recv_timeout(remaining) {
                Ok(event) => signal = signal.merge(signal_for_event(target, &event)),
                Err(RecvTimeoutError::Timeout | RecvTimeoutError::Disconnected) => break,
            }
        }
        callback(signal);
    }
}

fn signal_for_event(target: &Path, event: &notify::Result<Event>) -> WatchSignal {
    let Ok(event) = event else {
        return WatchSignal::Changed;
    };
    let touches_parent = event
        .paths
        .iter()
        .any(|path| path.parent() == target.parent());
    if !touches_parent {
        return WatchSignal::Changed;
    }

    match event.kind {
        EventKind::Remove(_) => WatchSignal::Removed,
        EventKind::Modify(ModifyKind::Name(RenameMode::From | RenameMode::Both)) => {
            WatchSignal::Renamed
        }
        EventKind::Modify(ModifyKind::Name(_)) => WatchSignal::Renamed,
        _ => WatchSignal::Changed,
    }
}

impl From<WatchSignal> for ExternalChangeSignal {
    fn from(value: WatchSignal) -> Self {
        match value {
            WatchSignal::Changed => Self::Changed,
            WatchSignal::Removed => Self::Removed,
            WatchSignal::Renamed => Self::Renamed,
        }
    }
}

/// Opens the narrow native file picker used by the Tauri shell.  The browser
/// receives only the selected path returned by this command; it never gets a
/// generic filesystem capability.
#[cfg(windows)]
pub fn pick_open_document() -> Option<PathBuf> {
    native_document_dialog(false)
}

#[cfg(not(windows))]
pub fn pick_open_document() -> Option<PathBuf> {
    None
}

#[cfg(windows)]
pub fn pick_save_document() -> Option<PathBuf> {
    native_document_dialog(true)
}

#[cfg(not(windows))]
pub fn pick_save_document() -> Option<PathBuf> {
    None
}

#[cfg(windows)]
fn native_document_dialog(save: bool) -> Option<PathBuf> {
    use std::mem::size_of;
    use std::os::windows::ffi::OsStringExt;
    use windows_sys::Win32::UI::Controls::Dialogs::{
        GetOpenFileNameW, GetSaveFileNameW, OFN_EXPLORER, OFN_FILEMUSTEXIST, OFN_NOCHANGEDIR,
        OFN_OVERWRITEPROMPT, OFN_PATHMUSTEXIST, OPENFILENAMEW,
    };

    let filter: Vec<u16> = if save {
        "Markdown (*.md)\0*.md\0Mermaid (*.mmd)\0*.mmd\0\0"
            .encode_utf16()
            .collect()
    } else {
        "Markdown and Mermaid\0*.md;*.mmd\0\0"
            .encode_utf16()
            .collect()
    };
    let mut file_buffer = vec![0u16; 32_768];
    let default_name: Vec<u16> = "Untitled.md\0".encode_utf16().collect();
    let title: Vec<u16> = if save {
        "Save the Markdown document as\0".encode_utf16().collect()
    } else {
        "Open a Markdown document\0".encode_utf16().collect()
    };
    let mut dialog: OPENFILENAMEW = unsafe { std::mem::zeroed() };
    dialog.lStructSize = size_of::<OPENFILENAMEW>() as u32;
    dialog.lpstrFilter = filter.as_ptr();
    dialog.lpstrFile = file_buffer.as_mut_ptr();
    dialog.nMaxFile = file_buffer.len() as u32;
    dialog.lpstrTitle = title.as_ptr();
    // The selected filter determines the default extension.  We append it
    // after the dialog returns instead of forcing every Save As operation to
    // become `.md` when the Mermaid filter was selected.
    dialog.lpstrDefExt = std::ptr::null();
    dialog.Flags = if save {
        OFN_EXPLORER | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR | OFN_OVERWRITEPROMPT
    } else {
        OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR
    };
    if save {
        file_buffer[..default_name.len()].copy_from_slice(&default_name);
    }

    let selected = if save {
        unsafe { GetSaveFileNameW(&mut dialog) }
    } else {
        unsafe { GetOpenFileNameW(&mut dialog) }
    };
    if selected == 0 {
        return None;
    }

    let end = file_buffer
        .iter()
        .position(|value| *value == 0)
        .unwrap_or(file_buffer.len());
    if end == 0 {
        return None;
    }
    let mut path = PathBuf::from(std::ffi::OsString::from_wide(&file_buffer[..end]));
    if save && path.extension().is_none() {
        path.set_extension(if dialog.nFilterIndex == 2 {
            "mmd"
        } else {
            "md"
        });
    }
    Some(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use markowski_document::{DocumentCoordinator, DocumentStatus};
    use std::sync::mpsc;

    fn temp_root(label: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!(
            "markowski-phase3-{label}-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).expect("temporary root");
        root
    }

    #[test]
    fn atomic_write_round_trips_unicode_filename_and_crlf_content() {
        let root = temp_root("unicode");
        let path = root.join("یادداشت 😊.MD");
        fs::write(&path, "# عنوان\r\n\r\nسلام\r\n").expect("initial document");
        let document_path = DocumentPath::new(path.clone()).expect("supported path");
        let mut coordinator = DocumentCoordinator::new(WindowsFileSystem::new());
        coordinator.open(document_path).expect("open document");
        assert_eq!(
            coordinator.state(true).content.as_deref(),
            Some("# عنوان\n\nسلام\n")
        );

        coordinator.update_content("# عنوان\n\nسلام\nتغییر");
        let state = coordinator.save().expect("safe save");
        assert_eq!(state.status, DocumentStatus::Saved);
        assert!(!state.dirty);
        let persisted = fs::read(&path).expect("persisted document");
        assert_eq!(
            String::from_utf8(persisted).expect("UTF-8"),
            "# عنوان\r\n\r\nسلام\r\nتغییر"
        );
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn replacement_failure_does_not_truncate_an_existing_document() {
        let root = temp_root("failure");
        let path = root.join("safe.md");
        fs::write(&path, "original").expect("initial document");
        let document_path = DocumentPath::new(path.clone()).expect("supported path");
        let filesystem = WindowsFileSystem::new();
        let snapshot = filesystem.read_document(&document_path).expect("snapshot");
        let (_, expected) = markowski_document::snapshot_from_read(document_path.clone(), snapshot)
            .expect("expected snapshot");

        let other_root = root.join("missing").join("nested");
        let other_path = DocumentPath::new(other_root.join("new.md")).expect("supported path");
        let error = filesystem
            .write_atomic(&other_path, b"new", None, true)
            .expect_err("missing destination directory fails");
        assert_eq!(error, DocumentError::InvalidPath);
        assert_eq!(
            fs::read_to_string(&path).expect("original remains"),
            "original"
        );
        assert_eq!(expected.content_hash, sha256_bytes(b"original"));
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn watcher_reports_external_file_activity_after_debounce() {
        let root = temp_root("watcher");
        let path = root.join("watch.md");
        fs::write(&path, "one").expect("initial document");
        let document_path = DocumentPath::new(path.clone()).expect("supported path");
        let (sender, receiver) = mpsc::channel();
        let watcher = WindowsWatcherHandle::watch(&document_path, move |signal| {
            let _ = sender.send(signal);
        })
        .expect("watcher starts");

        fs::write(&path, "two").expect("external write");
        let signal = receiver
            .recv_timeout(Duration::from_secs(3))
            .expect("Windows watcher event");
        assert!(matches!(
            signal,
            WatchSignal::Changed | WatchSignal::Removed | WatchSignal::Renamed
        ));
        drop(watcher);
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn own_save_watcher_event_does_not_create_a_false_conflict() {
        let root = temp_root("own-save");
        let path = root.join("own-save.md");
        fs::write(&path, "before").expect("initial document");
        let document_path = DocumentPath::new(path.clone()).expect("supported path");
        let (sender, receiver) = mpsc::channel();
        let watcher = WindowsWatcherHandle::watch(&document_path, move |signal| {
            let _ = sender.send(signal);
        })
        .expect("watcher starts");

        let mut coordinator = DocumentCoordinator::new(WindowsFileSystem::new());
        coordinator.open(document_path).expect("open document");
        coordinator.update_content("after");
        let state = coordinator.save().expect("own save succeeds");
        assert_eq!(state.status, DocumentStatus::Saved);

        if let Ok(signal) = receiver.recv_timeout(Duration::from_secs(3)) {
            let reconciled = coordinator.reconcile(signal.into());
            assert_ne!(reconciled.status, DocumentStatus::Conflict);
            assert_eq!(reconciled.disk_hash, reconciled.persisted_hash);
        }

        drop(watcher);
        let _ = fs::remove_dir_all(root);
    }
}
