# verify.ps1 - Static verification of the OpenCode orchestrator kit
#
# Usage:
#   .\scripts\verify.ps1 [-Target <path>]
#
# Parameters:
#   -Target  Path to the project root (default: current directory).
#
# Checks:
#   1-5: Core config validation (always)
#   6-9: Permission enforcement on agents (always)
#  10-13: Orca mode (only if orca.toml exists)
#
# Exit codes:
#   0  - all relevant checks passed
#   1  - one or more relevant checks failed

[CmdletBinding()]
param(
    [string]$Target = "."
)

$Target = (Resolve-Path -Path $Target -ErrorAction Stop | Select-Object -First 1).Path

# Use a script-scoped hashtable for counters
$script:results = @{
    passCount = 0
    failCount = 0
    totalCount = 0
}

function Test-Check {
    param(
        [string]$Number,
        [string]$Name,
        [bool]$Result,
        [string]$Hint = ""
    )
    $script:results.totalCount++
    if ($Result) {
        $script:results.passCount++
        Write-Host "[$Number/$($script:results.totalCount)] $Name ... PASS" -ForegroundColor Green
    } else {
        $script:results.failCount++
        Write-Host "[$Number/$($script:results.totalCount)] $Name ... FAIL" -ForegroundColor Red
        if ($Hint) {
            Write-Host "       $Hint" -ForegroundColor DarkGray
        }
    }
}

Write-Host "=== OpenCode Orchestrator Kit Verifier ===" -ForegroundColor Cyan
Write-Host "Target : $Target" -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------------------------
# Check 1: opencode.jsonc exists
# ---------------------------------------------------------------------------
$opencodePath = Join-Path $Target "opencode.jsonc"
$check1 = Test-Path $opencodePath

Test-Check -Number 1 -Name "opencode.jsonc exists" -Result $check1

# ---------------------------------------------------------------------------
# Check 2: opencode.jsonc has expected top-level keys
# ---------------------------------------------------------------------------
$check2 = $false

if ($check1) {
    $content = Get-Content $opencodePath -Raw

    $hasDefault = $content -match '"default_agent"\s*:\s*"orchestrator"'
    $hasModel   = $content -match '"model"\s*:\s*"nan/glm5\.3-flash"'
    $hasPromptFile = $content -match 'prompt_file'

    $check2 = $hasDefault -and $hasModel -and (-not $hasPromptFile)
}

Test-Check -Number 2 -Name "opencode.jsonc: default_agent=orchestrator, model=nan/glm5.3-flash, no prompt_file" -Result $check2

# ---------------------------------------------------------------------------
# Check 3: Built-in agents are disabled
# ---------------------------------------------------------------------------
$check3 = $false

if ($check1) {
    $content = Get-Content $opencodePath -Raw

    $hasBuildDisable = $content -match '"build"\s*:\s*\{[^}]*"disable"\s*:\s*true'
    $hasPlanDisable  = $content -match '"plan"\s*:\s*\{[^}]*"disable"\s*:\s*true'
    $hasGeneralDisable = $content -match '"general"\s*:\s*\{[^}]*"disable"\s*:\s*true'
    $hasExploreDisable = $content -match '"explore"\s*:\s*\{[^}]*"disable"\s*:\s*true'

    $check3 = $hasBuildDisable -and $hasPlanDisable -and $hasGeneralDisable -and $hasExploreDisable
}

Test-Check -Number 3 -Name "Built-in agents disabled (build/plan/general/explore)" -Result $check3

# ---------------------------------------------------------------------------
# Check 4: Agent prompt files exist and are non-empty
# ---------------------------------------------------------------------------
$orchPath = Join-Path $Target ".opencode\agents\orchestrator.md"
$execPath = Join-Path $Target ".opencode\agents\executor.md"

$check4a = (Test-Path $orchPath) -and ((Get-Item $orchPath).Length -gt 0)
$check4b = (Test-Path $execPath) -and ((Get-Item $execPath).Length -gt 0)

Test-Check -Number 4a -Name "orchestrator.md exists and is non-empty" -Result $check4a
Test-Check -Number 4b -Name "executor.md exists and is non-empty" -Result $check4b

# ---------------------------------------------------------------------------
# Check 5: Agent frontmatter - models, modes, descriptions
# ---------------------------------------------------------------------------
$check5a = $false  # orchestrator has YAML frontmatter
$check5b = $false  # executor has YAML frontmatter
$check5c = $false  # orchestrator model
$check5d = $false  # executor model
$check5e = $false  # orchestrator mode=primary
$check5f = $false  # executor mode=subagent
$check5g = $false  # orchestrator has description
$check5h = $false  # executor has description

if (Test-Path $orchPath) {
    $orchContent = Get-Content $orchPath -Raw
    $check5a = $orchContent -match '^---[\r\n]'
    $check5c = $orchContent -match 'model:\s*nan/glm5\.3-flash'
    $check5e = $orchContent -match 'mode:\s*primary'
    $check5g = $orchContent -match 'description:'
}

if (Test-Path $execPath) {
    $execContent = Get-Content $execPath -Raw
    $check5b = $execContent -match '^---[\r\n]'
    $check5d = $execContent -match 'model:\s*nan/qwen3\.6'
    $check5f = $execContent -match 'mode:\s*subagent'
    $check5h = $execContent -match 'description:'
}

Test-Check -Number 5a -Name "Orchestrator frontmatter: model=nan/glm5.3-flash, mode=primary" -Result ($check5a -and $check5c -and $check5e -and $check5g)
Test-Check -Number 5b -Name "Executor frontmatter: model=nan/qwen3.6, mode=subagent" -Result ($check5b -and $check5d -and $check5f -and $check5h)

# ---------------------------------------------------------------------------
# Check 6: Orchestrator permissions - edit must be explicitly denied
# ---------------------------------------------------------------------------
$check6a = $false  # orchestrator has permission block
$check6b = $false  # orchestrator edit: deny present
$check6c = $false  # orchestrator task restricted to executor only

if (Test-Path $orchPath) {
    $orchContent = Get-Content $orchPath -Raw
    $check6a = $orchContent -match 'permission:'
    $check6b = $orchContent -match 'edit:\s*deny'

    # Check task: verify executor is in allowlist and there's a deny/ask wildcard
    if ($orchContent -match 'task:') {
        $hasTaskExecutorAllow = $orchContent -match 'executor:\s*allow'
        $hasTaskWildcardDeny = $orchContent -match ':\s*\*\s*:\s*(?:deny|ask)' -or $orchContent -match ':\s*"\*"\s*:\s*(?:deny|ask)'
        $check6c = $hasTaskExecutorAllow -and $hasTaskWildcardDeny
    } else {
        $check6c = $false
    }
}

Test-Check -Number 6a -Name "Orchestrator has explicit permission block" -Result $check6a
Test-Check -Number 6b -Name "Orchestrator: edit explicitly denied" -Result $check6b
Test-Check -Number 6c -Name "Orchestrator: task delegation restricted to executor only" -Result $check6c

# ---------------------------------------------------------------------------
# Check 7: Executor permissions - task must be explicitly denied
# ---------------------------------------------------------------------------
$check7a = $false  # executor has permission block
$check7b = $false  # executor task: deny present
$check7c = $false  # executor webfetch: deny
$check7d = $false  # executor skill: deny

if (Test-Path $execPath) {
    $execContent = Get-Content $execPath -Raw
    $check7a = $execContent -match 'permission:'
    $check7b = $execContent -match 'task:\s*deny'
    $check7c = $execContent -match 'webfetch:\s*deny'
    $check7d = $execContent -match 'skill:\s*deny'
}

Test-Check -Number 7a -Name "Executor has explicit permission block" -Result $check7a
Test-Check -Number 7b -Name "Executor: task explicitly denied" -Result $check7b
Test-Check -Number 7c -Name "Executor: webfetch denied" -Result $check7c
Test-Check -Number 7d -Name "Executor: skill denied" -Result $check7d

# ---------------------------------------------------------------------------
# Check 8: No prompt_file anywhere in project config
# ---------------------------------------------------------------------------
$check8 = $true

$configFiles = @(
    (Join-Path -Path $Target -ChildPath "opencode.jsonc"),
    (Join-Path -Path $Target -ChildPath ".opencode.jsonc"),
    (Join-Path -Path $Target -ChildPath ".opencode\config.jsonc"),
    (Join-Path -Path $Target -ChildPath ".opencode\config.json")
)

foreach ($cf in $configFiles) {
    if (Test-Path $cf) {
        $cfContent = Get-Content $cf -Raw
        if ($cfContent -match 'prompt_file') {
            $check8 = $false
            break
        }
    }
}

Test-Check -Number 8 -Name "No prompt_file in any config file" -Result $check8

# ---------------------------------------------------------------------------
# Check 9: No agent definition in JSON that duplicates .md frontmatter
# ---------------------------------------------------------------------------
# If both opencode.jsonc defines an agent AND that agent has a .md file,
# it creates ambiguity. We only allow .md files to define agents.
$check9 = $true

if ($check1) {
    $jsonContent = Get-Content $opencodePath -Raw
    if ($jsonContent -match '"orchestrator"\s*:\s*\{') {
        # Check if this JSON orchestrator has a prompt_file (old pattern)
        if ($jsonContent -match '"orchestrator"[^}]*prompt_file') {
            $check9 = $false
        }
    }
}

Test-Check -Number 9 -Name "No agent duplication between JSON and .md" -Result $check9

# ---------------------------------------------------------------------------
# ORCA MODE checks (only if orca.toml exists)
# ---------------------------------------------------------------------------
$orcaPath = Join-Path $Target "orca.toml"
$hasOrca = Test-Path $orcaPath

if ($hasOrca) {
    Write-Host ""
    Write-Host "--- Orca mode detected ---" -ForegroundColor Magenta
    Write-Host ""

    # Check 10: orca.toml exists with required stages
    $check10 = $false
    $orcaContent = Get-Content $orcaPath -Raw
    $hasReview = $orcaContent -match 'name\s*=\s*"review"'
    $hasWork = $orcaContent -match 'name\s*=\s*"work"'
    $hasPlan = $orcaContent -match 'name\s*=\s*"plan"'
    $check10 = $hasReview -and $hasWork -and $hasPlan

    Test-Check -Number 10 -Name "orca.toml exists with stages review, work, plan" -Result $check10

    # Check 11: deno.json has orca tasks
    $denoPath = Join-Path $Target "deno.json"
    $check11 = $false

    if (Test-Path $denoPath) {
        $denoContent = Get-Content $denoPath -Raw
        $check11 = $denoContent -match '"orca"'
    }

    Test-Check -Number 11 -Name "deno.json has orca tasks" -Result $check11

    # Check 12: ticket CLI files exist
    $ticketCmd = Join-Path $Target ".orca-tools\bin\ticket.cmd"
    $ticketSh = Join-Path $Target ".orca-tools\bin\ticket.sh"
    $check12 = (Test-Path $ticketCmd) -and (Test-Path $ticketSh)

    Test-Check -Number 12 -Name "Ticket CLI files present" -Result $check12

    # Check 13: .orca-local is a git repo with correct HEAD
    $orcaLocal = Join-Path $Target ".orca-local"
    $expectedCommit = "35938cc8aa328853333bd171d474c300b4c09251"
    $check13Result = $false
    $check13Hint = ""

    if (Test-Path $orcaLocal) {
        $gitHeadPath = Join-Path $orcaLocal ".git"
        if (Test-Path $gitHeadPath) {
            try {
                $headCommit = git -C $orcaLocal rev-parse HEAD 2>&1 | Out-String
                $headCommit = $headCommit.Trim()
                if ($headCommit -eq $expectedCommit) {
                    $check13Result = $true
                } else {
                    $check13Hint = "Expected HEAD=$expectedCommit but HEAD=$headCommit"
                }
            } catch {
                $check13Hint = "Failed to read git HEAD: $_"
            }
        } else {
            $check13Hint = ".orca-local exists but is not a git repo"
        }
    } else {
        $check13Hint = ".orca-local not found. Manual clone: git clone https://github.com/upvalue/orca.git $Target\.orca-local"
    }

    Test-Check -Number 13 -Name ".orca-local git repo with pinned commit" -Result $check13Result -Hint $check13Hint
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "Passed : $($script:results.passCount) / $($script:results.totalCount)" -ForegroundColor Green
Write-Host "Failed : $($script:results.failCount) / $($script:results.totalCount)" -ForegroundColor $(if ($script:results.failCount -gt 0) { "Red" } else { "Green" })

if ($script:results.failCount -gt 0) {
    Write-Host ""
    Write-Host "VERIFICATION FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "VERIFICATION PASSED" -ForegroundColor Green
    exit 0
}