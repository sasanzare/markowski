use js_sys::Promise;
use leptos::prelude::*;
use leptos::task::spawn_local;
use markowski_core::{AppInfo, AppInfoRequest, AppInfoResponse, IpcError, PRODUCT_NAME};
use serde::Serialize;
use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::JsFuture;

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

#[component]
pub fn App() -> impl IntoView {
    let (bridge_state, set_bridge_state) = signal(BridgeState::Loading);

    spawn_local(async move {
        set_bridge_state.set(match request_app_info().await {
            Ok(info) => BridgeState::Ready(info),
            Err(error) => BridgeState::Failed(error),
        });
    });

    view! {
        <main class="shell">
            <h1>{PRODUCT_NAME}</h1>
            <p class="subtitle">"Windows Development Build"</p>
            <section class="status-card" aria-live="polite" aria-label="Application status">
                {move || match bridge_state.get() {
                    BridgeState::Loading => view! {
                        <p class="status-label">"Connecting to the native shell…"</p>
                    }.into_any(),
                    BridgeState::Ready(info) => view! {
                        <p class="status-label">"Native bridge connected"</p>
                        <dl class="app-info">
                            <dt>"Version"</dt>
                            <dd>{info.version.as_str().to_owned()}</dd>
                            <dt>"Platform"</dt>
                            <dd>{info.platform}</dd>
                        </dl>
                    }.into_any(),
                    BridgeState::Failed(error) => view! {
                        <p class="status-label">"Desktop bridge unavailable"</p>
                        <p>{error.message}</p>
                    }.into_any(),
                }}
            </section>
        </main>
    }
}
