$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $workspaceRoot "apps\desktop-shell\tauri.conf.json"
$capabilityPath = Join-Path $workspaceRoot "apps\desktop-shell\capabilities\default.json"

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$capability = Get-Content -LiteralPath $capabilityPath -Raw | ConvertFrom-Json
$csp = [string]$config.app.security.csp

if ([string]::IsNullOrWhiteSpace($csp)) {
    throw "Tauri CSP is missing."
}

if ($csp -match "\*" -or $csp -match "https://" -or $csp -match "script-src[^;]*https:") {
    throw "Tauri CSP contains a wildcard or remote runtime origin."
}

if ($csp -notmatch "default-src 'self'" -or $csp -notmatch "script-src 'self' 'wasm-unsafe-eval'" -or $csp -notmatch "object-src 'none'") {
    throw "Tauri CSP does not contain the required restrictive directives."
}

$allowedPermissions = @(
    "core:app:default",
    "core:event:default",
    "core:resources:default",
    "core:window:default",
    "allow-get-app-info"
)
$permissions = @($capability.permissions | ForEach-Object { [string]$_ })

if ($permissions.Count -ne $allowedPermissions.Count) {
    throw "Capability permission count changed unexpectedly."
}

foreach ($permission in $permissions) {
    if ($permission -notin $allowedPermissions) {
        throw "Unexpected capability permission: $permission"
    }
}

$forbiddenPermissionTerms = @("shell", "filesystem", "process", "http", "updater")
foreach ($term in $forbiddenPermissionTerms) {
    if ($permissions -match $term) {
        throw "Forbidden capability permission contains: $term"
    }
}

$credentialPattern = '(?i)(api[_-]?key|password|bearer)\s*[:=]\s*["''][^"'']{8,}["'']|-----BEGIN[ -].*PRIVATE KEY'
$scanMatches = $null
$scanExitCode = 1
Push-Location $workspaceRoot
try {
    $scanMatches = & rg --no-heading --hidden --glob '!target/**' --glob '!dist/**' --glob '*.rs' --glob '*.toml' --glob '*.json' -e $credentialPattern -- apps crates 2>$null
    $scanExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}
if ($scanExitCode -eq 0 -and $scanMatches) {
    throw "Credential-shaped literal found in production source/configuration."
}
if ($scanExitCode -gt 1) {
    throw "Secret scan failed with exit code $scanExitCode."
}

Write-Output "Phase 1 security validation: PASS"
