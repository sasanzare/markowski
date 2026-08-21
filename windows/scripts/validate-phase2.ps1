$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$uiRoot = Join-Path $workspaceRoot "apps\desktop-ui"
$shellRoot = Join-Path $workspaceRoot "apps\desktop-shell"
$configPath = Join-Path $shellRoot "tauri.conf.json"
$capabilityPath = Join-Path $shellRoot "capabilities\default.json"
$appPath = Join-Path $uiRoot "src\app.rs"
$cssPath = Join-Path $uiRoot "styles.css"
$indexPath = Join-Path $uiRoot "index.html"

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$capability = Get-Content -LiteralPath $capabilityPath -Raw | ConvertFrom-Json
$appSource = Get-Content -LiteralPath $appPath -Raw
$cssSource = Get-Content -LiteralPath $cssPath -Raw
$indexSource = Get-Content -LiteralPath $indexPath -Raw
$csp = [string]$config.app.security.csp

if ($csp -match "\*" -or $csp -match "https://" -or $csp -match "script-src[^;]*https:") {
    throw "Phase 2 CSP contains a wildcard or remote runtime origin."
}

if ($csp -notmatch "default-src 'self'" -or $csp -notmatch "script-src 'self' 'wasm-unsafe-eval'" -or $csp -notmatch "object-src 'none'") {
    throw "Phase 2 CSP does not contain the required restrictive directives."
}

$allowedPermissions = @(
    "core:app:default",
    "core:event:default",
    "core:resources:default",
    "core:window:default",
    "allow-get-app-info"
)
$permissions = @($capability.permissions | ForEach-Object { [string]$_ })
if ($permissions.Count -ne $allowedPermissions.Count -or @($permissions | Where-Object { $_ -notin $allowedPermissions }).Count -gt 0) {
    throw "Phase 2 changed the least-privilege capability allowlist."
}

if ($config.app.windows[0].minWidth -ne 900 -or $config.app.windows[0].minHeight -ne 600) {
    throw "The Phase 2 minimum window size is not the documented 900x600 DIP baseline."
}

if ($appSource -notmatch 'dir="ltr"' -or $indexSource -notmatch 'dir="ltr"') {
    throw "The application chrome must have an explicit LTR direction."
}

if ($appSource -match '<main[^>]*dir="rtl"' -or $appSource -match 'document\.dir\s*=\s*["'']rtl') {
    throw "The application root is globally forced to RTL."
}

if ($appSource -match 'https?://|//cdn\.' -or $cssSource -match 'url\(\s*["'']?https?://|@import') {
    throw "Phase 2 UI source contains a remote runtime asset reference."
}

foreach ($font in @(
    "IRANSansX-Regular.ttf",
    "IRANSansX-DemiBold.ttf",
    "IRANSansX-Bold.ttf",
    "IRANSansXFaNum-Regular.ttf"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $uiRoot "assets\fonts\$font"))) {
        throw "Bundled typography asset is missing: $font"
    }
}

# Phase 3 is now authorized. This validator remains a regression check for
# Phase 2 shell/CSP/layout invariants and must not reject lifecycle code.
if ($appSource -notmatch 'new_document|open_document|save_document') {
    throw "The Phase 3 lifecycle commands are not reachable from the UI shell."
}

Write-Output "Phase 2 regression validation: PASS"
