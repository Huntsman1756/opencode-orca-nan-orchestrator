# Integration Guide

> **IMPORTANT: This guide documents the OPTIONAL / ADVANCED Orca ticket mode.**
>
> The CORE kit (OpenCode orchestrator + executor) does **not** require Orca, Deno, jq, or any ticket system.
> See [`README.md`](../README.md) for the minimal CORE setup.

This document describes how a consuming project integrates with the OpenCode + Orca orchestration kit **when installed with `-WithOrca`**.

## Workflow Tags

The kit uses a tag-based workflow managed by `orca.toml` stages:

| Tag                | Meaning                          | Acting agent     | orca.toml stage  |
|--------------------|----------------------------------|------------------|------------------|
| `needs-plan`       | Ticket needs decomposition       | orchestrator     | plan             |
| `ready-for-work`   | Decomposed, ready for implementation | orchestrator | work             |
| `ready-for-review` | Implementation complete          | orchestrator     | review           |
| `verified`         | Passed review                    | — (inactionable) | verified         |
| `blocked`          | Blocked by external condition    | — (inactionable) | blocked         |
| `needs-human-decision` | Requires human input          | — (inactionable) | human-decision   |

### Flow

```
needs-plan ──► ready-for-work ──► ready-for-review ──► verified (closed)
    │              │                    │
    │              ▼                    ▼
    │       blocked               needs-human-decision
    │       (stuck)               (stuck)
    └───► ready-for-work (retry)
```

The `orca.toml` stages are evaluated in order: review, work, plan. Within each stage, tickets matching the `match` criteria are dispatched to the OpenCode orchestrator.

## Adding Project-Specific Rules

The kit is designed so that consuming projects add their OWN rules layer without touching the kit files:

1. **Agent prompt customization** — The agent prompt templates are in `.opencode/agents/`. Each consuming project can edit these directly for project-specific language, safety rules and conventions.

2. **Project-specific `orca.toml` additions** — After installation with `-WithOrca`, the consuming project has its own copy of `orca.toml`. Add new stages, modify existing prompts, or add project-specific tags by editing this copy.

3. **Additional tools** — Project-specific scripts in `.orca-tools/` or `scripts/` can be added independently.

## Manual Orca Bootstrap

If `install.ps1 -WithOrca` could not clone orca (e.g., no network), run manually:

```powershell
git clone https://github.com/upvalue/orca.git .orca-local
git -C .orca-local checkout 35938cc8aa328853333bd171d474c300b4c09251
```

After bootstrapping, re-run `.\scripts\verify.ps1` to confirm.

## deno.json Merge Note

If the target project already has a `deno.json`, the installer with `-WithOrca` will refuse (fail-closed). In that case:

1. Manually merge the two `deno.json` files.
2. Ensure these keys exist in the final file:
   ```json
   {
     "tasks": {
       "orca": "deno run --env-file --allow-run --allow-env --allow-net --allow-read .orca-local/cli.ts",
       "orca:plan": "deno run --env-file --allow-run --allow-env --allow-net --allow-read .orca-local/cli.ts plan"
     }
   }
   ```

## verify.ps1 Exit Codes

| Exit code | Meaning                                      |
|-----------|----------------------------------------------|
| `0`       | All checks passed                            |
| `1`       | One or more checks failed (printed above)    |

## Environment Variables

| Variable      | Description                              | Default                   |
|---------------|------------------------------------------|---------------------------|
| `OPENCODE_URL`| OpenCode server endpoint                 | `http://localhost:4096`   |
| `TICKETS_DIR` | Directory for ticket markdown files       | auto-detected (`.tickets`) |

A template `.env.example` is included — copy it to `.env` and adjust as needed.