# Migration: 0.1.0 → 1.1.0

## For an existing cabinet

- Notes already use `YYYY-MM-DD_<slug>.md` + `session_id` +
  `schema_version: 1`: no rewrite needed. Legacy `NNNN.md` notes keep
  loading as memory; the Stop hook ignores them (no `session_id`).
- Non-role folders (`hooks/`, `specs/`, `shared/`) are no longer treated
  as roles. Folders without `raw/` or `ROLE.md` are ignored too.
- Legacy `INDEX.md` and `archive/` dirs are ignored (memory excludes
  `index.md`, alongside `log.md`, `*.proposed.md`, `schema.md`).
- Pages now load whenever `pages/*.md` exist — `pages/schema.md` is no
  longer required, and nothing creates it.
- `release_eng/` (or any custom role with `raw/` or `ROLE.md`) still
  loads: discovery unions cabinet folders with the 8 plugin defaults.
- Raw notes order by filename now, not mtime (Drive-safe).
- `/cabinet-init` is gone; use `/cabinet-ensure`.
- The project `CLAUDE.md` line about a SessionEnd flush is stale: there
  is no SessionEnd hook. Saving is enforced by the Stop hook in-session.

## Registry

`~/.cabinet/registry.json` keeps the v1 shape
(`schema_version`, name-keyed `cabinets`). On read:

- `last_flush` entries are stripped (dead field, no longer written).
- The old list shape `{"cabinets": [{name, path, topics}]}` migrates as
  before.
- This Mac's shape `{"version": 1, "cabinets": [{cabinet_id, path:
  <project root>, name, …}]}` also migrates: `path` maps to
  `<path>/cabinet` when that exists, `name` is the key, `topics` is `[]`.
- The original file is backed up to `registry.json.bak` before any
  migration.

## No-effect flags

- `CABINET_SKIP_STOP_GUARD` (0.1.0) has **no effect** in v1.1.0. To skip
  one Stop check: `touch <state>/.cabinet-flush-skip-<id>` with the id
  from the start brief or the block message.
- `auto_triage` in `config.json` is ignored (nothing reads it).
