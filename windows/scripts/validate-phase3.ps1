$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $workspaceRoot

foreach ($relativePath in @(
    "Cargo.toml",
    "Cargo.lock",
    "crates\markowski-document\src\lib.rs",
    "crates\markowski-platform-windows\src\lib.rs",
    "apps\desktop-shell\src\lib.rs",
    "apps\desktop-ui\src\app.rs",
    "scripts\validate-phase3.ps1",
    "..\docs\windows\phase-03\PHASE_03_IMPLEMENTATION.md",
    "..\docs\windows\phase-03\ACCEPTANCE_MATRIX.md",
    "..\docs\windows\phase-03\EVIDENCE.md"
)) {
    $path = Join-Path $workspaceRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Phase 3 required path is missing: $relativePath"
    }
}

$cargo = Get-Content -LiteralPath (Join-Path $workspaceRoot "Cargo.toml") -Raw
$documentSource = Get-Content -LiteralPath (Join-Path $workspaceRoot "crates\markowski-document\src\lib.rs") -Raw
$platformSource = Get-Content -LiteralPath (Join-Path $workspaceRoot "crates\markowski-platform-windows\src\lib.rs") -Raw
$shellSource = Get-Content -LiteralPath (Join-Path $workspaceRoot "apps\desktop-shell\src\lib.rs") -Raw
$uiSource = Get-Content -LiteralPath (Join-Path $workspaceRoot "apps\desktop-ui\src\app.rs") -Raw

foreach ($fragment in @(
    "markowski-document",
    "markowski-platform-windows",
    "sha256_bytes",
    "DocumentSession",
    "DocumentCoordinator",
    "DocumentFileSystem"
)) {
    if (-not ($cargo + $documentSource).Contains($fragment)) {
        throw "Phase 3 document-domain fragment is missing: $fragment"
    }
}

foreach ($fragment in @(
    "write_atomic",
    "MoveFileExW",
    "WATCH_DEBOUNCE",
    "WindowsWatcherHandle",
    "pick_open_document",
    "pick_save_document"
)) {
    if (-not ($platformSource + $shellSource).Contains($fragment)) {
        throw "Phase 3 Windows platform fragment is missing: $fragment"
    }
}

foreach ($fragment in @(
    "new_document",
    "open_document",
    "save_document",
    "save_document_as",
    "reload_document",
    "update_document_content",
    "get_document_state",
    "schedule_document_autosave"
)) {
    if (-not ($shellSource + $uiSource).Contains($fragment)) {
        throw "Phase 3 typed lifecycle fragment is missing: $fragment"
    }
}

foreach ($forbidden in @("monaco", "codemirror", "rusqlite", "sqlx", "sqlite")) {
    if (($cargo + $documentSource + $platformSource + $shellSource + $uiSource).ToLowerInvariant().Contains($forbidden)) {
        throw "Phase 3 scope boundary was crossed by: $forbidden"
    }
}

$capabilityPath = Join-Path $workspaceRoot "apps\desktop-shell\capabilities\default.json"
$capability = Get-Content -LiteralPath $capabilityPath -Raw | ConvertFrom-Json
$permissions = @($capability.permissions | ForEach-Object { [string]$_ })
if ($permissions -match "filesystem|shell|process|http|updater") {
    throw "Phase 3 capability boundary is broader than the approved shell baseline."
}

Write-Output "Windows Phase 3 implementation validation: PASS"
