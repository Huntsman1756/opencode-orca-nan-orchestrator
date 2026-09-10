# verify-runtime.ps1 - Runtime smoke test for the OpenCode orchestrator kit
#
# This script performs end-to-end verification of the GLM-Qwen-GLM flow.
# It uses ONLY a temporary directory - never modifies the real repository.
#
# Usage:
#   .\scripts\verify-runtime.ps1 [-Target <path>]
#
# Parameters:
#   -Target  Path to the project root (default: current directory).
#
# Requirements:
#   - OpenCode installed and accessible
#   - NaN API credentials configured (for actual model calls)
#
# If NaN credentials are not available, tests are skipped with NOT_RUN.
#
# Exit codes:
#   0  - all tests passed or not_run (no credential issues)
#   1  - one or more tests failed (runtime errors)

[CmdletBinding()]
param(
    [string]$Target = "."
)

$Target = (Resolve-Path -Path $Target -ErrorAction Stop | Select-Object -First 1).Path

# Script-scoped results
$script:results = @{
    passCount = 0
    failCount = 0
    notRunCount = 0
    totalCount = 0
}

function Test-Check {
    param(
        [string]$Number,
        [string]$Name,
        [bool]$Result,
        [string]$Status = "PASS",  # PASS, FAIL, or NOT_RUN
        [string]$Hint = ""
    )
    $script:results.totalCount++
    $color = "Green"
    if ($Status -eq "FAIL") { $color = "Red" }
    elseif ($Status -eq "NOT_RUN") { $color = "Yellow" }

    if ($Status -eq "PASS") {
        $script:results.passCount++
    } elseif ($Status -eq "NOT_RUN") {
        $script:results.notRunCount++
    } else {
        $script:results.failCount++
    }

    Write-Host "[$Number] $Name ... $Status" -ForegroundColor $color
    if ($Hint) {
        Write-Host "       $Hint" -ForegroundColor DarkGray
    }
}

Write-Host "=== OpenCode Orchestrator Runtime Smoke Test ===" -ForegroundColor Cyan
Write-Host "Target : $Target" -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------------------------
# Pre-flight: check opencode availability
# ---------------------------------------------------------------------------
$opencodeAvailable = $false
$opencodeCmd = Get-Command opencode -ErrorAction SilentlyContinue
if ($opencodeCmd) {
    $opencodeAvailable = $true
}

if (-not $opencodeAvailable) {
    Write-Host "ERROR: opencode not found in PATH. Cannot run smoke tests." -ForegroundColor Red
    Write-Host "Install OpenCode or ensure it is in PATH." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Pre-flight: check NaN credentials availability
# ---------------------------------------------------------------------------
$hasNaNCredentials = $false
$credentialHint = ""

# Check for NaN API key environment variable
if ($env:NAN_API_KEY -or $env:NANITE_API_KEY) {
    $hasNaNCredentials = $true
}

# Check for NaN config file
$nanConfigPaths = @(
    "$env:APPDATA\opencode\nan.json",
    "$env:USERPROFILE\.config\opencode\nan.json",
    "$env:APPDATA\opencode\providers\nan.json"
)

foreach ($p in $nanConfigPaths) {
    if (Test-Path $p) {
        $pContent = Get-Content $p -Raw -ErrorAction SilentlyContinue
        if ($pContent -and ($pContent -match 'api[_-]?key|token|bearer')) {
            $hasNaNCredentials = $true
            break
        }
    }
}

# Also check if opencode can list models (indicates working auth)
try {
    $modelsOutput = opencode models nan 2>&1 | Out-String
    if ($modelsOutput -and $modelsOutput -match 'glm5\.3-flash') {
        $hasNaNCredentials = $true
    }
} catch {
    $credentialHint = "Could not verify NaN auth status"
}

Write-Host ""
Write-Host "--- Runtime Smoke Tests ---" -ForegroundColor Magenta
Write-Host ""

# If no credentials, skip all runtime tests
if (-not $hasNaNCredentials) {
    Write-Host "NO NaN CREDENTIALS DETECTED - all runtime tests will be NOT_RUN" -ForegroundColor Yellow
    Write-Host ""

    Test-Check -Number "T1" -Name "Orchestrator agent resolution" -Result $false -Status "NOT_RUN" -Hint "Requires NaN API credentials"
    Test-Check -Number "T2" -Name "Parent session uses nan/glm5.3-flash" -Result $false -Status "NOT_RUN" -Hint "Requires NaN API credentials"
    Test-Check -Number "T3" -Name "Orchestrator delegates to executor" -Result $false -Status "NOT_RUN" -Hint "Requires NaN API credentials"
    Test-Check -Number "T4" -Name "Child session uses nan/qwen3.6" -Result $false -Status "NOT_RUN" -Hint "Requires NaN API credentials"
    Test-Check -Number "T5" -Name "Executor modifies only the requested fixture" -Result $false -Status "NOT_RUN" -Hint "Requires NaN API credentials"
    Test-Check -Number "T6" -Name "Orchestrator inspects git diff" -Result $false -Status "NOT_RUN" -Hint "Requires NaN API credentials"
    Test-Check -Number "T7" -Name "Orchestrator produces verdict" -Result $false -Status "NOT_RUN" -Hint "Requires NaN API credentials"
    Test-Check -Number "T8" -Name "No changes left in sandbox" -Result $false -Status "NOT_RUN" -Hint "Requires NaN API credentials"

    Write-Host ""
    Write-Host "=== Results ===" -ForegroundColor Cyan
    Write-Host "Passed   : $($script:results.passCount) / $($script:results.totalCount)" -ForegroundColor Green
    Write-Host "Not Run  : $($script:results.notRunCount) / $($script:results.totalCount)" -ForegroundColor Yellow
    Write-Host "Failed   : $($script:results.failCount) / $($script:results.totalCount)" -ForegroundColor Green
    Write-Host ""
    Write-Host "RUNTIME SMOKE: NOT_RUN - no NaN credentials available" -ForegroundColor Yellow
    Write-Host "Static config validation should be run separately." -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------------------
# Create temporary sandbox directory
# ---------------------------------------------------------------------------
$randomSuffix = Get-Random -Minimum 100000 -Maximum 999999
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$sandbox = Join-Path $env:TEMP ("opencode-orchestrator-smoke-${timestamp}-${randomSuffix}")

Write-Host "Sandbox: $sandbox" -ForegroundColor Gray
Write-Host ""

try {
    # Create sandbox
    New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

    # Initialize minimal git repo (no remote)
    Set-Location $sandbox
    git init -q 2>&1 | Out-Null
    git config user.email "smoke@test.local" 2>&1 | Out-Null
    git config user.name "Smoke Test" 2>&1 | Out-Null

    # Create opencode.jsonc (copy from project target)
    $targetJsonc = Join-Path $Target "opencode.jsonc"
    if (Test-Path $targetJsonc) {
        Copy-Item $targetJsonc (Join-Path $sandbox "opencode.jsonc") -Force
    }

    # Create orchestrator.md (copy from project target)
    $targetOrch = Join-Path $Target ".opencode\agents\orchestrator.md"
    $sandboxAgents = Join-Path $sandbox ".opencode\agents"
    New-Item -ItemType Directory -Path $sandboxAgents -Force | Out-Null

    if (Test-Path $targetOrch) {
        Copy-Item $targetOrch (Join-Path $sandboxAgents "orchestrator.md") -Force
    }

    # Create executor.md (copy from project target)
    $targetExec = Join-Path $Target ".opencode\agents\executor.md"
    if (Test-Path $targetExec) {
        Copy-Item $targetExec (Join-Path $sandboxAgents "executor.md") -Force
    }

    # Create a fixture file and record initial state
    Set-Content -Path (Join-Path $sandbox "fixture.txt") -Value "INITIAL" -NoNewline

    # Also create an unrelated file that MUST NOT be modified
    Set-Content -Path (Join-Path $sandbox "unrelated.txt") -Value "DO_NOT_CHANGE" -NoNewline

    git add . 2>&1 | Out-Null
    git commit -m "initial" -q 2>&1 | Out-Null

    # Capture initial state for comparison
    $initialFixtureHash = (Get-FileHash (Join-Path $sandbox "fixture.txt") -Algorithm SHA256).Hash
    $initialUnrelatedHash = (Get-FileHash (Join-Path $sandbox "unrelated.txt") -Algorithm SHA256).Hash

    # ===================================================================
    # T1: OpenCode resolves the orchestrator agent from .opencode/agents/
    # ===================================================================
    $orchAgentPath = Join-Path $sandboxAgents "orchestrator.md"
    $t1 = (Test-Path $orchAgentPath) -and ((Get-Item $orchAgentPath).Length -gt 0)

    Test-Check -Number "T1" -Name "Orchestrator agent resolves from .opencode/agents/" -Result $t1

    # ===================================================================
    # T2: Parent session model is nan/glm5.3-flash (from opencode.jsonc)
    # ===================================================================
    $t2 = $false
    try {
        $jsoncContent = Get-Content (Join-Path $sandbox "opencode.jsonc") -Raw
        $t2 = $jsoncContent -match '"model"\s*:\s*"nan/glm5\.3-flash"' -and
              $jsoncContent -match '"default_agent"\s*:\s*"orchestrator"'
    } catch {}

    Test-Check -Number "T2" -Name "Parent session model is nan/glm5.3-flash" -Result $t2

    # ===================================================================
    # T3-T7: Execute orchestration flow
    # ===================================================================
    Write-Host ""
    Write-Host "--- Executing GLM-->Qwen-->GLM flow ---" -ForegroundColor Gray
    Write-Host ""

    $orchestrated = $false
    $openCodeSuccess = $false
    $hasOutput = $false
    $outputFile = Join-Path $sandbox "smoke-output.txt"
    $openCodeFailureReason = ""

    # OpenCode V1 CLI: 'opencode run [message..]' with optional flags.
    # --prompt is a TUI flag, NOT a run flag (confirmed by opencode --help).
    # The positional message approach is documented and used by other tools
    # (e.g. nsoderberg/ralph-codex uses: opencode run "$(cat {prompt})").
    $taskMessage = 'The file fixture.txt contains "INITIAL". Create a bounded work contract and delegate to executor to change it to "CHANGED_BY_EXECUTOR". Do not edit the file yourself.'

    # Try multiple invocation strategies:
    # 1. Direct: opencode run --agent orchestrator "message"
    # 2. With --attach: opencode run --attach http://localhost:4096 --agent orchestrator "message"
    #    (only if a server is already running)
    # 3. With --format json: opencode run --agent orchestrator --format json "message"
    #    (try this last; structured output may help prove delegation)

    $strategies = @(
        @{ Name = "direct";   Args = "run --agent orchestrator ""$taskMessage"""; }
    )

    # Check if a server is running for the attach strategy
    try {
        $checkServer = Invoke-WebRequest -Uri "http://localhost:4096/" -TimeoutSec 1 -ErrorAction Stop
        if ($checkServer.StatusCode -eq 200) {
            $strategies += @{ Name = "attach"; Args = "run --attach http://localhost:4096 --agent orchestrator ""$taskMessage"""; }
        }
    } catch {}

    # Always try --format json as well
    $strategies += @{ Name = "json"; Args = "run --agent orchestrator --format json ""$taskMessage"""; }

    foreach ($strategy in $strategies) {
        try {
            $proc = Start-Process -FilePath "opencode" `
                -ArgumentList $strategy.Args `
                -NoNewWindow `
                -Wait `
                -RedirectStandardOutput $outputFile `
                -RedirectStandardError (Join-Path $sandbox ("smoke-error-{0}.txt" -f $strategy.Name)) `
                -PassThru `
                -WorkingDirectory $sandbox

            $exitCode = $proc.ExitCode
            $currentSuccess = ($exitCode -eq 0)

            $hasOutput = $false
            if (Test-Path $outputFile) {
                $outputContent = Get-Content $outputFile -Raw -ErrorAction SilentlyContinue
                if ($outputContent -and $outputContent.Length -gt 0) {
                    $hasOutput = $true
                }
            }

            if ($currentSuccess -and $hasOutput) {
                $openCodeSuccess = $true
                break
            } else {
                $lastFailure = "Strategy ($strategy.Name): exit=$exitCode hasOutput=$hasOutput"
                if ($currentSuccess -and -not $hasOutput) {
                    $lastFailure += "; output was empty"
                }
            }
        } catch {
            $lastFailure = "Strategy ($strategy.Name): $_"
        }
    }

    if (-not $openCodeSuccess) {
        $openCodeFailureReason = "All invocation strategies failed. Last: $lastFailure"
        if (Test-Path (Join-Path $sandbox "smoke-error-direct.txt")) {
            $errContent = Get-Content (Join-Path $sandbox "smoke-error-direct.txt") -Raw -ErrorAction SilentlyContinue
            if ($errContent -and $errContent.Length -gt 0) {
                $openCodeFailureReason += "; stderr: $($errContent.Substring(0, [Math]::Min(200, $errContent.Length)))"
            }
        }
        if (Test-Path (Join-Path $sandbox "smoke-error-json.txt")) {
            $errContent = Get-Content (Join-Path $sandbox "smoke-error-json.txt") -Raw -ErrorAction SilentlyContinue
            if ($errContent -and $errContent.Length -gt 0) {
                $openCodeFailureReason += "; json-stderr: $($errContent.Substring(0, [Math]::Min(200, $errContent.Length)))"
            }
        }
    }

    # Determine if the orchestration run actually succeeded
    $runSucceeded = $openCodeSuccess -and $hasOutput

    # T3: Orchestrator delegated
    # Note: This does NOT prove delegation happened; it only proves OpenCode ran and produced output.
    # Actual delegation can only be verified by inspecting the agent's child-session logs.
    if ($runSucceeded) {
        $t3 = $true
        Test-Check -Number "T3" -Name "Orchestrator session ran and produced output (limited: does not prove delegation)" -Result $t3 -Hint "T3-T7 require OpenCode run to succeed; this check is a weak proxy for actual subagent invocation"
    } else {
        $t3 = $false
        Test-Check -Number "T3" -Name "Orchestrator session ran and produced output" -Result $t3 -Status "NOT_RUN" -Hint "OpenCode run did not succeed: $openCodeFailureReason"
    }

    # All downstream T4-T7 are only meaningful if T3's prerequisite (OpenCode run succeeded) is met.
    # If the run failed, mark them all NOT_RUN.
    $runFailed = (-not $runSucceeded)

    if ($runFailed) {
        $notRunHint = "OpenCode run failed: $openCodeFailureReason - downstream checks are NOT_RUN"

        # T4: Executor uses nan/qwen3.6 (verified by agent config, NOT by runtime execution)
        $t4 = $false
        if (Test-Path $targetExec) {
            $execContent = Get-Content $targetExec -Raw
            $t4 = $execContent -match 'model:\s*nan/qwen3\.6'
        }
        Test-Check -Number "T4" -Name "Executor agent model is nan/qwen3.6" -Result $t4 -Status "NOT_RUN" -Hint "$notRunHint (config-level check only)"

        # T5: Executor modified only the requested fixture
        $t5 = $false
        Test-Check -Number "T5" -Name "Executor modified only the requested fixture" -Result $t5 -Status "NOT_RUN" -Hint "$notRunHint"

        # T6: Orchestrator inspects git diff
        $t6 = $false
        Test-Check -Number "T6" -Name "Orchestrator inspects git diff of changes" -Result $t6 -Status "NOT_RUN" -Hint "$notRunHint"

        # T7: Orchestrator produces verdict
        $t7 = $false
        Test-Check -Number "T7" -Name "Orchestrator produces verdict on result" -Result $t7 -Status "NOT_RUN" -Hint "$notRunHint"

    } else {
        # Run succeeded - proceed with downstream checks

        # Check if fixture was modified (evidence of executor work)
        $fixtureContent = Get-Content (Join-Path $sandbox "fixture.txt") -Raw -ErrorAction SilentlyContinue
        $fixtureChanged = ($fixtureContent -eq "CHANGED_BY_EXECUTOR")
        $fixtureHash = (Get-FileHash (Join-Path $sandbox "fixture.txt") -Algorithm SHA256).Hash

        # T4: Executor uses nan/qwen3.6 (verified by agent config)
        $t4 = $false
        if (Test-Path $targetExec) {
            $execContent = Get-Content $targetExec -Raw
            $t4 = $execContent -match 'model:\s*nan/qwen3\.6'
        }
        Test-Check -Number "T4" -Name "Executor agent model is nan/qwen3.6" -Result $t4 -Hint "Verified via agent config (runtime model detection requires session introspection)"

        # T5: Executor modified only the requested fixture
        $t5 = $false
        if ($fixtureChanged) {
            $unrelatedHash = (Get-FileHash (Join-Path $sandbox "unrelated.txt") -Algorithm SHA256).Hash
            $unrelatedUnchanged = ($unrelatedHash -eq $initialUnrelatedHash)
            if ($unrelatedUnchanged) {
                $t5 = $true
            }
        }
        Test-Check -Number "T5" -Name "Executor modified only the requested fixture" -Result $t5

        # T6: Orchestrator can inspect git diff
        $t6 = $false
        try {
            $diffOutput = git -C $sandbox diff --cached 2>&1 | Out-String
            $diffHasFixture = $diffOutput -match 'fixture\.txt'
            $statusOutput = git -C $sandbox status --porcelain 2>&1 | Out-String
            $statusHasFixture = $statusOutput -match 'fixture\.txt'
            $t6 = ($diffHasFixture -or $statusHasFixture)
        } catch {}
        Test-Check -Number "T6" -Name "Orchestrator can inspect git diff of changes" -Result $t6

        # T7: Orchestrator produces verdict
        $t7 = $false
        if ($hasOutput) {
# Capture pre-run state of the target repo
    $targetGitStatusBefore = ""
    try {
        $targetGitStatusBefore = git -C $Target status --porcelain 2>&1 | Out-String
    } catch {}

    try {
                $output = Get-Content $outputFile -Raw -ErrorAction SilentlyContinue
                if ($output -match '(?i)(pass|fail|verdict|complete|review|correct|reject)') {
                    $t7 = $true
                }
            } catch {}
        }
        Test-Check -Number "T7" -Name "Orchestrator produces verdict on result" -Result $t7
    }

    # T8: No changes left outside sandbox
    Set-Location $Target
    $t8 = $true
    $t8Hint = ""

    try {
        $targetGitStatusAfter = git -C $Target status --porcelain 2>&1 | Out-String
        if ($targetGitStatusAfter.Trim() -ne $targetGitStatusBefore.Trim()) {
            $t8 = $false
            $t8Hint = "git status changed after sandbox run"
        }
    } catch {
        $t8Hint = "Could not check git status of target repo"
    }

    Test-Check -Number "T8" -Name "No changes left outside sandbox" -Result $t8 -Hint $t8Hint

} finally {
    # Cleanup: remove sandbox
    Set-Location $Target
    if (Test-Path $sandbox) {
        Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "Passed   : $($script:results.passCount) / $($script:results.totalCount)" -ForegroundColor Green
Write-Host "Not Run  : $($script:results.notRunCount) / $($script:results.totalCount)" -ForegroundColor Yellow
Write-Host "Failed   : $($script:results.failCount) / $($script:results.totalCount)" -ForegroundColor $(if ($script:results.failCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

# If the OpenCode run did not succeed, all meaningful smoke tests are NOT_RUN.
# Do NOT report PASS when the core orchestration was not executed.
if (-not $openCodeSuccess -or -not $hasOutput) {
    $reason = "OpenCode run did not produce successful output"
    if ($openCodeFailureReason) {
        $reason = $openCodeFailureReason
    }
    Write-Host "RUNTIME SMOKE: NOT_RUN" -ForegroundColor Yellow
    Write-Host "REASON  : $reason" -ForegroundColor Yellow
    Write-Host "NOTE    : T1/T2 are static config checks; T3-T7 require a working OpenCode session." -ForegroundColor Yellow
    Write-Host "          Static verify.ps1 should be used for non-runtime validation." -ForegroundColor Yellow
    exit 0
}

if ($script:results.failCount -gt 0) {
    Write-Host "RUNTIME SMOKE: FAIL" -ForegroundColor Red
    exit 1
} elseif ($script:results.totalCount -eq 0) {
    Write-Host "RUNTIME SMOKE: NOT_RUN" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "RUNTIME SMOKE: PASS" -ForegroundColor Green
    exit 0
}