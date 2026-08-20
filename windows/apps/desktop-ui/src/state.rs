use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum WorkspaceMode {
    #[default]
    Preview,
    Editor,
    Source,
}

impl WorkspaceMode {
    pub const fn label(self) -> &'static str {
        match self {
            Self::Preview => "Preview",
            Self::Editor => "Editor",
            Self::Source => "Source",
        }
    }

    pub const fn description(self) -> &'static str {
        match self {
            Self::Preview => "Rendered preview foundation",
            Self::Editor => "Visual editor foundation",
            Self::Source => "Markdown source foundation",
        }
    }

    pub const fn next(self) -> Self {
        match self {
            Self::Preview => Self::Editor,
            Self::Editor => Self::Source,
            Self::Source => Self::Preview,
        }
    }

    pub const fn previous(self) -> Self {
        match self {
            Self::Preview => Self::Source,
            Self::Editor => Self::Preview,
            Self::Source => Self::Editor,
        }
    }
}

impl fmt::Display for WorkspaceMode {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.label())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ThemePreference {
    #[default]
    System,
    Light,
    Dark,
}

impl ThemePreference {
    pub const fn label(self) -> &'static str {
        match self {
            Self::System => "System",
            Self::Light => "Light",
            Self::Dark => "Dark",
        }
    }

    pub const fn css_value(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::Light => "light",
            Self::Dark => "dark",
        }
    }
}

impl fmt::Display for ThemePreference {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.label())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum WorkspaceFixture {
    #[default]
    Empty,
    DocumentPlaceholder,
    PersianDocument,
    MixedDirectionDocument,
}

impl WorkspaceFixture {
    pub const fn label(self) -> &'static str {
        match self {
            Self::Empty => "No document",
            Self::DocumentPlaceholder => "Document placeholder",
            Self::PersianDocument => "Persian fixture",
            Self::MixedDirectionDocument => "Mixed RTL/LTR fixture",
        }
    }

    pub const fn value(self) -> &'static str {
        match self {
            Self::Empty => "empty",
            Self::DocumentPlaceholder => "document",
            Self::PersianDocument => "persian",
            Self::MixedDirectionDocument => "mixed",
        }
    }

    pub fn from_value(value: &str) -> Self {
        match value {
            "document" => Self::DocumentPlaceholder,
            "persian" => Self::PersianDocument,
            "mixed" => Self::MixedDirectionDocument,
            _ => Self::Empty,
        }
    }

    pub const fn has_document(self) -> bool {
        !matches!(self, Self::Empty)
    }

    pub const fn content_direction(self) -> &'static str {
        match self {
            Self::PersianDocument | Self::MixedDirectionDocument => "rtl",
            Self::Empty | Self::DocumentPlaceholder => "ltr",
        }
    }
}

pub const SIDEBAR_MIN_WIDTH: u16 = 280;
pub const SIDEBAR_DEFAULT_WIDTH: u16 = 336;
pub const SIDEBAR_MAX_WIDTH: u16 = 520;

pub const fn clamp_sidebar_width(width: i32) -> u16 {
    if width < SIDEBAR_MIN_WIDTH as i32 {
        SIDEBAR_MIN_WIDTH
    } else if width > SIDEBAR_MAX_WIDTH as i32 {
        SIDEBAR_MAX_WIDTH
    } else {
        width as u16
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ResizeStart {
    pub start_x: f64,
    pub start_width: f64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workspace_modes_have_stable_keyboard_order() {
        assert_eq!(WorkspaceMode::Preview.next(), WorkspaceMode::Editor);
        assert_eq!(WorkspaceMode::Editor.next(), WorkspaceMode::Source);
        assert_eq!(WorkspaceMode::Source.next(), WorkspaceMode::Preview);
        assert_eq!(WorkspaceMode::Preview.previous(), WorkspaceMode::Source);
    }

    #[test]
    fn theme_preferences_have_stable_css_values() {
        assert_eq!(ThemePreference::System.css_value(), "system");
        assert_eq!(ThemePreference::Light.css_value(), "light");
        assert_eq!(ThemePreference::Dark.css_value(), "dark");
    }

    #[test]
    fn fixture_direction_is_local_to_document_content() {
        assert!(!WorkspaceFixture::Empty.has_document());
        assert_eq!(WorkspaceFixture::PersianDocument.content_direction(), "rtl");
        assert_eq!(
            WorkspaceFixture::MixedDirectionDocument.content_direction(),
            "rtl"
        );
        assert_eq!(
            WorkspaceFixture::DocumentPlaceholder.content_direction(),
            "ltr"
        );
    }

    #[test]
    fn sidebar_width_is_clamped_to_safe_constraints() {
        assert_eq!(clamp_sidebar_width(0), SIDEBAR_MIN_WIDTH);
        assert_eq!(clamp_sidebar_width(336), SIDEBAR_DEFAULT_WIDTH);
        assert_eq!(clamp_sidebar_width(999), SIDEBAR_MAX_WIDTH);
    }
}
