use markowski_document::{
    sha256_bytes, snapshot_from_read, DocumentCoordinator, DocumentError, DocumentFileSystem,
    DocumentPath, DocumentSession, DocumentStatus, ExternalChangeSignal,
};
use markowski_platform_windows::WindowsFileSystem;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

static TEST_SEQUENCE: AtomicU64 = AtomicU64::new(0);

struct TestRoot(PathBuf);

impl TestRoot {
    fn new(label: &str) -> Self {
        let path = std::env::temp_dir().join(format!(
            "markowski-phase3-integration-{label}-{}-{}",
            std::process::id(),
            TEST_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&path).expect("isolated temporary directory");
        Self(path)
    }

    fn path(&self, name: &str) -> PathBuf {
        self.0.join(name)
    }
}

impl Drop for TestRoot {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn document_path(path: impl AsRef<Path>) -> DocumentPath {
    DocumentPath::new(path.as_ref().to_path_buf()).expect("absolute supported document path")
}

#[test]
fn filesystem_lifecycle_matrix_covers_phase3_t1_to_t20() {
    let root = TestRoot::new("matrix");
    let filesystem = WindowsFileSystem::new();

    // T1/T2/T3/T15/T16: open and save both supported extensions with newline policy.
    let md_path = root.path("english.md");
    fs::write(&md_path, b"# title\r\n\r\nbody\r\n").expect("UTF-8 Markdown fixture");
    let mut markdown = DocumentCoordinator::new(filesystem);
    markdown.open(document_path(&md_path)).expect("T1 open md");
    assert_eq!(
        markdown.state(true).content.as_deref(),
        Some("# title\n\nbody\n")
    );
    markdown.update_content("# title\n\nupdated\n");
    markdown.save().expect("T3 save existing document");
    assert_eq!(
        fs::read(&md_path).expect("saved bytes"),
        b"# title\r\n\r\nupdated\r\n"
    );

    let mmd_path = root.path("diagram.mmd");
    fs::write(&mmd_path, b"graph TD\nA-->B\n").expect("Mermaid fixture");
    markdown
        .open(document_path(&mmd_path))
        .expect("T2 open mmd");
    assert_eq!(markdown.state(false).file_extension, Some("mmd".to_owned()));

    // T4/T5/T12/T13/T14: first Save As, atomic replacement, Persian and emoji paths/content.
    let persian_path = root.path("یادداشت 😊.md");
    let mut untitled = DocumentCoordinator::new(WindowsFileSystem::new());
    untitled.update_content("# عنوان\n\nسلام جهان\n");
    untitled
        .save_as(document_path(&persian_path), false)
        .expect("T4 first Save As");
    assert_eq!(
        fs::read(&persian_path).expect("T12/T14 Unicode filename bytes"),
        "# عنوان\r\n\r\nسلام جهان\r\n".as_bytes()
    );
    untitled.update_content("# عنوان\n\nسلام جهان\nتغییر");
    untitled.save().expect("T5 atomic replacement");
    assert!(untitled.state(false).persisted_hash.is_some());
    let second_save_as = root.path("second-save-as.mmd");
    untitled
        .save_as(document_path(&second_save_as), false)
        .expect("T11 subsequent Save As");
    assert_eq!(untitled.state(false).file_name, "second-save-as.mmd");
    assert!(second_save_as.is_file());

    // T6/T19: a failed destination operation is typed and cannot touch the original.
    let protected_path = root.path("protected.md");
    fs::write(&protected_path, b"original").expect("protected original");
    let missing_destination = document_path(root.path("missing/nested/new.md"));
    let failure = WindowsFileSystem::new()
        .write_atomic(&missing_destination, b"replacement", None, true)
        .expect_err("T6 simulated replacement failure");
    assert_eq!(failure, DocumentError::InvalidPath);
    assert_eq!(
        fs::read(&protected_path).expect("T6 original remains"),
        b"original"
    );

    let directory_as_document = root.path("not-a-file.md");
    fs::create_dir(&directory_as_document).expect("permission/error fixture");
    let read_error = WindowsFileSystem::new()
        .read_document(&document_path(&directory_as_document))
        .expect_err("T19 invalid filesystem target");
    assert!(matches!(
        read_error,
        DocumentError::PermissionDenied | DocumentError::ReadFailed
    ));

    // T7/T8/T9/T10/T11: reconciliation never discards in-memory edits.
    let changed_path = root.path("changed.md");
    fs::write(&changed_path, b"one").expect("change fixture");
    let mut clean = DocumentCoordinator::new(WindowsFileSystem::new());
    clean
        .open(document_path(&changed_path))
        .expect("open changed fixture");
    fs::write(&changed_path, b"two").expect("T7 external modification");
    assert_eq!(
        clean.reconcile(ExternalChangeSignal::Changed).status,
        DocumentStatus::ExternalChanged
    );
    assert_eq!(
        clean.reload().expect("T9 safe reload").content.as_deref(),
        Some("two")
    );

    let conflict_path = root.path("conflict.md");
    fs::write(&conflict_path, b"disk-a").expect("conflict fixture");
    let mut conflict = DocumentCoordinator::new(WindowsFileSystem::new());
    conflict
        .open(document_path(&conflict_path))
        .expect("open conflict fixture");
    conflict.update_content("memory-c");
    fs::write(&conflict_path, b"disk-b").expect("T8 external conflict");
    let conflict_state = conflict.reconcile(ExternalChangeSignal::Changed);
    assert_eq!(conflict_state.status, DocumentStatus::Conflict);
    assert_eq!(conflict_state.content, None);
    assert_eq!(conflict.state(true).content.as_deref(), Some("memory-c"));
    assert_eq!(
        conflict.save().expect_err("T8 conflict save blocked"),
        DocumentError::ConflictActive
    );

    let deleted_path = root.path("deleted.md");
    fs::write(&deleted_path, b"keep in memory").expect("delete fixture");
    let mut deleted = DocumentCoordinator::new(WindowsFileSystem::new());
    deleted
        .open(document_path(&deleted_path))
        .expect("open delete fixture");
    deleted.update_content("keep this edit");
    fs::remove_file(&deleted_path).expect("T10 external delete");
    let deleted_state = deleted.reconcile(ExternalChangeSignal::Removed);
    assert_eq!(deleted_state.status, DocumentStatus::Missing);
    assert_eq!(
        deleted.state(true).content.as_deref(),
        Some("keep this edit")
    );

    let renamed_path = root.path("renamed.md");
    let moved_path = root.path("moved.md");
    fs::write(&renamed_path, b"move me").expect("rename fixture");
    let mut renamed = DocumentCoordinator::new(WindowsFileSystem::new());
    renamed
        .open(document_path(&renamed_path))
        .expect("open rename fixture");
    fs::rename(&renamed_path, &moved_path).expect("T11 external rename");
    assert_eq!(
        renamed.reconcile(ExternalChangeSignal::Renamed).status,
        DocumentStatus::ExternallyRenamed
    );

    // T17/T18: empty and deterministic 1 MiB documents remain hashable and savable.
    let empty_path = root.path("empty.md");
    fs::write(&empty_path, b"").expect("T17 empty fixture");
    let mut empty = DocumentCoordinator::new(WindowsFileSystem::new());
    empty
        .open(document_path(&empty_path))
        .expect("T17 open empty");
    assert_eq!(empty.state(true).content.as_deref(), Some(""));

    let large_path = root.path("large.md");
    let large = "# line\n".repeat(1_048_576 / 7);
    fs::write(&large_path, large.as_bytes()).expect("T18 large fixture");
    let mut large_document = DocumentCoordinator::new(WindowsFileSystem::new());
    large_document
        .open(document_path(&large_path))
        .expect("T18 open large document");
    assert_eq!(
        large_document.state(false).persisted_hash.as_deref(),
        Some(sha256_bytes(large.as_bytes()).as_str())
    );
    large_document.update_content(format!("{large}# tail\n"));
    large_document.save().expect("T18 save large document");

    // BOM policy: preserve a UTF-8 BOM while normalizing the in-memory newline model.
    let bom_path = root.path("bom.md");
    fs::write(&bom_path, b"\xEF\xBB\xBFone\r\ntwo\r\n").expect("BOM fixture");
    let mut bom = DocumentCoordinator::new(WindowsFileSystem::new());
    bom.open(document_path(&bom_path)).expect("BOM open");
    bom.update_content("one\ntwo\nthree");
    bom.save().expect("BOM save");
    assert!(fs::read(&bom_path)
        .expect("BOM bytes")
        .starts_with(b"\xEF\xBB\xBF"));

    // T20: a save proposal is tied to its memory revision; a newer edit stays dirty.
    let concurrent_path = root.path("concurrent.md");
    fs::write(&concurrent_path, b"revision zero").expect("T20 initial document");
    let concurrent_document_path = document_path(&concurrent_path);
    let concurrent_read = WindowsFileSystem::new()
        .read_document(&concurrent_document_path)
        .expect("T20 read initial document");
    let (concurrent_content, concurrent_snapshot) =
        snapshot_from_read(concurrent_document_path.clone(), concurrent_read)
            .expect("T20 initial snapshot");
    let mut concurrent = DocumentSession::from_disk(
        concurrent_document_path,
        concurrent_content,
        concurrent_snapshot,
    );
    concurrent.update_content("revision one");
    let pending_save = concurrent.begin_save().expect("T20 save proposal");
    concurrent.update_content("revision two");
    assert_eq!(pending_save.memory_generation, 1);
    assert!(concurrent.is_dirty(), "T20 newer edit must remain dirty");
}
