#!/usr/bin/env bash
# session-stop-guard.sh — Stop hook: block stopping until this session's
# notes exist and are valid; print the "Cabinet saved" receipt.
#
# Does not read stdin. Marker lookup: .cabinet-session-start-$SID (env var)
# then the ppid symlink. No marker: silent pass. Cabinet gone: silent pass.
# Bypass file .cabinet-flush-skip-<resolved-id>: delete, pass once.
# Session age = now - marker mtime. This session's notes: */raw/*.md whose
# session_id equals the marker's second line (never mtimes — Drive rewrites
# them). Matched notes are validated for filename AND schema_version
# (schema_version covers Bash-written notes, which skip the lint hook).
# Freshness: newest matched note older than 30 min + session past 3 min ->
# block (stale). After 5 blocks, enforcement off for the session.
#
# Tunables: CABINET_FLUSH_THRESHOLD_SECS (180), CABINET_FRESHNESS_SECS
# (1800), CABINET_MAX_BLOCKS (5).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/cabinet_hook.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/cabinet-schema.sh"

if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "cabinet: install jq and python3 for Cabinet hooks to run" >&2
  exit 0
fi

if [ "${CABINET_DEBUG:-0}" = "1" ]; then
  set -x
  trap 'echo "cabinet stop: error at $0:$LINENO" >&2' ERR
fi

FLUSH_THRESHOLD="${CABINET_FLUSH_THRESHOLD_SECS:-180}"
FRESHNESS="${CABINET_FRESHNESS_SECS:-1800}"
MAX_BLOCKS="${CABINET_MAX_BLOCKS:-5}"

if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}" ]; then
  STATE_DIR="$XDG_RUNTIME_DIR"
else
  STATE_DIR="$HOME/.cabinet/session-state"
fi

# 1. Find the marker.
MARKER=""
RESOLVED_ID=""
if [ -n "${CLAUDE_CODE_CURRENT_SESSION_ID:-}" ] && \
   [ -f "$STATE_DIR/.cabinet-session-start-$CLAUDE_CODE_CURRENT_SESSION_ID" ]; then
  RESOLVED_ID="$CLAUDE_CODE_CURRENT_SESSION_ID"
  MARKER="$STATE_DIR/.cabinet-session-start-$RESOLVED_ID"
elif [ -f "$STATE_DIR/.cabinet-session-start-ppid-$PPID" ]; then
  MARKER="$STATE_DIR/.cabinet-session-start-ppid-$PPID"
  RESOLVED_ID="$(basename "$(readlink "$MARKER" 2>/dev/null || printf '%s' "$MARKER")" 2>/dev/null | sed 's/^\.cabinet-session-start-//')"
  if [ -z "$RESOLVED_ID" ]; then
    RESOLVED_ID="ppid-$PPID"
  fi
fi
if [ -z "$MARKER" ]; then
  emit_stop_pass
  exit 0
fi
CABINET="$(sed -n 1p "$MARKER" 2>/dev/null)"
SESSION_ID="$(sed -n 2p "$MARKER" 2>/dev/null)"
if [ -z "$CABINET" ] || [ ! -d "$CABINET" ]; then
  emit_stop_pass
  exit 0
fi
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="$RESOLVED_ID"
fi

# 2. Bypass file: one file skips one Stop.
SKIP_FILE="$STATE_DIR/.cabinet-flush-skip-$RESOLVED_ID"
if [ -f "$SKIP_FILE" ]; then
  rm -f "$SKIP_FILE"
  emit_stop_pass
  exit 0
fi

block_count_file="$STATE_DIR/.cabinet-block-count-$RESOLVED_ID"
receipt_file="$STATE_DIR/.cabinet-receipt-$RESOLVED_ID"

do_block() {
  _B_COUNT=0
  if [ -f "$block_count_file" ]; then
    _B_COUNT="$(cat "$block_count_file" 2>/dev/null | tr -d ' ')"
    case "$_B_COUNT" in ''|*[!0-9]*) _B_COUNT=0 ;; esac
  fi
  _B_COUNT=$((_B_COUNT + 1))
  printf '%s' "$_B_COUNT" > "$block_count_file"
  if [ "$_B_COUNT" -ge "$MAX_BLOCKS" ]; then
    rm -f "$block_count_file"
    emit_stop_user_message "Cabinet: enforcement off for this session — saving is on you now."
    exit 0
  fi
  emit_stop_block "$1"
  exit 0
}

# 3. Session age = now - marker mtime. lstat, not stat: the marker may be
# the ppid symlink, and the start hook / smoke test age the symlink itself
# (BSD stat reads the symlink's own mtime; Drive rewrites file mtimes).
_MTIME="$(python3 -c 'import os,sys; print(int(os.lstat(sys.argv[1]).st_mtime))' "$MARKER" 2>/dev/null || date +%s)"
_NOW="$(date +%s)"
AGE=$((_NOW - _MTIME))

# 4. This session's notes: session_id match, never mtimes.
MATCHED=""
for _RAW in "$CABINET"/*/raw/*.md; do
  [ -f "$_RAW" ] || continue
  _NOTE_SID="$(extract_frontmatter_session_id "$_RAW")"
  if [ "$_NOTE_SID" = "$SESSION_ID" ]; then
    MATCHED="$MATCHED
$_RAW"
  fi
done
MATCHED="$(printf '%s' "$MATCHED" | sed '/^$/d')"

# 5. Validate matched notes: bad filename OR bad schema_version blocks.
if [ -n "$MATCHED" ]; then
  _BAD=""
  printf '%s\n' "$MATCHED" | while read -r _F; do
    [ -n "$_F" ] || continue
    if ! validate_raw_entry "$_F" 2>/tmp/cabinet-err-$$; then
      echo "schema violation in $(basename "$_F"): $(cat /tmp/cabinet-err-$$)"
    elif ! validate_schema_version "$_F" 2>/tmp/cabinet-err-$$; then
      echo "schema violation in $(basename "$_F"): $(cat /tmp/cabinet-err-$$)"
    fi
  done > /tmp/cabinet-bad-$$ 2>/dev/null
  _BAD="$(cat /tmp/cabinet-bad-$$ 2>/dev/null)"
  rm -f /tmp/cabinet-bad-$$ /tmp/cabinet-err-$$
  if [ -n "$_BAD" ]; then
    do_block "Cabinet schema violation:
$_BAD
Fix the notes, then stop again. Save help: bash $PLUGIN_ROOT/hooks/scripts/cabinet-save-instructions.sh force '$RESOLVED_ID'"
  fi
fi

# Newest matched note mtime (freshness only — attribution already done).
_NEWEST=0
if [ -n "$MATCHED" ]; then
  _NEWEST="$(printf '%s\n' "$MATCHED" | while read -r _F; do
    [ -n "$_F" ] || continue
    python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "$_F" 2>/dev/null || echo 0
  done | sort -n | tail -n 1)"
fi

# 6. Freshness: newest save older than 30 min and session past 3 min.
if [ -n "$MATCHED" ] && [ "$((_NOW - _NEWEST))" -gt "$FRESHNESS" ] && [ "$AGE" -gt "$FLUSH_THRESHOLD" ]; then
  do_block "Cabinet flush — no saves in this session for a while. Run: bash $PLUGIN_ROOT/hooks/scripts/cabinet-save-instructions.sh stale '$RESOLVED_ID'
Bypass: touch $STATE_DIR/.cabinet-flush-skip-$RESOLVED_ID"
fi

# 7. Happy path: receipt once per new set of files.
if [ -n "$MATCHED" ]; then
  _SORTED="$(printf '%s\n' "$MATCHED" | sort | tr '\n' '|' )"
  _PREV=""
  [ -f "$receipt_file" ] && _PREV="$(cat "$receipt_file" 2>/dev/null)"
  if [ "$_SORTED" != "$_PREV" ]; then
    printf '%s' "$_SORTED" > "$receipt_file"
    # Per-role counts with a one-line description from the first note.
    _LINES="$(printf '%s\n' "$MATCHED" | while read -r _F; do
      [ -n "$_F" ] || continue
      _ROLE="$(basename "$(dirname "$(dirname "$_F")")")"
      _DESC="$(awk 'BEGIN{f=0} /^---$/{f++; next} f>=2 && NF{print; exit}' "$_F" 2>/dev/null | cut -c1-60)"
      printf '%s|%s|%s\n' "$_ROLE" "$(basename "$_F")" "$_DESC"
    done | sort | awk -F'|' '{n[$1]++; if (!(($1) in seen)) {seen[$1]=$3}} END {for (r in n) printf "  %s  - %d note%s on %s\n", toupper(substr(r,1,1)) substr(r,2), n[r], (n[r]==1?"":"s"), seen[r]}' | sort)"
    _NROLES="$(printf '%s\n' "$MATCHED" | while read -r _F; do basename "$(dirname "$(dirname "$_F")")"; done | sort -u | wc -l | tr -d ' ')"
    emit_stop_user_message "Cabinet saved ($_NROLES specialist$([ "$_NROLES" = 1 ] || printf 's') updated):
$_LINES

Next session, they'll remember."
    exit 0
  fi
  emit_stop_pass
  exit 0
fi

# 8. No notes, session past threshold -> block with force variant.
if [ "$AGE" -gt "$FLUSH_THRESHOLD" ]; then
  do_block "Cabinet flush — no saves in ~$((AGE / 60))m. Run: bash $PLUGIN_ROOT/hooks/scripts/cabinet-save-instructions.sh force '$RESOLVED_ID'
Bypass: touch $STATE_DIR/.cabinet-flush-skip-$RESOLVED_ID"
fi

# 9. Short session, nothing saved.
emit_stop_user_message "Cabinet: nothing to save (quick session)."
