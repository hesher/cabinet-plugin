# /cabinet:process

Fold raw notes into summary pages, one subagent per role, in parallel.
Nothing triggers this automatically, on purpose — run it by hand when a
role's raw notes pile up.

## Procedure

1. Find the cabinet (working directory + up to 3 parents, then registry,
   then `project_roots` — same rule as `/cabinet-ensure`).
2. List roles: subfolders with `raw/` or `ROLE.md`, unioned with the
   plugin defaults; never `hooks/`, `specs/`, or `shared/`.
3. One subagent per role, in parallel.
4. Each subagent runs `scripts/scan.sh <cabinet> <role>` to list notes no
   page cites yet. A citation is `[[raw/<stem>|src: <stem>]]` in any
   `pages/*.md`.
5. The subagent merges each uncited note into an existing page, creates a
   new page, or just adds a citation.
6. Writes go through `scripts/apply.sh`:

   ```
   apply.sh --cabinet <dir> --role <role> --page <name.md> [--dry-run] [--allow-first-touch-merge] < content
   ```

   Input must start with `---`. If a human edited the page since the last
   synthesis, `apply.sh` writes `<page>.proposed.md` beside it instead of
   overwriting. `log.md` records each write; it is memory bookkeeping,
   not memory — the start hook never loads it.
7. Finish with `scan.sh --validate <cabinet> <role>`: every note must be
   cited or listed in `pages/.processed-skip` (one stem per line, `#`
   comments allowed).

## Page shape

```markdown
---
source: synthesized
synthesized_from: [2026-07-22_androidrec-simulator-backend]
last_synthesized_at: 2026-07-22T22:00:00Z
schema_version: 1
---
# Title
> One-line subtitle

## Section
- Claim. [[raw/2026-07-22_androidrec-simulator-backend|src: 2026-07-22_androidrec-simulator-backend]]

## Related Pages
- [[other-page]] — why it's related
```

`last_synthesized_at` is stamped at write time inside `apply.sh`.
