# Cabinet snippet for CLAUDE.md

The project uses the Cabinet plugin for persistent role memory. Each
role remembers in `cabinet/<role>/raw/` (notes) and
`cabinet/<role>/pages/` (summaries). The SessionStart hook loads memory
automatically; the Stop hook blocks stopping until this session's notes
are saved.

## Writing a note (correct format)

Filename: `cabinet/<role>/raw/YYYY-MM-DD_<kebab-slug>.md`
(first line exactly `---`; date-prefixed name; no `NNNN.md` numbers,
no `shared/raw/` folder — those are invisible to the Stop hook).

```markdown
---
date: 2026-11-09
session: short-topic-of-this-session
session_id: <the literal id from the Session Save Protocol brief>
role: engineer
tags: [cabinet, hooks]
schema_version: 1
---

Two to five sentences, one idea, readable with no other context.
```

The `session_id` MUST be the literal id from the start-of-session
brief. A note without it is invisible to the Stop hook: the session
will still be blocked after writing it. Write all notes in one Bash
call with heredocs so the user's screen isn't buried in previews.

To skip one Stop check: `touch <state>/.cabinet-flush-skip-<id>` using
the id printed in the start brief (or in the block message).
