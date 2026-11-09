# Cabinet for Claude Code

A per-project team of eight AI specialists (chief of staff, engineer, tech
lead, product designer, marketing, researcher, recruiter and the villain)
whose memory compounds across sessions. Each role keeps small markdown notes
inside your project, and hooks load them at session start and make sure new
learnings get saved before a session ends.

Full plugin docs: [cabinet/README.md](cabinet/README.md).

## Install

In Claude Code:

```
/plugin marketplace add OWNER/cabinet-plugin
/plugin install cabinet@cabinet
```

Then restart Claude Code and run `/cabinet-ensure` in a project to create its
cabinet.

## Requirements

- macOS or Linux, `bash`, `python3`
- Optional: `codex` CLI. The Villain review runs on Codex when it's installed
  and falls back to Claude otherwise.

## Development

```
bash cabinet/tests/run.sh
```

Tests run against a throwaway `HOME` and never touch your real `~/.cabinet`.

## License

MIT
