# /cabinet

Convene the specialists as parallel subagents. The main session
orchestrates only — it never answers the topic itself.

## 1. Locate

Look for `cabinet/` in the working directory and up to 3 parents
(`META.md` or `chief_of_staff/` marks a cabinet), then the registry
(`~/.cabinet/registry.json` via `hooks/lib/registry.sh`), then
`project_roots` from `~/.cabinet/config.json`. If no cabinet is found,
offer setup via `/cabinet-ensure`. (There is no `/cabinet-init`.)

## 2. Parse

- `challenge` / `red team`: the Villain reviews with extra rounds.
- `harden`: fix and re-review up to 3 rounds.
- `@role`: include that role. `all`: include every role.
- `commit`: this skill does not write notes; use `/cabinet commit` instead.
- Empty topic: ask what the question is.

## 3. Read

For each role: its manifesto (cabinet copy first, plugin default second),
then its memory — always the last 3 raw notes by filename sort first,
then pages chosen via `pages/index.md` when present. Cap at 200 lines
per role. There is no SessionEnd hook that flushes insights automatically;
saving happens through the Stop guard in-session.

## 4. Triage

Pick 2 to 4 roles for the question. Remove the Villain from the builders.
Check other cabinets for relevant knowledge with
`registry_relevant_cabinets "<topic>"` (at most 1 foreign cabinet; an
unreadable path gets one advisory line, not a retry loop).

## 5. Size and seat

Size the meeting, name one pivotal role, and seat it per this table:

| Size | Pivotal | Supporting |
|---|---|---|
| quick | `cabinet-sonnet-medium` | `cabinet-sonnet-low` |
| standard | `cabinet-opus-high` | `cabinet-sonnet-medium` |
| deep | `cabinet-opus-high` | `cabinet-sonnet-medium` |

Limits: at most one `cabinet-opus-max`, only in a `deep` meeting; nothing
above medium in a `quick` meeting; a cheap pivotal seat must say why.

## 6. Announce

One line: `Convening (deep): tech_lead (opus, max — irreversible schema call), …`

## 7. Spawn

Spawn one subagent per role in parallel with `subagent_type` set to the
seat and NO `model` argument. Fallback: retry as `cabinet:<seat>`, then
`general-purpose` with a model and a visible note saying the seat was
unavailable. Prompt template: persona, topic, the role's memory, and the
instruction to answer in 4–10 lines plus an `ESCALATE:` line when
under-seated. Escalation goes one seat deeper; in a `quick` meeting it
re-sizes the meeting to `standard` once, never to `deep`.

Each answer is shown, then a synthesis: consensus, tensions, assumptions,
next steps, open questions. Flag shallow answers (the under-seated
check). One AskUserQuestion for a blocking fork. A mandatory footer line
reports what cross-cabinet discovery did.

## 8. Villain

The Villain reviews the synthesized proposal, not the raw topic.

1. Write the proposal to a temp file (X's last in the `mktemp` template —
   macOS rejects a trailing literal).
2. Preflight: `bash hooks/scripts/villain-codex.sh --preflight`.
3. Mandatory command (foreground, `timeout: 600000`,
   `dangerouslyDisableSandbox: true` — the sandbox kills Codex with exit
   127 and no stderr; Codex's own read-only sandbox still blocks writes):
   `bash hooks/scripts/villain-codex.sh --prompt-file <file> --out <file>`.
4. Read the `fatal=` count from the bridge's status line. A missing count
   is never zero (`unknown` means re-check, not clean).
5. If the bridge reports `status=unavailable`: fall back to a
   `cabinet-opus-high` Claude subagent for the review and print this
   disclosure line verbatim:
   `Villain review by Claude (Codex unavailable: <reason>) — same model family as the builders.`
6. Stop rule (4-way): `fatal=0` clean; `fatal=N>0` fix and re-review
   (`harden`/`challenge` loop up to 3 rounds); `status=failed` one retry,
   then Claude fallback with disclosure; `unknown` treat as failed.
7. Report line naming the model family, e.g.
   `Villain (codex, gpt-6): fatal=0 — ships.` or
   `Villain (claude, opus-high fallback): fatal=2 — see objections.`

## 9. Audit

Stamp `model`, `effort`, and `model_reason` on any note written from the
meeting. The meeting itself writes no memory.

## Boundary

The main session orchestrates only. It never answers the topic itself.

## Mode: commit

`/cabinet commit` writes this session's notes; it is not a meeting.

1. Find the session marker (`.cabinet-session-start-<id>` or the ppid
   symlink in the state dir) and read the cabinet path (line 1) and the
   session id (line 2).
2. For each role that learned something this session, write one raw note:
   `cabinet/<role>/raw/YYYY-MM-DD_<kebab-slug>.md` with frontmatter
   `date`, `session`, `session_id` (exactly the marker's id), `role`,
   `tags`, `schema_version: 1`, and a 2–5 sentence body.
3. Refuse when the last commit for this session is less than 5 minutes
   old, unless `--force` is passed. Age is measured from the newest note
   carrying this session id (file mtimes are unreliable on Drive).
4. Print one dim line naming the roles that wrote, e.g.
   `cabinet: committed engineer, tech_lead`.
