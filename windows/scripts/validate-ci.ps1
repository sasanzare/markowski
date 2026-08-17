$ErrorActionPreference = "Stop"

$workflowPath = Join-Path (Split-Path -Parent $PSScriptRoot) "..\.github\workflows\windows-phase1.yml"
$workflow = Get-Content -LiteralPath $workflowPath -Raw

$requiredFragments = @(
    "runs-on: windows-latest",
    "permissions:",
    "contents: read",
    "cargo fmt --check",
    "cargo check --workspace",
    "cargo clippy --workspace --all-targets --all-features -- -D warnings",
    "cargo test --workspace",
    "./scripts/validate-security.ps1",
    "trunk build --release",
    "cargo tauri build --no-bundle --ci",
    "wasm32-unknown-unknown",
    "rustfmt, clippy"
)

foreach ($fragment in $requiredFragments) {
    if (-not $workflow.Contains($fragment)) {
        throw "Windows Phase 1 workflow is missing required fragment: $fragment"
    }
}

if ($workflow -match "permissions:\s*\r?\n\s+contents:\s+write") {
    throw "Windows Phase 1 workflow requests write access to repository contents."
}

if ($workflow -match "secrets\.") {
    throw "Windows Phase 1 workflow must not require secrets."
}

Write-Output "Phase 1 CI contract validation: PASS"
