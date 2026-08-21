use js_sys::Promise;
use leptos::prelude::*;
use leptos::task::spawn_local;
use markowski_core::{AppInfo, AppInfoRequest, AppInfoResponse, IpcError, PRODUCT_NAME};
use markowski_document::{DocumentError, DocumentState, DocumentStatus};
use serde::de::DeserializeOwned;
use serde::Serialize;
use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::JsFuture;
use web_sys::MouseEvent;

use crate::state::{
    clamp_sidebar_width, ResizeStart, ThemePreference, WorkspaceMode, SIDEBAR_DEFAULT_WIDTH,
    SIDEBAR_MAX_WIDTH, SIDEBAR_MIN_WIDTH,
};

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(catch, js_namespace = ["window", "__TAURI_INTERNALS__"])]
    fn invoke(command: &str, args: JsValue) -> Result<Promise, JsValue>;
}

#[derive(Debug, Clone)]
enum BridgeState {
    Loading,
    Ready(AppInfo),
    Failed(IpcError),
}

#[derive(Clone, Copy)]
struct UiState {
    mode: RwSignal<WorkspaceMode>,
    theme: RwSignal<ThemePreference>,
    sidebar_visible: RwSignal<bool>,
    sidebar_width: RwSignal<u16>,
    resize_start: RwSignal<Option<ResizeStart>>,
    notice: RwSignal<Option<String>>,
    document_state: RwSignal<DocumentState>,
    document_content: RwSignal<String>,
    edit_ticket: RwSignal<u64>,
}

#[derive(Serialize)]
struct GetAppInfoInvokeArgs {
    request: AppInfoRequest,
}

#[derive(Serialize)]
struct GetDocumentStateInvokeArgs {
    known_memory_generation: Option<u64>,
}

#[derive(Serialize)]
struct UpdateDocumentContentInvokeArgs {
    content: String,
}

#[derive(Serialize)]
struct DocumentSwitchInvokeArgs {
    discard_changes: bool,
}

const CONTENT_UPDATE_DEBOUNCE_MS: i32 = 180;
const AUTOSAVE_DEBOUNCE_MS: i32 = 700;

fn decode_bridge_error(error: JsValue) -> IpcError {
    serde_wasm_bindgen::from_value(error).unwrap_or_else(|_| IpcError::bridge_unavailable())
}

fn decode_document_error(error: JsValue) -> DocumentError {
    serde_wasm_bindgen::from_value(error).unwrap_or(DocumentError::ReadFailed)
}

async fn invoke_document<R: DeserializeOwned>(
    command: &str,
    args: JsValue,
) -> Result<R, DocumentError> {
    let promise = invoke(command, args).map_err(decode_document_error)?;
    let response = JsFuture::from(promise)
        .await
        .map_err(decode_document_error)?;
    serde_wasm_bindgen::from_value(response).map_err(|_| DocumentError::ReadFailed)
}

async fn invoke_document_without_args<R: DeserializeOwned>(
    command: &str,
) -> Result<R, DocumentError> {
    invoke_document(command, JsValue::NULL).await
}

async fn request_app_info() -> Result<AppInfo, IpcError> {
    let args = serde_wasm_bindgen::to_value(&GetAppInfoInvokeArgs {
        request: AppInfoRequest::default(),
    })
    .map_err(|_| IpcError::initialization())?;

    let promise = invoke("get_app_info", args).map_err(decode_bridge_error)?;
    let response = JsFuture::from(promise).await.map_err(decode_bridge_error)?;
    let response: AppInfoResponse =
        serde_wasm_bindgen::from_value(response).map_err(|_| IpcError::initialization())?;

    Ok(response.app)
}

async fn request_document_state(
    known_memory_generation: Option<u64>,
) -> Result<DocumentState, DocumentError> {
    let args = serde_wasm_bindgen::to_value(&GetDocumentStateInvokeArgs {
        known_memory_generation,
    })
    .map_err(|_| DocumentError::ReadFailed)?;
    invoke_document("get_document_state", args).await
}

fn device_scale_label() -> String {
    let ratio = web_sys::window()
        .map(|window| window.device_pixel_ratio())
        .unwrap_or(1.0);
    format!("{:.0}%", ratio * 100.0)
}

async fn delay_ms(milliseconds: i32) {
    let promise = Promise::new(&mut |resolve, _reject| {
        let callback = Closure::once_into_js(move || {
            let _ = resolve.call0(&JsValue::UNDEFINED);
        });
        if let Some(window) = web_sys::window() {
            let _ = window.set_timeout_with_callback_and_timeout_and_arguments_0(
                callback.unchecked_ref(),
                milliseconds,
            );
        }
    });
    let _ = JsFuture::from(promise).await;
}

fn apply_document_state(ui: UiState, state: DocumentState) {
    if let Some(content) = state.content.clone() {
        ui.document_content.set(content);
    }
    ui.document_state.set(state);
}

fn show_document_error(ui: UiState, error: DocumentError) {
    let message = if error == DocumentError::DialogCancelled {
        "The document action was cancelled.".to_owned()
    } else {
        error.user_message()
    };
    ui.notice.set(Some(message));
}

fn confirm_discard_if_dirty(ui: UiState, action: &str) -> bool {
    if !ui.document_state.get_untracked().dirty {
        return true;
    }
    web_sys::window()
        .and_then(|window| {
            window
                .confirm_with_message(&format!(
                    "This document has unsaved changes. {action} and discard them?"
                ))
                .ok()
        })
        .unwrap_or(false)
}

fn start_document_switch(ui: UiState, command: &'static str) {
    let args = match serde_wasm_bindgen::to_value(&DocumentSwitchInvokeArgs {
        discard_changes: true,
    }) {
        Ok(args) => args,
        Err(_) => {
            show_document_error(ui, DocumentError::ReadFailed);
            return;
        }
    };
    spawn_local(async move {
        match invoke_document::<DocumentState>(command, args).await {
            Ok(state) => apply_document_state(ui, state),
            Err(error) => show_document_error(ui, error),
        }
    });
}

fn schedule_content_update(ui: UiState, content: String) {
    ui.edit_ticket
        .update(|ticket| *ticket = ticket.saturating_add(1));
    let ticket = ui.edit_ticket.get_untracked();
    spawn_local(async move {
        delay_ms(CONTENT_UPDATE_DEBOUNCE_MS).await;
        if ui.edit_ticket.get_untracked() != ticket {
            return;
        }
        let args = match serde_wasm_bindgen::to_value(&UpdateDocumentContentInvokeArgs { content })
        {
            Ok(args) => args,
            Err(_) => {
                show_document_error(ui, DocumentError::ReadFailed);
                return;
            }
        };
        match invoke_document::<DocumentState>("update_document_content", args).await {
            Ok(state) => {
                apply_document_state(ui, state);
                schedule_document_autosave(ui, ticket);
            }
            Err(error) => show_document_error(ui, error),
        }
    });
}

fn schedule_document_autosave(ui: UiState, ticket: u64) {
    spawn_local(async move {
        delay_ms(AUTOSAVE_DEBOUNCE_MS).await;
        if ui.edit_ticket.get_untracked() != ticket {
            return;
        }

        let state = ui.document_state.get_untracked();
        if state.path.is_none()
            || !state.dirty
            || matches!(
                state.status,
                DocumentStatus::Conflict
                    | DocumentStatus::Missing
                    | DocumentStatus::ExternallyRenamed
                    | DocumentStatus::ExternalChanged
                    | DocumentStatus::Saving
            )
        {
            return;
        }

        match invoke_document_without_args::<DocumentState>("save_document").await {
            Ok(state) => apply_document_state(ui, state),
            Err(DocumentError::SaveInProgress) => {}
            Err(error) => show_document_error(ui, error),
        }
    });
}

fn start_document_poll(ui: UiState) {
    spawn_local(async move {
        loop {
            delay_ms(500).await;
            let known = ui.document_state.get_untracked().memory_generation;
            match request_document_state(Some(known)).await {
                Ok(state) => apply_document_state(ui, state),
                Err(DocumentError::DialogCancelled) => {}
                Err(DocumentError::ReadFailed) => {}
                Err(error) => show_document_error(ui, error),
            }
        }
    });
}

#[component]
pub fn App() -> impl IntoView {
    let (bridge_state, set_bridge_state) = signal(BridgeState::Loading);
    let initial_document = DocumentState::untitled();
    let ui = UiState {
        mode: RwSignal::new(WorkspaceMode::default()),
        theme: RwSignal::new(ThemePreference::default()),
        sidebar_visible: RwSignal::new(true),
        sidebar_width: RwSignal::new(SIDEBAR_DEFAULT_WIDTH),
        resize_start: RwSignal::new(None),
        notice: RwSignal::new(None),
        document_content: RwSignal::new(initial_document.content.clone().unwrap_or_default()),
        document_state: RwSignal::new(initial_document),
        edit_ticket: RwSignal::new(0),
    };

    spawn_local(async move {
        set_bridge_state.set(match request_app_info().await {
            Ok(info) => BridgeState::Ready(info),
            Err(error) => BridgeState::Failed(error),
        });
    });

    spawn_local(async move {
        if let Ok(state) = request_document_state(None).await {
            apply_document_state(ui, state);
        }
    });
    start_document_poll(ui);

    let handle_workspace_mousemove = move |event: MouseEvent| {
        if let Some(start) = ui.resize_start.get() {
            let delta = start.start_x - f64::from(event.client_x());
            let width = clamp_sidebar_width((start.start_width + delta).round() as i32);
            ui.sidebar_width.set(width);
        }
    };

    view! {
        <main
            class=move || format!("app-shell theme-{}", ui.theme.get().css_value())
            data-theme=move || ui.theme.get().css_value()
            dir="ltr"
            aria-labelledby="app-title"
        >
            <div class="app-frame">
                <TopBar ui=ui bridge_state=bridge_state />
                <WorkspaceToolbar ui=ui />

                <div
                    class="workspace-layout has-sidebar"
                    style=("grid-template-columns", move || {
                        let width = ui.sidebar_width.get();
                        if ui.sidebar_visible.get() {
                            format!("minmax(0, 1fr) 18px {width}px")
                        } else {
                            "minmax(0, 1fr)".to_owned()
                        }
                    })
                    on:mousemove=handle_workspace_mousemove
                    on:mouseup=move |_| ui.resize_start.set(None)
                    on:mouseleave=move |_| ui.resize_start.set(None)
                >
                    <WorkspaceSurface ui=ui />
                    <ResizableSplitter ui=ui />
                    <AiSidebar ui=ui />
                </div>

                <StatusArea ui=ui bridge_state=bridge_state scale_label=device_scale_label() />
            </div>
        </main>
    }
}

#[component]
fn TopBar(ui: UiState, bridge_state: ReadSignal<BridgeState>) -> impl IntoView {
    view! {
        <header class="top-bar">
            <div class="brand-lockup">
                <div class="brand-mark" aria-hidden="true">"M"</div>
                <div class="brand-copy">
                    <h1 id="app-title">{PRODUCT_NAME}</h1>
                    <span class="brand-context">"Windows document workspace"</span>
                </div>
            </div>

            <nav class="primary-actions" aria-label="Primary document actions">
                <button
                    class="button button-subtle"
                    type="button"
                    aria-label="New document"
                    title="Create a new untitled Markdown document"
                    on:click=move |_| {
                        if !confirm_discard_if_dirty(ui, "Create a new document") { return; }
                        start_document_switch(ui, "new_document");
                    }
                >
                    <span class="button-glyph" aria-hidden="true">"+"</span>
                    <span class="button-label">"New"</span>
                </button>
                <button
                    class="button button-subtle"
                    type="button"
                    aria-label="Open document"
                    title="Open an existing .md or .mmd file"
                    on:click=move |_| {
                        if !confirm_discard_if_dirty(ui, "Open another document") { return; }
                        start_document_switch(ui, "open_document");
                    }
                >
                    <span class="button-glyph" aria-hidden="true">"↗"</span>
                    <span class="button-label">"Open"</span>
                </button>
                <button
                    class="button button-subtle"
                    type="button"
                    aria-label="Save document"
                    title="Save the current document safely"
                    on:click=move |_| {
                        let command = if ui.document_state.get_untracked().path.is_some() { "save_document" } else { "save_document_as" };
                        spawn_local(async move {
                            match invoke_document_without_args::<DocumentState>(command).await {
                                Ok(state) => apply_document_state(ui, state),
                                Err(error) => show_document_error(ui, error),
                            }
                        });
                    }
                >
                    <span class="button-glyph" aria-hidden="true">"↓"</span>
                    <span class="button-label">"Save"</span>
                </button>
                <button
                    class="button button-subtle"
                    type="button"
                    aria-label="Save document as"
                    title="Choose a new .md or .mmd path"
                    on:click=move |_| {
                        spawn_local(async move {
                            match invoke_document_without_args::<DocumentState>("save_document_as").await {
                                Ok(state) => apply_document_state(ui, state),
                                Err(error) => show_document_error(ui, error),
                            }
                        });
                    }
                >
                    <span class="button-glyph" aria-hidden="true">"⇥"</span>
                    <span class="button-label">"Save As"</span>
                </button>
                <button
                    class="button button-subtle"
                    type="button"
                    aria-label="Reload document from disk"
                    title="Reload the current document from disk"
                    prop:disabled=move || {
                        let state = ui.document_state.get();
                        state.path.is_none()
                            || matches!(
                                state.status,
                                DocumentStatus::Untitled
                                    | DocumentStatus::Missing
                                    | DocumentStatus::ExternallyRenamed
                            )
                    }
                    on:click=move |_| {
                        if !confirm_discard_if_dirty(ui, "Reload from disk") { return; }
                        spawn_local(async move {
                            match invoke_document_without_args::<DocumentState>("reload_document").await {
                                Ok(state) => apply_document_state(ui, state),
                                Err(error) => show_document_error(ui, error),
                            }
                        });
                    }
                >
                    <span class="button-glyph" aria-hidden="true">"↻"</span>
                    <span class="button-label">"Reload"</span>
                </button>
            </nav>

            <div class="top-bar-spacer"></div>

            <div class="top-bar-controls">
                <ThemeControl ui=ui />
                <span class="bridge-chip" aria-live="polite">
                    {move || match bridge_state.get() {
                        BridgeState::Loading => "Connecting".to_owned(),
                        BridgeState::Ready(info) => format!("Native bridge · {}", info.version.as_str()),
                        BridgeState::Failed(_) => "Bridge unavailable".to_owned(),
                    }}
                </span>
                <button
                    class="button button-accent"
                    type="button"
                    aria-controls="ai-sidebar"
                    aria-label="Toggle AI Assistant sidebar"
                    aria-pressed=move || ui.sidebar_visible.get().to_string()
                    on:click=move |_| ui.sidebar_visible.update(|visible| *visible = !*visible)
                >
                    <span class="button-glyph" aria-hidden="true">"✦"</span>
                    <span class="button-label">"AI Assistant"</span>
                </button>
            </div>
        </header>
    }
}

#[component]
fn ThemeControl(ui: UiState) -> impl IntoView {
    view! {
        <label class="theme-control">
            <span class="sr-only">"Theme preference"</span>
            <span class="theme-icon" aria-hidden="true">"◐"</span>
            <select
                aria-label="Theme preference"
                prop:value=move || ui.theme.get().css_value()
                on:change=move |event| {
                    ui.theme.set(match event_target_value(&event).as_str() {
                        "light" => ThemePreference::Light,
                        "dark" => ThemePreference::Dark,
                        _ => ThemePreference::System,
                    });
                }
            >
                <option value="system">"System"</option>
                <option value="light">"Light"</option>
                <option value="dark">"Dark"</option>
            </select>
        </label>
    }
}

#[component]
fn WorkspaceToolbar(ui: UiState) -> impl IntoView {
    view! {
        <div class="workspace-toolbar">
            <div class="workspace-context" aria-label="Current document">
                <span class="context-eyebrow">"DOCUMENT"</span>
                <span class="context-title">{move || ui.document_state.get().file_name}</span>
            </div>
            <ModeSwitcher ui=ui />
            <div class="document-toolbar-status" aria-live="polite">
                <span class="status-dot" aria-hidden="true"></span>
                <span>{move || ui.document_state.get().status.label()}</span>
            </div>
        </div>
    }
}

#[component]
fn ModeSwitcher(ui: UiState) -> impl IntoView {
    view! {
        <div class="mode-switcher" role="tablist" aria-label="Lifecycle text surface mode">
            <ModeTab ui=ui mode=WorkspaceMode::Preview />
            <ModeTab ui=ui mode=WorkspaceMode::Editor />
            <ModeTab ui=ui mode=WorkspaceMode::Source />
        </div>
    }
}

#[component]
fn ModeTab(ui: UiState, mode: WorkspaceMode) -> impl IntoView {
    view! {
        <button
            class=move || if ui.mode.get() == mode { "mode-tab is-selected" } else { "mode-tab" }
            type="button"
            role="tab"
            id=move || format!("mode-tab-{}", mode.label().to_ascii_lowercase())
            aria-controls="document-workspace"
            aria-selected=move || (ui.mode.get() == mode).to_string()
            tabindex=move || if ui.mode.get() == mode { "0" } else { "-1" }
            on:click=move |_| ui.mode.set(mode)
            on:keydown=move |event| {
                let next = match event.key().as_str() {
                    "ArrowRight" | "ArrowDown" => Some(mode.next()),
                    "ArrowLeft" | "ArrowUp" => Some(mode.previous()),
                    "Home" => Some(WorkspaceMode::Preview),
                    "End" => Some(WorkspaceMode::Source),
                    _ => None,
                };
                if let Some(next_mode) = next {
                    event.prevent_default();
                    ui.mode.set(next_mode);
                }
            }
        >
            {mode.label()}
        </button>
    }
}

#[component]
fn WorkspaceSurface(ui: UiState) -> impl IntoView {
    view! {
        <section
            class="document-workspace"
            id="document-workspace"
            role="tabpanel"
            aria-label="Document workspace"
            tabindex="0"
        >
            <div class="document-placeholder">
                <DocumentHeader ui=ui />
                <div
                    class="document-content"
                    dir=move || if has_persian(&ui.document_content.get()) { "auto" } else { "ltr" }
                    lang=move || if has_persian(&ui.document_content.get()) { "fa" } else { "en" }
                >
                    <LifecycleTextSurface ui=ui />
                </div>
            </div>
        </section>
    }
}

#[component]
fn DocumentHeader(ui: UiState) -> impl IntoView {
    view! {
        <header class="document-header">
            <div>
                <span class="document-kicker">"PHASE 3 · FILESYSTEM-BACKED DOCUMENT"</span>
                <h2>{move || ui.document_state.get().file_name}</h2>
            </div>
            <span class="document-status" aria-live="polite">
                {move || ui.document_state.get().status.label()}
            </span>
        </header>
    }
}

fn has_persian(text: &str) -> bool {
    text.chars().any(|character| {
        matches!(character, '\u{0600}'..='\u{06FF}' | '\u{0750}'..='\u{077F}' | '\u{08A0}'..='\u{08FF}')
    })
}

#[component]
fn LifecycleTextSurface(ui: UiState) -> impl IntoView {
    view! {
        <article class="lifecycle-surface">
            <div class="placeholder-heading">
                <span class="mode-icon" aria-hidden="true">"✎"</span>
                <div>
                    <span class="mode-kicker">"PHASE 3 LIFECYCLE SURFACE"</span>
                    <h3>{move || format!("{} text · {}", ui.mode.get().label(), ui.mode.get().description())}</h3>
                </div>
            </div>
            <p class="lifecycle-help">
                "A deliberately plain text surface for document lifecycle validation. The full Source Editor is reserved for Phase 4."
            </p>
            <textarea
                class="lifecycle-textarea"
                aria-label="Markdown document text"
                spellcheck="false"
                prop:value=move || ui.document_content.get()
                on:input=move |event| {
                    let content = event_target_value(&event);
                    ui.document_content.set(content.clone());
                    schedule_content_update(ui, content);
                }
            ></textarea>
            <div class="lifecycle-meta" aria-live="polite">
                <span>{move || format!("{} · revision {}", ui.document_state.get().status.label(), ui.document_state.get().memory_generation)}</span>
                <span>{move || format!("{} · {}", ui.document_state.get().encoding.label(), ui.document_state.get().newline_style.label())}</span>
            </div>
        </article>
    }
}

#[component]
fn ResizableSplitter(ui: UiState) -> impl IntoView {
    view! {
        <div
            class="splitter-hit-area"
            role="separator"
            aria-hidden=move || (!ui.sidebar_visible.get()).to_string()
            aria-label="Resize AI Assistant sidebar"
            style=move || if ui.sidebar_visible.get() { "" } else { "display: none" }
            aria-orientation="vertical"
            aria-valuemin=SIDEBAR_MIN_WIDTH.to_string()
            aria-valuemax=SIDEBAR_MAX_WIDTH.to_string()
            aria-valuenow=move || ui.sidebar_width.get().to_string()
            tabindex="0"
            on:mousedown=move |event| {
                event.prevent_default();
                ui.resize_start.set(Some(ResizeStart {
                    start_x: f64::from(event.client_x()),
                    start_width: f64::from(ui.sidebar_width.get()),
                }));
            }
            on:keydown=move |event| {
                let current = i32::from(ui.sidebar_width.get());
                let next = match event.key().as_str() {
                    "ArrowLeft" => Some(clamp_sidebar_width(current + 16)),
                    "ArrowRight" => Some(clamp_sidebar_width(current - 16)),
                    "Home" => Some(SIDEBAR_MIN_WIDTH),
                    "End" => Some(SIDEBAR_MAX_WIDTH),
                    _ => None,
                };
                if let Some(width) = next {
                    event.prevent_default();
                    ui.sidebar_width.set(width);
                }
            }
        >
            <span class="splitter-grip" aria-hidden="true">"⋮"</span>
        </div>
    }
}

#[component]
fn AiSidebar(ui: UiState) -> impl IntoView {
    view! {
        <aside
            class="assistant-sidebar"
            id="ai-sidebar"
            aria-hidden=move || (!ui.sidebar_visible.get()).to_string()
            aria-labelledby="ai-sidebar-title"
            style=move || if ui.sidebar_visible.get() { "" } else { "display: none" }
        >
            <header class="assistant-header">
                <div>
                    <span class="mode-kicker">"SIDE REGION"</span>
                    <h2 id="ai-sidebar-title">"AI Assistant"</h2>
                </div>
                <button
                    class="icon-button"
                    type="button"
                    aria-label="Hide AI Assistant sidebar"
                    title="Hide AI Assistant sidebar"
                    on:click=move |_| ui.sidebar_visible.set(false)
                >
                    <span aria-hidden="true">"×"</span>
                </button>
            </header>
            <div class="assistant-content">
                <div class="assistant-orb" aria-hidden="true">"✦"</div>
                <h3>"A thoughtful second pane"</h3>
                <p>"AI Assistant remains a later phase; document lifecycle safety is active here."</p>
                <div class="assistant-boundary">
                    <span class="status-dot" aria-hidden="true"></span>
                    <span>"No chat, provider, network, or secret access is active."</span>
                </div>
            </div>
            <footer class="assistant-footer">
                <span>"Resizable pane"</span>
                <span>{move || format!("{} px", ui.sidebar_width.get())}</span>
            </footer>
        </aside>
    }
}

#[component]
fn StatusArea(
    ui: UiState,
    bridge_state: ReadSignal<BridgeState>,
    scale_label: String,
) -> impl IntoView {
    view! {
        <footer class="status-area" aria-live="polite">
            <div class="status-message">
                <span class="status-dot" aria-hidden="true"></span>
                <span>
                    {move || match bridge_state.get() {
                        BridgeState::Loading => "Connecting to the native shell…".to_owned(),
                        BridgeState::Ready(_) => format!("Document lifecycle active · {}", ui.document_state.get().status.label()),
                        BridgeState::Failed(error) => error.message,
                    }}
                </span>
            </div>
            <Show when=move || ui.notice.get().is_some()>
                <div class="status-notice" role="status">
                    {move || ui.notice.get().unwrap_or_default()}
                </div>
            </Show>
            <Show when=move || ui.document_state.get().message.is_some()>
                <div class="status-notice" role="alert">
                    {move || ui.document_state.get().message.unwrap_or_default()}
                </div>
            </Show>
            <div class="status-metrics" aria-label="Document metrics">
                <span>{move || format!("{} · {}", ui.document_state.get().file_name, ui.document_state.get().status.label())}</span>
                <span>{move || if ui.document_state.get().dirty { "Unsaved" } else { "Clean" }}</span>
                <span>{format!("WebView scale {}", scale_label)}</span>
            </div>
        </footer>
    }
}
