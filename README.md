# OpenCode + Orca Nanite Orchestrator Kit

A reusable kit for setting up a two-agent orchestration workflow powered by [OpenCode](https://opencode.ai) and [Orca](https://github.com/upvalue/orca).

## Architecture

```
Orca (orca.toml) ──► OpenCode server ──► orchestrator (glm5.3-flash, read-only)
                                              │
                                              ▼
                                        executor (qwen3.6, code via bounded contracts)
```

- **Orca** is the ticket-driven agent orchestrator. It reads `orca.toml` stages and dispatches work based on ticket tags.
- **OpenCode** is the agent runtime with a JSON config (`opencode.jsonc`) defining models, permissions and prompts.
- **orchestrator** (GLM 5.3 Flash) handles planning, decomposition, verification and delegation. It has **read-only** access to implementation files.
- **executor** (Qwen 3.6) writes code and tests only under bounded work contracts delegated by the orchestrator.

## Requirements

- **OpenCode** with NaN provider configured, exposing models:
  - `nan/glm5.3-flash`
  - `nan/qwen3.6`
- **Deno** 2.x
- **Git for Windows** (must include `bash` at `C:\Program Files\Git\usr\bin\bash.exe`)
- **jq** (used by the ticket query plugin)

## Quick Start

```powershell
# Install the kit into a consuming project
.\scripts\install.ps1 -Target G:\_Proyectos\MiProyecto

# Verify the installation
.\scripts\verify.ps1 -Target G:\_Proyectos\MiProyecto
```

## What Gets Installed

| Kit source                     | Target location                          |
|-------------------------------|------------------------------------------|
| `templates/opencode.jsonc`    | `<project>/opencode.jsonc`               |
| `templates/orca.toml`         | `<project>/orca.toml`                    |
| `templates/deno.json`         | `<project>/deno.json`                    |
| `templates/orca-local.ps1`    | `<project>/scripts/orca-local.ps1`       |
| `templates/env.example`       | `<project>/.env.example`                 |
| `templates/.opencode/agents/*`| `<project>/.opencode/agents/*`           |
| `vendored/ticket/bin/*`       | `<project>/.orca-tools/bin/*`            |
| `vendor-config/orca.version`  | (used by install to record clone target) |
| (cloned) upvalue/orca         | `<project>/.orca-local/`                 |

## License Notes

- **This kit** is private/all-rights-reserved. No `LICENSE` file is included intentionally — the kit is a configuration scaffold, not redistributable code.
- **ticket** CLI (vendored in `vendored/ticket/`) is licensed under MIT by the wedow/ticket contributors. See `vendored/ticket/LICENSE` for full text. Modifications for Windows compatibility are documented there.
- **orca** (`upvalue/orca`) is upstream UNLICENSED. It is cloned at install time from the pinned commit; its source is never redistributed by this kit.

## Documentation

See [`docs/INTEGRATION.md`](docs/INTEGRATION.md) for workflow tags, manual bootstrap steps and integration notes.