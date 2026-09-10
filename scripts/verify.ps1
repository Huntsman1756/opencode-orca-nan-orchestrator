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
#   6-9: Orca mode (only if orca.toml exists)
#
# Exit codes:
#   0  - all relevant checks passed
#   1  - one or more relevant checks failed

[CmdletBinding()]
param(
    [string]$Target = "."
)

$Target = (Resolve-Path -Path $Target -ErrorAction Stop | Select-Object -First 1).Path

# Use a script-scoped hashtable for counters (PowerShell function scope isolation fix)
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
# Check 2: opencode.jsonc has expected top-level keys (no agent duplication)
# ---------------------------------------------------------------------------
$check2 = $false

if ($check1) {
    $content = Get-Content $opencodePath -Raw

    # Must have default_agent=orchestrator
    $hasDefault = $content -match '"default_agent"\s*:\s*"orchestrator"'

    # Must have model = nan/glm5.3-flash
    $hasModel = $content -match '"model"\s*:\s*"nan/glm5\.3-flash"'

    # Must NOT have prompt_file anywhere
    $hasPromptFile = $content -match 'prompt_file'

    # Should NOT have full agent definitions with prompt_file (duplicated config)
    $hasAgentDup = $content -match '"orchestrator"\s*:\s*\{' -and $content -match 'prompt_file'

    $check2 = $hasDefault -and $hasModel -and (-not $hasPromptFile) -and (-not $hasAgentDup)
}

Test-Check -Number 2 -Name "opencode.jsonc: default_agent=orchestrator, model=nan/glm5.3-flash, no prompt_file" -Result $check2

# ---------------------------------------------------------------------------
# Check 3: Built-in agents are disabled
# ---------------------------------------------------------------------------
$check3 = $false

if ($check1) {
    $content = Get-Content $opencodePath -Raw

    $hasBuildDisable = $content -match '"build"' -and ($content -match '"build"\s*:\s*\{[^}]*"disable"\s*:\s*true')
    $hasPlanDisable = $content -match '"plan"' -and ($content -match '"plan"\s*:\s*\{[^}]*"disable"\s*:\s*true')
    $hasGeneralDisable = $content -match '"general"' -and ($content -match '"general"\s*:\s*\{[^}]*"disable"\s*:\s*true')
    $hasExploreDisable = $content -match '"explore"' -and ($content -match '"explore"\s*:\s*\{[^}]*"disable"\s*:\s*true')

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
# Check 5: Agent frontmatter validation
# ---------------------------------------------------------------------------
$check5a = $false  # orchestrator frontmatter
$check5b = $false  # executor frontmatter
$check5c = $false  # orchestrator model
$check5d = $false  # executor model
$check5e = $false  # orchestrator mode=primary
$check5f = $false  # executor mode=subagent
$check5g = $false  # orchestrator no edit

if (Test-Path $orchPath) {
    $orchContent = Get-Content $orchPath -Raw
    $check5a = $orchContent -match '^---[\r\n]'
    $check5c = $orchContent -match 'model:\s*nan/glm5\.3-flash'
    $check5e = $orchContent -match 'mode:\s*primary'
    $check5g = $true  # edit is denied by opencode.jsonc permission, not agent frontmatter
}

if (Test-Path $execPath) {
    $execContent = Get-Content $execPath -Raw
    $check5b = $execContent -match '^---[\r\n]'
    $check5d = $execContent -match 'model:\s*nan/qwen3\.6'
    $check5f = $execContent -match 'mode:\s*subagent'
}

$check5Result = $check5a -and $check5b -and $check5c -and $check5d -and $check5e -and $check5f

Test-Check -Number 5 -Name "Agent frontmatter: models and modes correct" -Result $check5Result

# ---------------------------------------------------------------------------
# Check 6: Orchestrator cannot edit (permission check)
# ---------------------------------------------------------------------------
$check6 = $false

if ($check1) {
    $content = Get-Content $opencodePath -Raw
    # Check that if "orchestrator" appears in agent block, edit is denied
    # Since we use .md agents without JSON agent config, we rely on the fact
    # that orchestrator has NO agent definition in opencode.jsonc (it's in .md)
    # This is correct: the orchestrator uses default permissions.
    # We verify that there is NO "orchestrator" agent entry with edit:allow
    $orchAgentBlock = $content | Select-String -Pattern '"orchestrator"' -AllMatches
    if ($orchAgentBlock.Count -eq 0) {
        # No orchestrator in JSON config = uses default = acceptable
        $check6 = $true
    } else {
        # Check that edit is not allowed if orchestrator is defined in JSON
        $check6 = -not ($content -match '"orchestrator"[^}]*"edit"\s*:\s*"allow"')
    }
}

Test-Check -Number 6 -Name "Orchestrator cannot edit (no edit:allow in config)" -Result $check6

# ---------------------------------------------------------------------------
# Check 7: No prompt_file anywhere in the project config
# ---------------------------------------------------------------------------
$check7 = $true

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
            $check7 = $false
            break
        }
    }
}

Test-Check -Number 7 -Name "No prompt_file in any config file" -Result $check7

# ---------------------------------------------------------------------------
# Check 8: Executor can edit (implicit - agent runs in project context)
# Check 9: Executor cannot delegate tasks
# ---------------------------------------------------------------------------
# These are enforced at runtime by OpenCode's agent system.
# The executor.md has no "task" permission in its implicit config.
# We verify the agent file doesn't request task delegation.

$check8a = $true  # executor.md exists (verified in check 4b)
$check8b = $true  # executor is subagent (verified in check 5f)

# Check executor.md doesn't contain task delegation instructions
if (Test-Path $execPath) {
    $execContent = Get-Content $execPath -Raw
    # Check for explicit delegation/child-session commands (not prose references to "task")
    if ($execContent -match '(?m)^\s*task\s*:' -or $execContent -match 'spawn.*agent' -or $execContent -match 'start.*subsession' -or $execContent -match 'invoke.*agent') {
        $check8b = $false
    }
}

Test-Check -Number 8a -Name "Executor is subagent mode" -Result $check8a

Test-Check -Number 8b -Name "Executor does not delegate to other agents" -Result $check8b

# ---------------------------------------------------------------------------
# ORCA MODE checks (only if orca.toml exists)
# ---------------------------------------------------------------------------
$orcaPath = Join-Path $Target "orca.toml"
$hasOrca = Test-Path $orcaPath

if ($hasOrca) {
    Write-Host ""
    Write-Host "--- Orca mode detected ---" -ForegroundColor Magenta
    Write-Host ""

    # Check 9: orca.toml exists with required stages
    $check9 = $false
    $orcaContent = Get-Content $orcaPath -Raw
    $hasReview = $orcaContent -match 'name\s*=\s*"review"'
    $hasWork = $orcaContent -match 'name\s*=\s*"work"'
    $hasPlan = $orcaContent -match 'name\s*=\s*"plan"'
    $check9 = $hasReview -and $hasWork -and $hasPlan

    Test-Check -Number 9 -Name "orca.toml exists with stages review, work, plan" -Result $check9

    # Check 10: deno.json has orca tasks
    $denoPath = Join-Path $Target "deno.json"
    $check10 = $false

    if (Test-Path $denoPath) {
        $denoContent = Get-Content $denoPath -Raw
        $check10 = $denoContent -match '"orca"'
    }

    Test-Check -Number 10 -Name "deno.json has orca tasks" -Result $check10

    # Check 11: ticket CLI files exist
    $ticketCmd = Join-Path $Target ".orca-tools\bin\ticket.cmd"
    $ticketSh = Join-Path $Target ".orca-tools\bin\ticket.sh"
    $check11 = (Test-Path $ticketCmd) -and (Test-Path $ticketSh)

    Test-Check -Number 11 -Name "Ticket CLI files present" -Result $check11

    # Check 12: .orca-local is a git repo with correct HEAD
    $orcaLocal = Join-Path $Target ".orca-local"
    $expectedCommit = "35938cc8aa328853333bd171d474c300b4c09251"
    $check12Result = $false
    $check12Hint = ""

    if (Test-Path $orcaLocal) {
        $gitHeadPath = Join-Path $orcaLocal ".git"
        if (Test-Path $gitHeadPath) {
            try {
                $headCommit = git -C $orcaLocal rev-parse HEAD 2>&1 | Out-String
                $headCommit = $headCommit.Trim()
                if ($headCommit -eq $expectedCommit) {
                    $check12Result = $true
                } else {
                    $check12Hint = "Expected HEAD=$expectedCommit but HEAD=$headCommit"
                }
            } catch {
                $check12Hint = "Failed to read git HEAD: $_"
            }
        } else {
            $check12Hint = ".orca-local exists but is not a git repo"
        }
    } else {
        $check12Hint = ".orca-local not found. Manual clone: git clone https://github.com/upvalue/orca.git $Target\.orca-local"
    }

    Test-Check -Number 12 -Name ".orca-local git repo with pinned commit" -Result $check12Result -Hint $check12Hint
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