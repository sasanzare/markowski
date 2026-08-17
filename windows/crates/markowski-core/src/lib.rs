use std::fmt;

use serde::{Deserialize, Serialize};

pub const PRODUCT_NAME: &str = "Markowski";
pub const WINDOWS_PLATFORM: &str = "windows";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoreError {
    InvalidVersion,
}

impl fmt::Display for CoreError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidVersion => formatter.write_str("the application version is empty"),
        }
    }
}

impl std::error::Error for CoreError {}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppVersion(String);

impl AppVersion {
    pub fn parse(value: impl Into<String>) -> Result<Self, CoreError> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(CoreError::InvalidVersion);
        }

        Ok(Self(value))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppInfo {
    pub name: String,
    pub version: AppVersion,
    pub platform: String,
}

impl AppInfo {
    pub fn for_windows(version: impl Into<String>) -> Result<Self, CoreError> {
        Ok(Self {
            name: PRODUCT_NAME.to_owned(),
            version: AppVersion::parse(version)?,
            platform: WINDOWS_PLATFORM.to_owned(),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppInfoResponse {
    pub app: AppInfo,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AppInfoOperation {
    GetAppInfo,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppInfoRequest {
    pub operation: AppInfoOperation,
}

impl Default for AppInfoRequest {
    fn default() -> Self {
        Self {
            operation: AppInfoOperation::GetAppInfo,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IpcErrorCode {
    BridgeUnavailable,
    Initialization,
    InvalidRequest,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IpcError {
    pub code: IpcErrorCode,
    pub message: String,
}

impl IpcError {
    pub fn bridge_unavailable() -> Self {
        Self {
            code: IpcErrorCode::BridgeUnavailable,
            message: "The desktop bridge is unavailable.".to_owned(),
        }
    }

    pub fn initialization() -> Self {
        Self {
            code: IpcErrorCode::Initialization,
            message: "Markowski could not initialize its desktop bridge.".to_owned(),
        }
    }

    pub fn from_core(error: CoreError) -> Self {
        let message = match error {
            CoreError::InvalidVersion => "Markowski has an invalid application version.",
        };

        Self {
            code: IpcErrorCode::InvalidRequest,
            message: message.to_owned(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_info_has_stable_windows_identity() {
        let info = AppInfo::for_windows("0.1.0").expect("valid version");

        assert_eq!(info.name, PRODUCT_NAME);
        assert_eq!(info.version.as_str(), "0.1.0");
        assert_eq!(info.platform, WINDOWS_PLATFORM);
    }

    #[test]
    fn app_info_request_round_trips_through_json() {
        let request = AppInfoRequest::default();
        let encoded = serde_json::to_string(&request).expect("request serializes");
        let decoded: AppInfoRequest = serde_json::from_str(&encoded).expect("request decodes");

        assert_eq!(encoded, r#"{"operation":"get_app_info"}"#);
        assert_eq!(decoded, request);
    }

    #[test]
    fn invalid_version_maps_to_safe_ipc_error() {
        let error = AppInfo::for_windows(" ").expect_err("blank version is invalid");
        let ipc_error = IpcError::from_core(error);

        assert_eq!(ipc_error.code, IpcErrorCode::InvalidRequest);
        assert_eq!(
            ipc_error.message,
            "Markowski has an invalid application version."
        );
    }
}
