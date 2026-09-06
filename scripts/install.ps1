# install.ps1 - Install the OpenCode + Orca orchestration kit into a consuming project
#
# Usage:
#   .\scripts\install.ps1 -Target <project-root>
#
# Parameters:
#   -Target  (mandatory) Path to the consuming project root directory.
#
# Behavior:
#   - Fails-closed: aborts if any target files already exist (no -Force).
#   - Copies templates and vendored ticket tooling into the target project.
#   - Appends .gitignore entries (idempotent).
#   - Attempts to clone and checkout the pinned orca commit.
#     If cloning fails (no git/no network), prints a WARN with manual
#     instructions but does NOT fail the overall install (exit 0).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target
)

# Resolve the directory containing this script (scripts/ directory)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$KitRoot = Split-Path -Parent $ScriptDir

# Resolve Target to absolute path
$Target = (Resolve-Path -Path $Target -ErrorAction Stop)

Write-Host "=== OpenCode + Orca Kit Installer ===" -ForegroundColor Cyan
Write-Host "Target : $Target" -ForegroundColor Gray
Write-Host ""

# ---------- fail-closed pre-check ----------
$Forbidden = @(
    "opencode.jsonc"
    "orca.toml"
    "deno.json"
    ".opencode\agents\orchestrator.md"
    ".opencode\agents\executor.md"
    ".orca-tools\bin\ticket.cmd"
    ".orca-local"
    "scripts\orca-local.ps1"
)

$Existing = @()
foreach ($f in $Forbidden) {
    $path = Join-Path $Target $f
    if (Test-Path $path) {
        $Existing += $f
    }
}

if ($Existing.Count -gt 0) {
    Write-Host "ABORT: The following files/directories already exist in $Target :" -ForegroundColor Red
    foreach ($f in $Existing) {
        Write-Host "  - $f" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Remove them or choose a different -Target path. This installer does NOT overwrite existing files." -ForegroundColor Red
    exit 1
}

# ---------- create directories ----------
Write-Host "[1/5] Creating directories..." -ForegroundColor Yellow

$dirs = @(
    ".opencode\agents"
    ".orca-tools\bin"
    "scripts"
)

foreach ($d in $dirs) {
    $full = Join-Path $Target $d
    if (-not (Test-Path $full)) {
        New-Item -ItemType Directory -Path $full -Force | Out-Null
    }
}

Write-Host "OK" -ForegroundColor Green

# ---------- copy templates ----------
Write-Host "[2/5] Copying templates..." -ForegroundColor Yellow

$templateSrc = Join-Path $KitRoot "templates"

# opencode.jsonc
Copy-Item (Join-Path $templateSrc "opencode.jsonc") (Join-Path $Target "opencode.jsonc") -Force

# orca.toml
Copy-Item (Join-Path $templateSrc "orca.toml") (Join-Path $Target "orca.toml") -Force

# deno.json
Copy-Item (Join-Path $templateSrc "deno.json") (Join-Path $Target "deno.json") -Force

# .opencode/agents/*
Copy-Item (Join-Path $templateSrc ".opencode\agents\*") (Join-Path $Target ".opencode\agents") -Force

# env.example -> .env.example
Copy-Item (Join-Path $templateSrc "env.example") (Join-Path $Target ".env.example") -Force

Write-Host "OK" -ForegroundColor Green

# ---------- copy vendored ticket tooling ----------
Write-Host "[3/5] Copying vendored ticket CLI..." -ForegroundColor Yellow

$ticketsSrc = Join-Path $KitRoot "vendored\ticket\bin"

Copy-Item (Join-Path $ticketsSrc "ticket.sh") (Join-Path $Target ".orca-tools\bin\ticket.sh") -Force
Copy-Item (Join-Path $ticketsSrc "ticket.cmd") (Join-Path $Target ".orca-tools\bin\ticket.cmd") -Force
Copy-Item (Join-Path $ticketsSrc "ticket-query.sh") (Join-Path $Target ".orca-tools\bin\ticket-query.sh") -Force

Write-Host "OK" -ForegroundColor Green

# ---------- copy orca-local.ps1 ----------
Write-Host "[4/5] Installing orca-local.ps1..." -ForegroundColor Yellow

Copy-Item (Join-Path $templateSrc "orca-local.ps1") (Join-Path $Target "scripts\orca-local.ps1") -Force

Write-Host "OK" -ForegroundColor Green

# ---------- .gitignore append (idempotent) ----------
Write-Host "[5/5] Updating .gitignore..." -ForegroundColor Yellow

$gitignorePath = Join-Path $Target ".gitignore"
$ignoreLines = @(
    "# Orca kit: generated entries"
    ".orca-local/"
    ".orca-tools/"
    ".opencode/node_modules/"
    ".env"
)

if (Test-Path $gitignorePath) {
    $existingContent = Get-Content $gitignorePath -Raw
    foreach ($line in $ignoreLines) {
        if ($existingContent -notlike "*$line*") {
            Add-Content -Path $gitignorePath -Value "$line`n"
        }
    }
} else {
    $lines = @()
    foreach ($line in $ignoreLines) {
        $lines += $line
    }
    Set-Content -Path $gitignorePath -Value ($lines -join "`n") -NoNewline
}

Write-Host "OK" -ForegroundColor Green

# ---------- bootstrap orca (non-fatal) ----------
Write-Host ""
Write-Host "Bootstrapping orca..." -ForegroundColor Yellow

$orcaLocal = Join-Path $Target ".orca-local"
$orcaUrl = "https://github.com/upvalue/orca.git"
$orcaCommit = "35938cc8aa328853333bd171d474c300b4c09251"

$orcaCloned = $false
$hasGit = $false

if (Get-Command git -ErrorAction SilentlyContinue) {
    $hasGit = $true
    try {
        git clone $orcaUrl $orcaLocal 2>&1 | Out-Null
        git -C $orcaLocal checkout $orcaCommit 2>&1 | Out-Null
        if (Test-Path (Join-Path $orcaLocal ".git")) {
            $orcaCloned = $true
            Write-Host "OK - orca cloned and checked out at $orcaCommit" -ForegroundColor Green
        }
    } catch {
        Write-Warning "Failed to clone orca: $_"
    }
}

if (-not $orcaCloned) {
    Write-Warning ""
    Write-Warning "WARNING: orca was NOT cloned. This may be due to:"
    Write-Warning "  - git not installed"
    Write-Warning "  - no network connection"
    Write-Warning "  - a previous failure"
    Write-Warning ""
    Write-Warning "Manual bootstrap command:"
    Write-Warning "  git clone https://github.com/upvalue/orca.git $Target\.orca-local"
    Write-Warning "  git -C $Target\.orca-local checkout $orcaCommit"
    Write-Warning ""
    Write-Host "INSTALL COMPLETED (with WARN - see above)" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "INSTALL COMPLETED SUCCESSFULLY" -ForegroundColor Green
}

# ---------- summary ----------
Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Start the OpenCode server (refer to your project opencode docs)."
Write-Host "2. Run: deno task orca:plan"
Write-Host "   This verifies the orchestration pipeline is wired correctly."
Write-Host ""
Write-Host "3. For interactive work: .\scripts\orca-local.ps1"
Write-Host ""
Write-Host "4. Review orca.toml and add any project-specific stages/notes."
Write-Host "5. Ensure OPENCODE_URL is set in .env (or use the default: http://localhost:4096)."
Write-Host ""