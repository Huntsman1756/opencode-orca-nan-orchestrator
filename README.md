# OpenCode Orchestrator Kit

A minimal two-agent orchestration kit powered by [OpenCode](https://opencode.ai) with NaN models.

## Architecture

```
OpenCode
├── orchestrator → nan/glm5.3-flash  (plans, delegates, reviews)
└── executor     → nan/qwen3.6       (implements bounded contracts)
```

**GLM plans → Qwen implements → GLM verifies.**

OpenCode provides native parent→subagent orchestration. The orchestrator (GLM 5.3 Flash) handles planning, decomposition, verification and delegation. The executor (Qwen 3.6) implements bounded work contracts.

The executor has unrestricted `bash`/Git permissions. Scope control comes from the bounded work contract and orchestrator review, not command-level Git deny rules.

## Requirements

- **OpenCode** installed with NaN provider configured, exposing:
  - `nan/glm5.3-flash`
  - `nan/qwen3.6`

That is all. No Deno. No jq. No ticket CLI. No external dependencies.

## Quick Start

```powershell
# 1. Install the kit into a consuming project
.\scripts\install.ps1 -Target G:\_Proyectos\MiProyecto

# 2. Verify the installation
.\scripts\verify.ps1 -Target G:\_Proyectos\MiProyecto

# 3. Start OpenCode
opencode
```

The default agent is `orchestrator` (nan/glm5.3-flash).

## What Gets Installed (CORE)

| Kit source                        | Target location                 |
|-----------------------------------|---------------------------------|
| `templates/opencode.jsonc`        | `<project>/opencode.jsonc`      |
| `templates/.opencode/agents/*`    | `<project>/.opencode/agents/*`  |
| (append)                          | `<project>/.gitignore`          |

## License Notes

- **This kit** is private/all-rights-reserved. No `LICENSE` file is included intentionally.

## Documentation

See [`docs/INTEGRATION.md`](docs/INTEGRATION.md) for workflow details and integration notes.

---

## Optional: Orca Ticket Mode

Orca adds persistent autonomous ticket-driven processing on top of the CORE kit. It requires Deno and is **not installed by default**.

### Install with Orca

```powershell
.\scripts\install.ps1 -Target G:\_Proyectos\MiProyecto -WithOrca
```

This additionally installs:

| Kit source                         | Target location                      |
|------------------------------------|--------------------------------------|
| `templates/orca.toml`              | `<project>/orca.toml`                |
| `templates/deno.json`              | `<project>/deno.json`                |
| `templates/orca-local.ps1`         | `<project>/scripts/orca-local.ps1`   |
| `templates/env.example`            | `<project>/.env.example`             |
| `vendored/ticket/bin/*`            | `<project>/.orca-tools/bin/*`        |
| `vendor-config/orca.version`       | (pinned commit reference)            |
| (cloned) upvalue/orca              | `<project>/.orca-local/`             |

### Requirements for Orca mode

- **Deno** 2.x
- **Git** (for cloning upvalue/orca)
- **jq** (for ticket query filtering, optional but recommended)

### Using Orca

```powershell
# Plan mode (dry-run)
deno task orca:plan

# Interactive loop
deno task orca

# Or via launcher script
.\scripts\orca-local.ps1
```

See [`docs/INTEGRATION.md`](docs/INTEGRATION.md) for workflow tags, ticket lifecycle and integration notes.
