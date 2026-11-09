# Cabinet META

Version 1.1.0. Eight roles: chief_of_staff, engineer, tech_lead,
product_designer, marketing, researcher, recruiter, the_villain.

Hooks are registered by this plugin (`hooks/hooks.json`): SessionStart
(startup), Stop, PostToolUse (Write). There is no SessionEnd hook, by
design — notes are written in-session and the Stop guard validates them.

## Audit fields

Notes and pages may carry optional audit fields saying which model wrote
them and why:

```yaml
model: opus
effort: high
model_reason: irreversible schema call, needed the max seat
```

`/cabinet` stamps `model`, `effort`, and `model_reason` on notes written
from a meeting. The v1.0 names `model_tier` / `model_reason` are retired;
readers accept any extra frontmatter keys and ignore them.
