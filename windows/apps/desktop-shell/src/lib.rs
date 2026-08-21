use std::fmt;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use markowski_core::{AppInfo, AppInfoOperation, AppInfoRequest, AppInfoResponse, IpcError};
use markowski_document::{
    DocumentCoordinator as DomainDocumentCoordinator, DocumentError, DocumentPath, DocumentState,
    ExternalChangeSignal,
};
use markowski_platform_windows::{
    pick_open_document, pick_save_document, WindowsFileSystem, WindowsWatcherHandle,
};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, CloseRequestApi, Emitter, Runtime, State, Window};
use tracing::{error, info, warn};
use tracing_subscriber::EnvFilter;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellError {
    LoggingInitialization,
    CoreInitialization,
    TauriRuntime,
}

impl fmt::Display for ShellError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::LoggingInitialization => "logging could not be initialized",
            Self::CoreInitialization => "the application identity could not be initialized",
            Self::TauriRuntime => "the desktop runtime stopped unexpectedly",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for ShellError {}

type DocumentCoordinator = DomainDocumentCoordinator<WindowsFileSystem>;

pub struct AppState {
    app_info: AppInfo,
    documents: Mutex<DocumentCoordinator>,
    watcher: Mutex<Option<WindowsWatcherHandle>>,
    watcher_error: Mutex<Option<DocumentError>>,
    close_prompt_active: AtomicBool,
    allow_close: AtomicBool,
}

impl AppState {
    fn new(version: &str) -> Result<Self, ShellError> {
        let app_info = AppInfo::for_windows(version).map_err(|error| {
            error!(event = "core_initialization_failed", reason = ?error);
            ShellError::CoreInitialization
        })?;

        Ok(Self {
            app_info,
            documents: Mutex::new(DocumentCoordinator::new(WindowsFileSystem::new())),
            watcher: Mutex::new(None),
            watcher_error: Mutex::new(None),
            close_prompt_active: AtomicBool::new(false),
            allow_close: AtomicBool::new(false),
        })
    }

    fn get_app_info(&self, request: AppInfoRequest) -> Result<AppInfoResponse, IpcError> {
        match request.operation {
            AppInfoOperation::GetAppInfo => Ok(AppInfoResponse {
                app: self.app_info.clone(),
            }),
        }
    }

    fn document_state(&self, include_content: bool) -> Result<DocumentState, DocumentError> {
        let mut state = self
            .documents
            .lock()
            .map_err(|_| DocumentError::ReadFailed)?
            .state(include_content);
        if state.message.is_none() {
            state.message = self
                .watcher_error
                .lock()
                .map_err(|_| DocumentError::ReadFailed)?
                .as_ref()
                .map(DocumentError::user_message);
        }
        Ok(state)
    }

    fn ensure_discard_allowed(&self, discard_changes: bool) -> Result<(), DocumentError> {
        if !discard_changes
            && self
                .documents
                .lock()
                .map_err(|_| DocumentError::ReadFailed)?
                .state(false)
                .dirty
        {
            return Err(DocumentError::UnsavedChanges);
        }
        Ok(())
    }

    fn new_document(&self, discard_changes: bool) -> Result<DocumentState, DocumentError> {
        self.ensure_discard_allowed(discard_changes)?;
        self.documents
            .lock()
            .map_err(|_| DocumentError::ReadFailed)?
            .new_document();
        self.clear_watcher_error();
        self.document_state(true)
    }

    fn open_path(
        &self,
        path: PathBuf,
        discard_changes: bool,
    ) -> Result<DocumentState, DocumentError> {
        self.ensure_discard_allowed(discard_changes)?;
        let path = DocumentPath::new(path)?;
        self.documents
            .lock()
            .map_err(|_| DocumentError::ReadFailed)?
            .open(path)?;
        self.clear_watcher_error();
        self.document_state(true)
    }

    fn update_content(&self, content: String) -> Result<DocumentState, DocumentError> {
        self.documents
            .lock()
            .map_err(|_| DocumentError::ReadFailed)?
            .update_content(content);
        self.document_state(false)
    }

    fn save(&self) -> Result<DocumentState, DocumentError> {
        let result = self
            .documents
            .lock()
            .map_err(|_| DocumentError::ReadFailed)?
            .save();
        if let Err(error) = &result {
            warn!(event = "document_save_failed", code = error.code());
        }
        result
    }

    fn save_as(
        &self,
        path: PathBuf,
        overwrite_confirmed: bool,
    ) -> Result<DocumentState, DocumentError> {
        let path = DocumentPath::new(path)?;
        let result = self
            .documents
            .lock()
            .map_err(|_| DocumentError::ReadFailed)?
            .save_as(path, overwrite_confirmed);
        if let Err(error) = &result {
            warn!(event = "document_save_as_failed", code = error.code());
        }
        result
    }

    fn reload(&self) -> Result<DocumentState, DocumentError> {
        let result = self
            .documents
            .lock()
            .map_err(|_| DocumentError::ReadFailed)?
            .reload();
        if let Err(error) = &result {
            warn!(event = "document_reload_failed", code = error.code());
        }
        result
    }

    fn reconcile(&self, signal: ExternalChangeSignal) -> Result<DocumentState, DocumentError> {
        let state = self
            .documents
            .lock()
            .map_err(|_| DocumentError::ReadFailed)?
            .reconcile(signal);
        Ok(state)
    }

    fn clear_watcher_error(&self) {
        if let Ok(mut error) = self.watcher_error.lock() {
            *error = None;
        }
    }

    fn replace_watcher(self: &Arc<Self>, app_handle: AppHandle) {
        if let Ok(mut watcher) = self.watcher.lock() {
            watcher.take();
        }

        let path = self
            .documents
            .lock()
            .ok()
            .and_then(|documents| documents.path());
        let Some(path) = path else {
            return;
        };

        let weak_state = Arc::downgrade(self);
        match WindowsWatcherHandle::watch(&path, move |signal| {
            let Some(state) = weak_state.upgrade() else {
                return;
            };
            let document_signal: ExternalChangeSignal = signal.into();
            match state.reconcile(document_signal) {
                Ok(document_state) => {
                    let _ = app_handle.emit("document-state-changed", document_state);
                }
                Err(error) => warn!(event = "document_reconcile_failed", code = error.code()),
            }
        }) {
            Ok(handle) => {
                if let Ok(mut watcher) = self.watcher.lock() {
                    *watcher = Some(handle);
                }
            }
            Err(error) => {
                warn!(event = "document_watcher_failed", code = error.code());
                if let Ok(mut watcher_error) = self.watcher_error.lock() {
                    *watcher_error = Some(error);
                }
            }
        }
    }

    fn publish(&self, app_handle: &AppHandle, state: &DocumentState) {
        let _ = app_handle.emit("document-state-changed", state);
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateDocumentContentRequest {
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocumentSwitchRequest {
    pub discard_changes: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GetDocumentStateRequest {
    pub known_memory_generation: Option<u64>,
}

fn default_log_filter() -> &'static str {
    if cfg!(debug_assertions) {
        "markowski_desktop_shell=debug,markowski_core=debug,markowski_document=debug,markowski_platform_windows=debug"
    } else {
        "markowski_desktop_shell=info,markowski_core=info,markowski_document=info,markowski_platform_windows=info"
    }
}

fn build_profile() -> &'static str {
    if cfg!(debug_assertions) {
        "development"
    } else {
        "release"
    }
}

fn initialize_logging() -> Result<(), ShellError> {
    let filter =
        EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(default_log_filter()));

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_ansi(false)
        .try_init()
        .map_err(|_| ShellError::LoggingInitialization)
}

#[cfg(windows)]
fn close_prompt() -> i32 {
    use std::ptr::null_mut;
    use windows_sys::Win32::UI::WindowsAndMessaging::{
        MessageBoxW, MB_ICONWARNING, MB_YESNOCANCEL,
    };

    let message: Vec<u16> = "This document has unsaved changes. Save before closing?\0"
        .encode_utf16()
        .collect();
    let title: Vec<u16> = "Markowski — Unsaved document\0".encode_utf16().collect();
    unsafe {
        MessageBoxW(
            null_mut(),
            message.as_ptr(),
            title.as_ptr(),
            MB_ICONWARNING | MB_YESNOCANCEL,
        )
    }
}

#[cfg(windows)]
fn handle_close_request<R: Runtime>(
    window: &Window<R>,
    api: &CloseRequestApi,
    state: Arc<AppState>,
) {
    if state.allow_close.swap(false, Ordering::SeqCst) {
        return;
    }
    if state.close_prompt_active.swap(true, Ordering::SeqCst) {
        api.prevent_close();
        return;
    }

    let dirty = state
        .document_state(false)
        .map(|document| document.dirty)
        .unwrap_or(true);
    if !dirty {
        state.close_prompt_active.store(false, Ordering::SeqCst);
        return;
    }

    api.prevent_close();
    match close_prompt() {
        windows_sys::Win32::UI::WindowsAndMessaging::IDYES => {
            let state_for_save = state.clone();
            let window_for_close = window.clone();
            std::thread::spawn(move || match state_for_save.save() {
                Ok(_) => {
                    state_for_save.allow_close.store(true, Ordering::SeqCst);
                    state_for_save
                        .close_prompt_active
                        .store(false, Ordering::SeqCst);
                    if window_for_close.close().is_err() {
                        state_for_save.allow_close.store(false, Ordering::SeqCst);
                    }
                }
                Err(error) => {
                    state_for_save
                        .close_prompt_active
                        .store(false, Ordering::SeqCst);
                    warn!(event = "close_save_failed", code = error.code());
                }
            });
        }
        windows_sys::Win32::UI::WindowsAndMessaging::IDNO => {
            state.allow_close.store(true, Ordering::SeqCst);
            state.close_prompt_active.store(false, Ordering::SeqCst);
            if window.close().is_err() {
                state.allow_close.store(false, Ordering::SeqCst);
            }
        }
        _ => state.close_prompt_active.store(false, Ordering::SeqCst),
    }
}

#[tauri::command]
fn get_app_info(
    request: AppInfoRequest,
    state: State<'_, Arc<AppState>>,
) -> Result<AppInfoResponse, IpcError> {
    state.get_app_info(request)
}

#[tauri::command]
async fn new_document(
    request: DocumentSwitchRequest,
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<DocumentState, DocumentError> {
    let state = state.inner().clone();
    let result = tokio::task::spawn_blocking({
        let state = state.clone();
        move || state.new_document(request.discard_changes)
    })
    .await
    .map_err(|_| DocumentError::WriteFailed)??;
    state.replace_watcher(app.clone());
    state.publish(&app, &result);
    Ok(result)
}

#[tauri::command]
async fn open_document(
    request: DocumentSwitchRequest,
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<DocumentState, DocumentError> {
    let state = state.inner().clone();
    state.ensure_discard_allowed(request.discard_changes)?;
    let path = pick_open_document().ok_or(DocumentError::DialogCancelled)?;
    let result = tokio::task::spawn_blocking({
        let state = state.clone();
        move || state.open_path(path, request.discard_changes)
    })
    .await
    .map_err(|_| DocumentError::ReadFailed)??;
    state.replace_watcher(app.clone());
    state.publish(&app, &result);
    Ok(result)
}

#[tauri::command]
async fn update_document_content(
    request: UpdateDocumentContentRequest,
    state: State<'_, Arc<AppState>>,
) -> Result<DocumentState, DocumentError> {
    let state = state.inner().clone();
    tokio::task::spawn_blocking(move || state.update_content(request.content))
        .await
        .map_err(|_| DocumentError::WriteFailed)?
        .map(|mut state| {
            state.content = None;
            state
        })
}

#[tauri::command]
async fn save_document(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<DocumentState, DocumentError> {
    let state = state.inner().clone();
    let result = tokio::task::spawn_blocking({
        let state = state.clone();
        move || state.save()
    })
    .await
    .map_err(|_| DocumentError::WriteFailed)??;
    state.replace_watcher(app.clone());
    state.publish(&app, &result);
    Ok(result)
}

#[tauri::command]
async fn save_document_as(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<DocumentState, DocumentError> {
    let path = pick_save_document().ok_or(DocumentError::DialogCancelled)?;

    let state = state.inner().clone();
    let result = tokio::task::spawn_blocking({
        let state = state.clone();
        move || state.save_as(path, true)
    })
    .await
    .map_err(|_| DocumentError::WriteFailed)??;
    state.replace_watcher(app.clone());
    state.publish(&app, &result);
    Ok(result)
}

#[tauri::command]
async fn reload_document(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<DocumentState, DocumentError> {
    let state = state.inner().clone();
    let result = tokio::task::spawn_blocking({
        let state = state.clone();
        move || state.reload()
    })
    .await
    .map_err(|_| DocumentError::ReloadFailed)??;
    state.publish(&app, &result);
    Ok(result)
}

#[tauri::command]
fn get_document_state(
    request: GetDocumentStateRequest,
    state: State<'_, Arc<AppState>>,
) -> Result<DocumentState, DocumentError> {
    let current = state.document_state(false)?;
    let include_content = request.known_memory_generation != Some(current.memory_generation);
    state.document_state(include_content)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() -> Result<(), ShellError> {
    initialize_logging()?;

    let version = env!("CARGO_PKG_VERSION");
    let state = Arc::new(AppState::new(version)?);
    let close_state = state.clone();
    info!(
        event = "startup",
        app = "Markowski",
        version,
        platform = std::env::consts::OS,
        architecture = std::env::consts::ARCH,
        profile = build_profile(),
        "starting desktop shell"
    );

    tauri::Builder::default()
        .manage(state)
        .on_window_event(move |window, event| {
            #[cfg(windows)]
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                handle_close_request(window, api, close_state.clone());
            }
            #[cfg(not(windows))]
            let _ = (&window, &event, &close_state);
        })
        .setup(|_app| {
            info!(
                event = "initialization_complete",
                "desktop shell initialized"
            );
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_app_info,
            new_document,
            open_document,
            update_document_content,
            save_document,
            save_document_as,
            reload_document,
            get_document_state
        ])
        .run(tauri::generate_context!())
        .map_err(|_| {
            error!(
                event = "runtime_failed",
                "desktop shell stopped with an error"
            );
            ShellError::TauriRuntime
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use markowski_core::CoreError;

    #[test]
    fn default_log_filter_is_local_and_structured() {
        let filter = default_log_filter();

        assert!(filter.contains("markowski_desktop_shell"));
        assert!(filter.contains("markowski_document"));
        assert!(!filter.contains("trace"));
    }

    #[test]
    fn app_state_returns_the_typed_info_response() {
        let state = AppState::new("0.1.0").expect("state initializes");
        let response = state
            .get_app_info(AppInfoRequest::default())
            .expect("request succeeds");

        assert_eq!(response.app.name, "Markowski");
        assert_eq!(response.app.version.as_str(), "0.1.0");
        assert_eq!(response.app.platform, "windows");
    }

    #[test]
    fn core_initialization_failure_is_not_exposed_as_a_raw_error() {
        let error = AppInfo::for_windows(" ").expect_err("blank version is invalid");
        let shell_error = match error {
            CoreError::InvalidVersion => ShellError::CoreInitialization,
        };

        assert_eq!(
            shell_error.to_string(),
            "the application identity could not be initialized"
        );
    }

    #[test]
    fn new_state_has_no_filesystem_path() {
        let state = AppState::new("0.1.0").expect("state initializes");
        let document = state.document_state(true).expect("document state");
        assert_eq!(document.status.label(), "Untitled");
        assert!(document.path.is_none());
        assert_eq!(document.content.as_deref(), Some(""));
    }
}
