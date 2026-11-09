#!/usr/bin/env bash
# raw-entry-lint.sh — PostToolUse hook (Write): warn when a note the model
# just wrote has a bad name or frontmatter. Never blocks.
#
# Reads .tool_name and .tool_input.file_path from stdin. Non-Write tools,
# non-cabinet paths, and missing files pass silently.
#
# NOTE: the save template tells the model to write notes with Bash
# heredocs, and Bash writes never trigger this hook. schema_version for
# those notes is validated by the Stop hook instead (validate_schema_version
# in cabinet-schema.sh) — that is the v1.1.0 coverage choice.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/cabinet_hook.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/cabinet-schema.sh"

if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "cabinet: install jq and python3 for Cabinet hooks to run" >&2
  exit 0
fi

INPUT="$(cat)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"

if [ "$TOOL" != "Write" ] || [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  emit_post_tool_pass
  exit 0
fi

case "$FILE" in
  */cabinet/*/raw/*.md) ;;
  *)
    emit_post_tool_pass
    exit 0
    ;;
esac

if ! validate_raw_entry "$FILE" 2>/tmp/cabinet-lint-$$; then
  _WHY="$(cat /tmp/cabinet-lint-$$ 2>/dev/null)"
  rm -f /tmp/cabinet-lint-$$
  emit_post_tool_warn "Cabinet schema violation in $FILE: $_WHY"
  exit 0
fi
rm -f /tmp/cabinet-lint-$$
if ! validate_schema_version "$FILE" 2>/tmp/cabinet-lint-$$; then
  _WHY="$(cat /tmp/cabinet-lint-$$ 2>/dev/null)"
  rm -f /tmp/cabinet-lint-$$
  emit_post_tool_warn "Cabinet schema violation in $FILE: $_WHY"
  exit 0
fi
rm -f /tmp/cabinet-lint-$$
emit_post_tool_pass
