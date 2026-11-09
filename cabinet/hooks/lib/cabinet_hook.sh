# cabinet_hook.sh — the only way Cabinet hooks print JSON.
# Every emitter builds a payload with Python's json.dumps (safe quoting),
# then pipes it through _emit.py so an invalid shape fails loudly on
# stderr (return 1) instead of shipping bad JSON to Claude Code.
#
# Usage from a hook script:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   # shellcheck disable=SC1091
#   . "$SCRIPT_DIR/../lib/cabinet_hook.sh"
#   emit_stop_block "reason text"
#
# Requires: python3. jq is NOT required here.

_cabinet_hook_root() {
  # Directory containing this file's parent lib dir.
  _CH_THIS="${BASH_SOURCE[0]:-$0}"
  _CH_DIR="$(cd "$(dirname "$_CH_THIS")" && pwd)"
  printf '%s' "$_CH_DIR"
}

# Internal: encode a value with json.dumps and emit under a schema.
_cabinet_emit_string_field() {
  _CE_SCHEMA="$1"; _CE_FIELD="$2"; _CE_VALUE="$3"; _CE_EVENT="${4:-}"
  _CE_LIB="$(_cabinet_hook_root)"
  _CE_OUT="$(python3 - "$_CE_FIELD" "$_CE_VALUE" "$_CE_EVENT" <<'PYEOF'
import json, sys
field, value, event = sys.argv[1], sys.argv[2], sys.argv[3]
if event:
    payload = {"hookSpecificOutput": {"hookEventName": event,
               "additionalContext": value}}
else:
    payload = {field: value}
sys.stdout.write(json.dumps(payload))
PYEOF
)"
  # shellcheck disable=SC2181
  if [ $? -ne 0 ] || [ -z "$_CE_OUT" ]; then
    echo "cabinet_hook: failed to encode payload for $_CE_SCHEMA" >&2
    return 1
  fi
  printf '%s' "$_CE_OUT" | python3 "$_CE_LIB/_emit.py" "$_CE_SCHEMA"
}

emit_session_start() {
  # $1 = additionalContext text
  if [ -z "${1:-}" ]; then
    echo "cabinet_hook: emit_session_start needs non-empty context" >&2
    return 1
  fi
  _cabinet_emit_string_field session_start "" "$1" "SessionStart"
}

emit_post_tool_warn() {
  # $1 = additionalContext text
  if [ -z "${1:-}" ]; then
    echo "cabinet_hook: emit_post_tool_warn needs non-empty context" >&2
    return 1
  fi
  _cabinet_emit_string_field post_tool_warn "" "$1" "PostToolUse"
}

emit_post_tool_pass() {
  printf '{}' | python3 "$(_cabinet_hook_root)/_emit.py" post_tool_pass
}

emit_stop_block() {
  # $1 = reason text
  if [ -z "${1:-}" ]; then
    echo "cabinet_hook: emit_stop_block needs a non-empty reason" >&2
    return 1
  fi
  _CE_LIB="$(_cabinet_hook_root)"
  _CE_OUT="$(python3 - "$1" <<'PYEOF'
import json, sys
sys.stdout.write(json.dumps({"decision": "block", "reason": sys.argv[1]}))
PYEOF
)"
  if [ -z "$_CE_OUT" ]; then
    echo "cabinet_hook: failed to encode stop_block payload" >&2
    return 1
  fi
  printf '%s' "$_CE_OUT" | python3 "$_CE_LIB/_emit.py" stop_block
}

emit_stop_pass() {
  printf '{}' | python3 "$(_cabinet_hook_root)/_emit.py" stop_pass
}

emit_stop_user_message() {
  # $1 = message text
  if [ -z "${1:-}" ]; then
    echo "cabinet_hook: emit_stop_user_message needs non-empty text" >&2
    return 1
  fi
  _cabinet_emit_string_field stop_user_message "systemMessage" "$1"
}
