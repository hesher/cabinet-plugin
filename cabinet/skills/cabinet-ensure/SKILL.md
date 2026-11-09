# /cabinet-ensure

Create and register a cabinet, idempotently.

## Procedure

1. Look for `cabinet/` in the working directory and up to 3 parents. A
   folder counts as a cabinet when it has `META.md` or a `chief_of_staff/`
   subfolder (same rule as the SessionStart hook and the registry doctor).
2. Already present AND registered (its path appears in
   `~/.cabinet/registry.json`): silent no-op. Say only that the cabinet
   already exists.
3. Folder present, not registered: add a registry entry named after the
   project folder with empty `topics`. A failed registry write is a
   warning, not an abort.
4. Neither present nor registered: ask `No cabinet here yet. Want me to set
   one up? (y/n)`. Anything but a clear yes writes nothing.
5. On yes: run `scaffold_cabinet` from `hooks/lib/scaffold.sh` (8 default
   roles, each with `raw/` and `pages/`), then register as in step 3, then
   print the 4-line team intro:

   ```
   Cabinet team assembled: chief of staff, engineer, tech lead, designer,
   marketing, researcher, recruiter — and the villain, who reviews.
   Notes live in cabinet/<role>/raw/. Pages fold them up via /cabinet:process.
   Your next session will remember this one.
   ```

6. Never reference `/cabinet-init`: it no longer exists.
