# Cabinet v1.1.0

A per-project team of eight AI specialists (chief of staff, engineer,
tech lead, product designer, marketing, researcher, recruiter, and the
villain) for Claude Code. Each specialist's memory is a folder of small
markdown notes in the project: `cabinet/<role>/raw/` for notes,
`cabinet/<role>/pages/` for summaries built from them.

## How it works

- A **SessionStart** hook finds the cabinet, loads every role's manifesto
  and memory into context, and writes a session marker.
- A **Stop** hook refuses to let a substantive session stop until notes
  stamped with this session's id exist and are valid — then prints a
  `Cabinet saved` receipt.
- A **PostToolUse** hook warns when a `Write` creates a badly named or
  malformed note. (Notes written via Bash heredocs skip it; the Stop
  hook validates those, including `schema_version`.)
- `/cabinet <topic>` convenes the specialists as parallel subagents. A
  Chief of Staff merges their answers; the Villain attacks the result —
  on Codex when available, on Claude (opus-high) with a disclosure line
  when not.
- `/cabinet commit` writes this session's notes (one per role that
  learned something; refuses within 5 minutes unless `--force`).
- `/cabinet:process` folds raw notes into pages. `/cabinet-ensure`
  creates and registers a cabinet, idempotently.

There is deliberately **no SessionEnd hook**: notes are written
in-session and the Stop guard validates them. Hooks are registered by the
plugin (`hooks/hooks.json`), not by `~/.claude/settings.json`.

## Roles (8)

chief_of_staff, engineer, tech_lead, product_designer, marketing,
researcher, recruiter, the_villain. Discovery: a subfolder with `raw/`
or `ROLE.md`, unioned with these defaults — never `hooks/`, `specs/`,
`shared/`, or a folder with neither.

## Tunables

| Var | Default | Meaning |
|---|---|---|
| `CABINET_FLUSH_THRESHOLD_SECS` | 180 | session age before saves are required |
| `CABINET_FRESHNESS_SECS` | 1800 | a save older than this re-blocks |
| `CABINET_MAX_BLOCKS` | 5 | blocks before enforcement stands down |
| `CABINET_ROLE_LINES` | 200 | memory lines per role in the brief |
| `CABINET_BRIEF_MAX_BYTES` | 40960 | global brief cap; oldest memory trimmed first |
| `CABINET_PROCESS_NUDGE_THRESHOLD` | 10 | notes before the save helper nudges |
| `CABINET_CODEX_MODEL` / `CODEX_HOME` | config | Villain bridge model resolution |
| `CABINET_CODEX_TIMEOUT` | 480 | Villain bridge timeout (secs) |
| `CABINET_REGISTRY_PATH` | `~/.cabinet/registry.json` | registry override (tests) |
| `CABINET_CONFIG_PATH` | `~/.cabinet/config.json` | config override (doctor) |

## Dead fields (documented, not revived)

- `last_flush` (registry entries): nothing writes it; new entries omit
  it and it is stripped on read.
- `auto_triage` (config): nothing reads it; ignored.
- `emit_stop` (Stop hook helper): removed.
- `CABINET_SKIP_STOP_GUARD` (0.1.0): has no effect in v1.1.0; skipping
  one Stop check is `touch <state>/.cabinet-flush-skip-<id>` with the id
  from the start brief or the block message.

See [MIGRATION.md](MIGRATION.md) for 0.1.0 → 1.1.0 and
[META.md](META.md) for the audit fields.
