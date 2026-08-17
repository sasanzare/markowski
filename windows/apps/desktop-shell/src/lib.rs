use std::fmt;

use markowski_core::{AppInfo, AppInfoOperation, AppInfoRequest, AppInfoResponse, IpcError};
use tauri::State;
use tracing::{error, info};
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

struct AppState {
    app_info: AppInfo,
}

impl AppState {
    fn new(version: &str) -> Result<Self, ShellError> {
        let app_info = AppInfo::for_windows(version).map_err(|error| {
            error!(event = "core_initialization_failed", reason = ?error);
            ShellError::CoreInitialization
        })?;

        Ok(Self { app_info })
    }

    fn get_app_info(&self, request: AppInfoRequest) -> Result<AppInfoResponse, IpcError> {
        match request.operation {
            AppInfoOperation::GetAppInfo => Ok(AppInfoResponse {
                app: self.app_info.clone(),
            }),
        }
    }
}

fn default_log_filter() -> &'static str {
    if cfg!(debug_assertions) {
        "markowski_desktop_shell=debug,markowski_core=debug"
    } else {
        "markowski_desktop_shell=info,markowski_core=info"
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

#[tauri::command]
fn get_app_info(
    request: AppInfoRequest,
    state: State<'_, AppState>,
) -> Result<AppInfoResponse, IpcError> {
    state.get_app_info(request)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() -> Result<(), ShellError> {
    initialize_logging()?;

    let version = env!("CARGO_PKG_VERSION");
    let state = AppState::new(version)?;
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
        .setup(|_app| {
            info!(
                event = "initialization_complete",
                "desktop shell initialized"
            );
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![get_app_info])
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
        assert!(filter.contains("markowski_core"));
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
}
