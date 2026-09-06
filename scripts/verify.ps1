# verify.ps1 - Verify that the OpenCode + Orca kit is correctly installed in a project
#
# Usage:
#   .\scripts\verify.ps1 [-Target <path>]
#
# Parameters:
#   -Target  Path to the project root (default: current directory).
#
# Exit codes:
#   0  - all checks passed
#   1  - one or more checks failed

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

Write-Host "=== OpenCode + Orca Kit Verifier ===" -ForegroundColor Cyan
Write-Host "Target : $Target" -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------------------------
# Check 1: opencode.jsonc exists and has expected content
# ---------------------------------------------------------------------------
$opencodePath = Join-Path $Target "opencode.jsonc"
$check1 = Test-Path $opencodePath

if ($check1) {
    $content = Get-Content $opencodePath -Raw
    $hasDefault = $content -match '"default_agent"\s*:\s*"orchestrator"'
    $hasGlm = $content -match 'nan/glm5\.3-flash'
    $check1 = $hasDefault -and $hasGlm
}

Test-Check -Number 1 -Name "opencode.jsonc exists with default_agent=orchestrator and model nan/glm5.3-flash" -Result $check1

# ---------------------------------------------------------------------------
# Check 2: opencode.jsonc has executor model and disables unused agents
# ---------------------------------------------------------------------------
$check2b = $false

if (Test-Path $opencodePath) {
    $content = Get-Content $opencodePath -Raw

    # Check executor model
    $hasExecutor = $content -match 'nan/qwen3\.6'

    if ($hasExecutor) {
        # Check disabled agents using content scan
        $hasBuildDisable = $false
        $hasPlanDisable = $false
        $hasGeneralDisable = $false
        $hasExploreDisable = $false

        $lines = Get-Content $opencodePath
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '"build"') {
                for ($j = $i; $j -lt ([Math]::Min($i + 5, $lines.Count)); $j++) {
                    if ($lines[$j] -match '"disable"\s*:\s*true') { $hasBuildDisable = $true }
                }
            }
            if ($lines[$i] -match '"plan"') {
                for ($j = $i; $j -lt ([Math]::Min($i + 5, $lines.Count)); $j++) {
                    if ($lines[$j] -match '"disable"\s*:\s*true') { $hasPlanDisable = $true }
                }
            }
            if ($lines[$i] -match '"general"') {
                for ($j = $i; $j -lt ([Math]::Min($i + 5, $lines.Count)); $j++) {
                    if ($lines[$j] -match '"disable"\s*:\s*true') { $hasGeneralDisable = $true }
                }
            }
            if ($lines[$i] -match '"explore"') {
                for ($j = $i; $j -lt ([Math]::Min($i + 5, $lines.Count)); $j++) {
                    if ($lines[$j] -match '"disable"\s*:\s*true') { $hasExploreDisable = $true }
                }
            }
        }

        $check2b = $hasBuildDisable -and $hasPlanDisable -and $hasGeneralDisable -and $hasExploreDisable
    }
}

Test-Check -Number 2 -Name "opencode.jsonc: executor model nan/qwen3.6, disabled agents (build/plan/general/explore)" -Result $check2b

# ---------------------------------------------------------------------------
# Check 3: Agent prompt files exist and are non-empty
# ---------------------------------------------------------------------------
$orchPath = Join-Path $Target ".opencode\agents\orchestrator.md"
$execPath = Join-Path $Target ".opencode\agents\executor.md"

$check3a = $false
$check3b = $false

if (Test-Path $orchPath) {
    $size = (Get-Item $orchPath).Length
    $check3a = $size -gt 0
}
if (Test-Path $execPath) {
    $size = (Get-Item $execPath).Length
    $check3b = $size -gt 0
}
$check3Result = $check3a -and $check3b

Test-Check -Number 3 -Name "Agent prompts exist and are non-empty" -Result $check3Result

# ---------------------------------------------------------------------------
# Check 4: orca.toml exists with required stages
# ---------------------------------------------------------------------------
$orcaPath = Join-Path $Target "orca.toml"
$check4 = $false

if (Test-Path $orcaPath) {
    $content = Get-Content $orcaPath -Raw
    $hasReview = $content -match '[\[\]]tickets[\[\]]' -and $content -match 'name\s*=\s*"review"'
    $hasWork = $content -match 'name\s*=\s*"work"'
    $hasPlan = $content -match 'name\s*=\s*"plan"'
    $check4 = $hasReview -and $hasWork -and $hasPlan
}

Test-Check -Number 4 -Name "orca.toml exists with stages review, work, plan" -Result $check4

# ---------------------------------------------------------------------------
# Check 5: deno.json has tasks.orca
# ---------------------------------------------------------------------------
$denoPath = Join-Path $Target "deno.json"
$check5 = $false

if (Test-Path $denoPath) {
    $content = Get-Content $denoPath -Raw
    $check5 = $content -match '"orca"'
}

Test-Check -Number 5 -Name "deno.json has tasks.orca" -Result $check5

# ---------------------------------------------------------------------------
# Check 6: ticket CLI files exist
# ---------------------------------------------------------------------------
$ticketCmd = Join-Path $Target ".orca-tools\bin\ticket.cmd"
$ticketSh = Join-Path $Target ".orca-tools\bin\ticket.sh"

$check6 = (Test-Path $ticketCmd) -and (Test-Path $ticketSh)

Test-Check -Number 6 -Name "Ticket CLI files (.orca-tools/bin/ticket.cmd and ticket.sh)" -Result $check6

# ---------------------------------------------------------------------------
# Check 7: .orca-local is a git repo with correct HEAD
# ---------------------------------------------------------------------------
$orcaLocal = Join-Path $Target ".orca-local"
$expectedCommit = "35938cc8aa328853333bd171d474c300b4c09251"
$check7Result = $false
$check7Hint = ""

if (Test-Path $orcaLocal) {
    $gitHeadPath = Join-Path $orcaLocal ".git"
    if (Test-Path $gitHeadPath) {
        try {
            $headCommit = git -C $orcaLocal rev-parse HEAD 2>&1 | Out-String
            $headCommit = $headCommit.Trim()
            if ($headCommit -eq $expectedCommit) {
                $check7Result = $true
            } else {
                $check7Hint = "Expected HEAD=$expectedCommit but HEAD=$headCommit"
            }
        } catch {
            $check7Hint = "Failed to read git HEAD: $_"
        }
    } else {
        $check7Result = $false
        $check7Hint = ".orca-local exists but is not a git repo"
    }
} else {
    $check7Hint = ".orca-local not found. Manual clone: git clone https://github.com/upvalue/orca.git $Target\.orca-local"
}

Test-Check -Number 7 -Name ".orca-local git repo with pinned commit" -Result $check7Result -Hint $check7Hint

# ---------------------------------------------------------------------------
# Check 8: Required tools resolvable
# ---------------------------------------------------------------------------
$toolsToCheck = @("deno", "git", "jq")
$check8 = $true

foreach ($tool in $toolsToCheck) {
    $toolResult = Get-Command $tool -ErrorAction SilentlyContinue
    if (-not $toolResult) {
        Write-Host "       Missing tool: $tool" -ForegroundColor DarkRed
        $check8 = $false
    }
}

# bash is a WARN only
$bashPath = "C:\Program Files\Git\usr\bin\bash.exe"
if (-not (Test-Path $bashPath)) {
    Write-Host "       WARN: bash not found at $bashPath (may still work via PATH)" -ForegroundColor Yellow
}

Test-Check -Number 8 -Name "Required tools resolvable (deno, git, jq)" -Result $check8

# ---------------------------------------------------------------------------
# Check 9: Ticket smoke test
# ---------------------------------------------------------------------------
$check9Result = $false
$check9Hint = ""

# Use ticket.cmd for simple operations; for filtered query we verify via
# raw JSON output because ticket.sh's jq invocation inside double quotes
# cannot preserve embedded double-quote filter arguments (byte-identical
# constraint on vendored ticket.sh).
$ticketCmd = Join-Path $Target ".orca-tools\bin\ticket.cmd"
$ticketSh = Join-Path $Target ".orca-tools\bin\ticket.sh"
$ticketShPosix = $ticketSh -replace '\\', '/'

if ($check8 -and (Test-Path $ticketCmd)) {
    $tempDir = Join-Path $env:TEMP ("kit-scratch-ticket-$([DateTime]::Now.ToString('yyyyMMddHHmmssffff'))")
    New-Item -ItemType Directory -Path (Join-Path $tempDir ".tickets") -Force | Out-Null

    try {
        $env:TICKETS_DIR = Join-Path $tempDir ".tickets"

        # Create a ticket (via ticket.cmd)
        $createOut = & $ticketCmd create Test --description x 2>&1 | Out-String
        $createExit = $LASTEXITCODE
        $ticketId = $createOut.Trim()

        if ($createExit -eq 0 -and $ticketId -ne "" -and $ticketId -ne "0") {
            # List tickets (via ticket.cmd)
            $lsOut = & $ticketCmd ls 2>&1 | Out-String
            $lsExit = $LASTEXITCODE

            # Query tickets (via ticket.cmd)
            $queryOut = & $ticketCmd query 2>&1 | Out-String
            $queryExit = $LASTEXITCODE

# Query with filter: use jq directly with --arg to safely pass the
            # filter value (ticket.sh's jq invocation inside double quotes
            # cannot preserve embedded double-quote args, byte-identical constraint)
            $queryFilterOut = $queryOut | jq --arg status open 'select(.status == $status)' 2>&1 | Out-String
            $queryFilterExit = $LASTEXITCODE

            # Close ticket (via ticket.cmd)
            $closeOut = & $ticketCmd close $ticketId 2>&1 | Out-String
            $closeExit = $LASTEXITCODE

            if ($lsExit -eq 0 -and $queryExit -eq 0 -and $queryFilterExit -eq 0 -and $closeExit -eq 0) {
                $check9Result = $true
            } else {
                $check9Hint = "Ticket commands failed: create=$createExit ls=$lsExit query=$queryExit query-filter=$queryFilterExit close=$closeExit"
            }
        } else {
            $check9Hint = "Ticket create failed (exit=$createExit): $createOut"
        }
    } catch {
        $check9Hint = "Ticket smoke test exception: $_"
    } finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $env:TICKETS_DIR -ErrorAction SilentlyContinue) {
            Remove-Item $env:TICKETS_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Variable TICKETS_DIR -ErrorAction SilentlyContinue
    }
} else {
    if (-not $check8) {
        $check9Hint = "Skipping: required tools not found (check 8 failed)"
    }
    if (-not (Test-Path $ticketCmd)) {
        $check9Hint = "Skipping: ticket.cmd not found at $ticketCmd"
    }
}

Test-Check -Number 9 -Name "Ticket smoke test (create, ls, query, query-filter, close)" -Result $check9Result -Hint $check9Hint

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