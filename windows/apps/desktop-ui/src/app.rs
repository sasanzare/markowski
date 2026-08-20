use js_sys::Promise;
use leptos::prelude::*;
use leptos::task::spawn_local;
use markowski_core::{AppInfo, AppInfoRequest, AppInfoResponse, IpcError, PRODUCT_NAME};
use serde::Serialize;
use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::JsFuture;
use web_sys::MouseEvent;

use crate::state::{
    clamp_sidebar_width, ResizeStart, ThemePreference, WorkspaceFixture, WorkspaceMode,
    SIDEBAR_DEFAULT_WIDTH, SIDEBAR_MAX_WIDTH, SIDEBAR_MIN_WIDTH,
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
    fixture: RwSignal<WorkspaceFixture>,
    sidebar_visible: RwSignal<bool>,
    sidebar_width: RwSignal<u16>,
    resize_start: RwSignal<Option<ResizeStart>>,
    notice: RwSignal<Option<String>>,
}

#[derive(Serialize)]
struct GetAppInfoInvokeArgs {
    request: AppInfoRequest,
}

fn decode_bridge_error(error: JsValue) -> IpcError {
    serde_wasm_bindgen::from_value(error).unwrap_or_else(|_| IpcError::bridge_unavailable())
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

fn device_scale_label() -> String {
    let ratio = web_sys::window()
        .map(|window| window.device_pixel_ratio())
        .unwrap_or(1.0);
    format!("{:.0}%", ratio * 100.0)
}

#[component]
pub fn App() -> impl IntoView {
    let (bridge_state, set_bridge_state) = signal(BridgeState::Loading);
    let ui = UiState {
        mode: RwSignal::new(WorkspaceMode::default()),
        theme: RwSignal::new(ThemePreference::default()),
        fixture: RwSignal::new(WorkspaceFixture::default()),
        sidebar_visible: RwSignal::new(true),
        sidebar_width: RwSignal::new(SIDEBAR_DEFAULT_WIDTH),
        resize_start: RwSignal::new(None),
        notice: RwSignal::new(None),
    };

    spawn_local(async move {
        set_bridge_state.set(match request_app_info().await {
            Ok(info) => BridgeState::Ready(info),
            Err(error) => BridgeState::Failed(error),
        });
    });

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
                    <span class="brand-context">"Windows workspace shell"</span>
                </div>
            </div>

            <nav class="primary-actions" aria-label="Primary document actions">
                <button
                    class="button button-subtle"
                    type="button"
                    aria-label="New document placeholder"
                    title="Document creation begins in Phase 3"
                    on:click=move |_| ui.notice.set(Some(
                        "New document is a Phase 3 placeholder; no filesystem access is active in Phase 2.".to_owned(),
                    ))
                >
                    <span class="button-glyph" aria-hidden="true">"+"</span>
                    <span class="button-label">"New"</span>
                </button>
                <button
                    class="button button-subtle"
                    type="button"
                    aria-label="Open document placeholder"
                    title="Document opening begins in Phase 3"
                    on:click=move |_| ui.notice.set(Some(
                        "Open document is a Phase 3 placeholder; this shell does not read files.".to_owned(),
                    ))
                >
                    <span class="button-glyph" aria-hidden="true">"↗"</span>
                    <span class="button-label">"Open"</span>
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
            <div class="workspace-context" aria-label="Workspace context">
                <span class="context-eyebrow">"WORKSPACE"</span>
                <span class="context-title">"Untitled local fixture"</span>
            </div>
            <ModeSwitcher ui=ui />
            <FixtureControl ui=ui />
        </div>
    }
}

#[component]
fn ModeSwitcher(ui: UiState) -> impl IntoView {
    view! {
        <div class="mode-switcher" role="tablist" aria-label="Workspace mode">
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
fn FixtureControl(ui: UiState) -> impl IntoView {
    view! {
        <label class="fixture-control">
            <span class="fixture-label">"Phase 2 fixture"</span>
            <select
                aria-label="Phase 2 UI fixture"
                title="Deterministic UI-only fixture; it never opens a file"
                prop:value=move || ui.fixture.get().value()
                on:change=move |event| ui.fixture.set(WorkspaceFixture::from_value(&event_target_value(&event)))
            >
                <option value="empty">"No document"</option>
                <option value="document">"Document placeholder"</option>
                <option value="persian">"Persian fixture"</option>
                <option value="mixed">"Mixed RTL/LTR fixture"</option>
            </select>
        </label>
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
            {move || match ui.fixture.get() {
                WorkspaceFixture::Empty => view! { <EmptyState ui=ui /> }.into_any(),
                fixture => view! {
                    <div class="document-placeholder">
                        <DocumentHeader fixture=fixture />
                        <div
                            class="document-content"
                            dir=fixture.content_direction()
                            lang=if fixture.content_direction() == "rtl" { "fa" } else { "en" }
                        >
                            {move || match ui.mode.get() {
                                WorkspaceMode::Preview => mode_placeholder(ui.fixture.get(), WorkspaceMode::Preview),
                                WorkspaceMode::Editor => mode_placeholder(ui.fixture.get(), WorkspaceMode::Editor),
                                WorkspaceMode::Source => mode_placeholder(ui.fixture.get(), WorkspaceMode::Source),
                            }}
                        </div>
                    </div>
                }.into_any(),
            }}
        </section>
    }
}

#[component]
fn DocumentHeader(fixture: WorkspaceFixture) -> impl IntoView {
    view! {
        <header class="document-header">
            <div>
                <span class="document-kicker">"PHASE 2 UI FIXTURE · NOT PERSISTED"</span>
                <h2>{fixture.label()}</h2>
            </div>
            <span class="document-status">"Local only"</span>
        </header>
    }
}

#[component]
fn EmptyState(ui: UiState) -> impl IntoView {
    view! {
        <div class="empty-state">
            <div class="empty-mark" aria-hidden="true">"M"</div>
            <span class="document-kicker">"MARKOWSKI WINDOWS"</span>
            <h2>"A calm place for your next document"</h2>
            <p>
                "The workspace is ready. Phase 2 only provides the desktop shell; file opening and document editing arrive in Phase 3."
            </p>
            <div class="empty-actions" aria-label="Document placeholders">
                <button
                    class="button button-primary"
                    type="button"
                    on:click=move |_| ui.notice.set(Some(
                        "New document is a Phase 3 placeholder; no filesystem access is active in Phase 2.".to_owned(),
                    ))
                >
                    <span class="button-glyph" aria-hidden="true">"+"</span>
                    <span>"New document"</span>
                </button>
                <button
                    class="button button-outline"
                    type="button"
                    on:click=move |_| ui.notice.set(Some(
                        "Open document is a Phase 3 placeholder; this workspace stays local and deterministic.".to_owned(),
                    ))
                >
                    <span class="button-glyph" aria-hidden="true">"↗"</span>
                    <span>"Open document"</span>
                </button>
            </div>
            <p class="empty-note">"No document data is read, written, watched, or persisted in this state."</p>
        </div>
    }
}

fn mode_placeholder(fixture: WorkspaceFixture, mode: WorkspaceMode) -> AnyView {
    let source = match fixture {
        WorkspaceFixture::PersianDocument => "سلام، این یک سند فارسی برای آزمایش Markowski است.",
        WorkspaceFixture::MixedDirectionDocument => {
            "برای اجرای cargo test از ترمینال استفاده کنید."
        }
        WorkspaceFixture::DocumentPlaceholder => {
            "# Untitled Markdown fixture\n\nPhase 2 keeps document behavior stubbed."
        }
        WorkspaceFixture::Empty => "",
    };

    match mode {
        WorkspaceMode::Preview => view! {
            <article class="mode-placeholder preview-placeholder">
                <div class="placeholder-heading">
                    <span class="mode-icon" aria-hidden="true">"◈"</span>
                    <div>
                        <span class="mode-kicker">"PREVIEW FOUNDATION"</span>
                        <h3>"Rendered workspace placeholder"</h3>
                    </div>
                </div>
                <p>{mode.description()} " · This panel reserves the future local Markdown renderer surface."</p>
                <FixtureContent fixture=fixture />
            </article>
        }
        .into_any(),
        WorkspaceMode::Editor => view! {
            <article class="mode-placeholder editor-placeholder">
                <div class="placeholder-heading">
                    <span class="mode-icon" aria-hidden="true">"✦"</span>
                    <div>
                        <span class="mode-kicker">"EDITOR FOUNDATION"</span>
                        <h3>"Visual editor placeholder"</h3>
                    </div>
                </div>
                <p>{mode.description()} " · The future semantic editor will live here without changing the source authority."</p>
                <div class="editor-blocks" aria-label="Editor block placeholders">
                    <div class="editor-block editor-block-heading">"Heading block"</div>
                    <div class="editor-block">"Paragraph block with stable spacing"</div>
                    <div class="editor-block editor-block-code">"Code block placeholder"</div>
                </div>
                <FixtureContent fixture=fixture />
            </article>
        }
        .into_any(),
        WorkspaceMode::Source => view! {
            <article class="mode-placeholder source-placeholder">
                <div class="placeholder-heading">
                    <span class="mode-icon" aria-hidden="true">"‹/›"</span>
                    <div>
                        <span class="mode-kicker">"SOURCE FOUNDATION"</span>
                        <h3>"Markdown source placeholder"</h3>
                    </div>
                </div>
                <p>{mode.description()} " · Source remains the future document authority; editing is intentionally not active yet."</p>
                <pre class="source-code" dir="ltr"><code>{source}</code></pre>
                <FixtureContent fixture=fixture />
            </article>
        }
        .into_any(),
    }
}

#[component]
fn FixtureContent(fixture: WorkspaceFixture) -> impl IntoView {
    match fixture {
        WorkspaceFixture::DocumentPlaceholder => view! {
            <div class="fixture-copy" dir="ltr">
                <p>"This is a deterministic document-open placeholder."</p>
                <p>"It exposes the future workspace without reading a real file."</p>
                <p class="inline-note"><code dir="ltr">"Phase 3"</code> " owns document lifecycle."</p>
            </div>
        }
        .into_any(),
        WorkspaceFixture::PersianDocument => view! {
            <div class="fixture-copy" dir="rtl" lang="fa">
                <p>"سلام، این یک سند فارسی برای آزمایش Markowski است."</p>
                <p>"نسخه " <bdi dir="ltr">"0.1.0"</bdi> " روی " <bdi dir="ltr">"Windows"</bdi> " اجرا می‌شود."</p>
                <p class="inline-note">"متن سند جهت محلی دارد و پوسته‌ی برنامه همچنان چپ‌به‌راست است."</p>
            </div>
        }
        .into_any(),
        WorkspaceFixture::MixedDirectionDocument => view! {
            <div class="fixture-copy" dir="rtl" lang="fa">
                <p>"برای اجرای " <code dir="ltr">"cargo test"</code> " از ترمینال استفاده کنید."</p>
                <p>"نسخه " <bdi dir="ltr">"0.1.0"</bdi> " روی " <bdi dir="ltr">"Windows"</bdi> " اجرا می‌شود."</p>
                <p class="inline-note">"کد، اعداد و برچسب‌های انگلیسی با bidi isolation خوانا می‌مانند."</p>
            </div>
        }
        .into_any(),
        WorkspaceFixture::Empty => view! { <div></div> }.into_any(),
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
                <p>"AI Assistant becomes available in a later phase."</p>
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
                        BridgeState::Ready(_) => "Native bridge connected · local UI state only".to_owned(),
                        BridgeState::Failed(error) => error.message,
                    }}
                </span>
            </div>
            <Show when=move || ui.notice.get().is_some()>
                <div class="status-notice" role="status">
                    {move || ui.notice.get().unwrap_or_default()}
                </div>
            </Show>
            <div class="status-metrics" aria-label="Workspace metrics">
                <span>{move || format!("{} · {} mode", if ui.fixture.get().has_document() { "Document" } else { "Empty" }, ui.mode.get())}</span>
                <span>{move || format!("{} · {} px", if ui.sidebar_visible.get() { "AI on" } else { "AI off" }, ui.sidebar_width.get())}</span>
                <span>{format!("WebView scale {}", scale_label)}</span>
            </div>
        </footer>
    }
}
