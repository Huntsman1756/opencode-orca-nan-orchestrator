# install.ps1 - Install the OpenCode + Orca orchestration kit into a consuming project
#
# Usage:
#   .\scripts\install.ps1 -Target <project-root>                           # CORE only (default)
#   .\scripts\install.ps1 -Target <project-root> -WithOrca                 # CORE + Orca advanced mode
#
# Parameters:
#   -Target    (mandatory) Path to the consuming project root directory.
#   -WithOrca  (optional)  Include Orca ticket-mode support (requires Deno, git clone).
#
# CORE files (always installed):
#   opencode.jsonc
#   .opencode/agents/orchestrator.md
#   .opencode/agents/executor.md
#   .gitignore entries
#
# With -WithOrca, additionally:
#   orca.toml
#   deno.json
#   scripts/orca-local.ps1
#   .env.example
#   .orca-tools/bin/* (vendored ticket CLI)
#   upvalue/orca cloned to .orca-local/

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [switch]$WithOrca
)

# Resolve the directory containing this script (scripts/ directory)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$KitRoot = Split-Path -Parent $ScriptDir

# Resolve Target to absolute path
$Target = (Resolve-Path -Path $Target -ErrorAction Stop)

Write-Host "=== OpenCode + Orca Kit Installer ===" -ForegroundColor Cyan
Write-Host "Target : $Target" -ForegroundColor Gray
Write-Host "Mode   : $(if ($WithOrca) { 'CORE + ORCA' } else { 'CORE' })" -ForegroundColor Gray
Write-Host ""

# ---------- fail-closed pre-check ----------
$Forbidden = @(
    "opencode.jsonc"
    ".opencode\agents\orchestrator.md"
    ".opencode\agents\executor.md"
)

if ($WithOrca) {
    $Forbidden += @(
        "orca.toml"
        "deno.json"
        ".orca-tools\bin\ticket.cmd"
        ".orca-local"
        "scripts\orca-local.ps1"
    )
}

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
Write-Host "[1/$(if ($WithOrca) { 7 } else { 3 })] Creating directories..." -ForegroundColor Yellow

$dirs = @(
    ".opencode\agents"
    "scripts"
)

if ($WithOrca) {
    $dirs += @(".orca-tools\bin")
}

foreach ($d in $dirs) {
    $full = Join-Path $Target $d
    if (-not (Test-Path $full)) {
        New-Item -ItemType Directory -Path $full -Force | Out-Null
    }
}

Write-Host "OK" -ForegroundColor Green

# ---------- copy CORE templates ----------
Write-Host "[2/$(if ($WithOrca) { 7 } else { 3 })] Copying CORE templates..." -ForegroundColor Yellow

$templateSrc = Join-Path $KitRoot "templates"

# opencode.jsonc
Copy-Item (Join-Path $templateSrc "opencode.jsonc") (Join-Path $Target "opencode.jsonc") -Force

# .opencode/agents/*
Copy-Item (Join-Path $templateSrc ".opencode\agents\*") (Join-Path $Target ".opencode\agents") -Force

Write-Host "OK" -ForegroundColor Green

# ---------- Orca mode (optional) ----------
if ($WithOrca) {
    Write-Host "[3/7] Copying Orca templates..." -ForegroundColor Yellow

    # orca.toml
    Copy-Item (Join-Path $templateSrc "orca.toml") (Join-Path $Target "orca.toml") -Force

    # deno.json
    Copy-Item (Join-Path $templateSrc "deno.json") (Join-Path $Target "deno.json") -Force

    # env.example -> .env.example
    Copy-Item (Join-Path $templateSrc "env.example") (Join-Path $Target ".env.example") -Force

    Write-Host "OK" -ForegroundColor Green

    Write-Host "[4/7] Copying vendored ticket CLI..." -ForegroundColor Yellow

    $ticketsSrc = Join-Path $KitRoot "vendored\ticket\bin"

    Copy-Item (Join-Path $ticketsSrc "ticket.sh") (Join-Path $Target ".orca-tools\bin\ticket.sh") -Force
    Copy-Item (Join-Path $ticketsSrc "ticket.cmd") (Join-Path $Target ".orca-tools\bin\ticket.cmd") -Force
    Copy-Item (Join-Path $ticketsSrc "ticket-query.sh") (Join-Path $Target ".orca-tools\bin\ticket-query.sh") -Force

    Write-Host "OK" -ForegroundColor Green

    Write-Host "[5/7] Installing orca-local.ps1..." -ForegroundColor Yellow

    Copy-Item (Join-Path $templateSrc "orca-local.ps1") (Join-Path $Target "scripts\orca-local.ps1") -Force

    Write-Host "OK" -ForegroundColor Green
}

# ---------- .gitignore append (idempotent) ----------
Write-Host "[$(if ($WithOrca) { 6 } else { 3 })/$(if ($WithOrca) { 7 } else { 3 })] Updating .gitignore..." -ForegroundColor Yellow

$gitignorePath = Join-Path $Target ".gitignore"
$ignoreLines = @(
    "# Orca kit: generated entries"
    ".opencode/node_modules/"
)

if ($WithOrca) {
    $ignoreLines += @(
        ".orca-local/"
        ".orca-tools/"
        ".env"
    )
}

if (Test-Path $gitignorePath) {
    $existingContent = Get-Content $gitignorePath -Raw
    foreach ($line in $ignoreLines) {
        if ($existingContent -notlike "*$line*") {
            Add-Content -Path $gitignorePath -Value "$line`n"
        }
    }
} else {
    Set-Content -Path $gitignorePath -Value (($ignoreLines | ForEach-Object { "$_`n" }) -join "") -NoNewline
}

Write-Host "OK" -ForegroundColor Green

# ---------- bootstrap orca (optional, non-fatal) ----------
if ($WithOrca) {
    Write-Host "[7/7] Bootstrapping orca..." -ForegroundColor Yellow

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
        Write-Host "INSTALL COMPLETED SUCCESSFULLY (CORE + ORCA)" -ForegroundColor Green
    }

    # ---------- summary ----------
    Write-Host ""
    Write-Host "=== Next Steps ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "CORE (immediate):"
    Write-Host "  1. Start OpenCode in your project."
    Write-Host "  2. Use the 'orchestrator' agent to plan and delegate implementation."
    Write-Host ""
    Write-Host "ORCA (optional, requires Deno):"
    Write-Host "  1. Install Deno 2.x from https://deno.com"
    Write-Host "  2. Run: deno task orca:plan"
    Write-Host "     This verifies the orchestration pipeline is wired correctly."
    Write-Host ""
    Write-Host "  3. For interactive work: .\scripts\orca-local.ps1"
    Write-Host ""
    Write-Host "  4. Review orca.toml and add any project-specific stages/notes."
    Write-Host "  5. Ensure OPENCODE_URL is set in .env (or use the default: http://localhost:4096)."
    Write-Host ""
} else {
    # ---------- summary (core only) ----------
    Write-Host ""
    Write-Host "=== Next Steps ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "CORE:"
    Write-Host "  1. Start OpenCode in your project directory."
    Write-Host "  2. The default agent is 'orchestrator' (nan/glm5.3-flash)."
    Write-Host "  3. The orchestrator delegates implementation to 'executor' (nan/qwen3.6)."
    Write-Host ""
    Write-Host "Optional: To enable ticket-driven autonomous mode:"
    Write-Host "  .\scripts\install.ps1 -Target $(Resolve-Path $Target) -WithOrca"
    Write-Host ""
    Write-Host "Then run:"
    Write-Host "  .\scripts\verify.ps1 -Target $(Resolve-Path $Target)"
    Write-Host ""
}