#!/usr/bin/env bash
# cabinet-save-instructions.sh — helper the model runs when the Stop hook
# blocks. Prints the exact note template.
#
# Usage: cabinet-save-instructions.sh <force|stale> <id>
# Exit 1 on bad usage, missing marker, or missing cabinet folder.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/scaffold.sh"

VARIANT="${1:-}"
ID="${2:-}"
if [ "$VARIANT" != "force" ] && [ "$VARIANT" != "stale" ]; then
  echo "usage: cabinet-save-instructions.sh <force|stale> <id>" >&2
  exit 1
fi
if [ -z "$ID" ]; then
  echo "usage: cabinet-save-instructions.sh <force|stale> <id>" >&2
  exit 1
fi

if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}" ]; then
  STATE_DIR="$XDG_RUNTIME_DIR"
else
  STATE_DIR="$HOME/.cabinet/session-state"
fi
MARKER="$STATE_DIR/.cabinet-session-start-$ID"
if [ ! -f "$MARKER" ]; then
  # Fall back through the ppid symlink target.
  _LINK="$STATE_DIR/.cabinet-session-start-ppid-$PPID"
  if [ -f "$_LINK" ]; then
    MARKER="$_LINK"
  else
    echo "cabinet: no session marker for id '$ID'; nothing to save to" >&2
    exit 1
  fi
fi
CABINET="$(sed -n 1p "$MARKER")"
SESSION_ID="$(sed -n 2p "$MARKER")"
if [ ! -d "$CABINET" ]; then
  echo "cabinet: cabinet folder is gone: $CABINET" >&2
  exit 1
fi

# Roles that have a raw/ subfolder, skipping hooks and shared.
ROLES="$(cabinet_list_roles "$CABINET" "")"
SAVE_ROLES=""
for _R in $ROLES; do
  case "$_R" in
    hooks|shared) continue ;;
  esac
  if [ -d "$CABINET/$_R/raw" ]; then
    SAVE_ROLES="$SAVE_ROLES $_R"
  fi
done
# (cabinet_list_roles already excludes hooks/shared/specs; belt and braces.)

if [ "$VARIANT" = "stale" ]; then
  echo "Your last save for this session is stale (older than 30 minutes)."
  echo "Write fresh notes for what changed since, then stop again."
  echo ""
fi

echo "Write one raw note per role that learned something this session."
echo "Write ALL notes in ONE Bash call using heredocs — not one Write call"
echo "per file, so the user's screen isn't buried in previews."
echo ""
echo "Roles with memory folders in this cabinet:"
NUDGE_THRESHOLD="${CABINET_PROCESS_NUDGE_THRESHOLD:-10}"
for _R in $SAVE_ROLES; do
  _N="$(find "$CABINET/$_R/raw" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  _NUDGE=""
  if [ "$_N" -ge "$NUDGE_THRESHOLD" ]; then
    # Nudge: role has many notes not yet folded into pages.
    _NUDGE=" (nudge: $_N notes — consider running /cabinet:process soon)"
  fi
  echo "  - $_R$_NUDGE"
done
echo ""
echo "Template (repeat per role, one Bash heredoc per file):"
echo ""
echo "  cat > \"cabinet/<role>/raw/\$(date +%F)_<kebab-slug>.md\" <<'EOF'"
echo "  ---"
echo "  date: $(date +%F)"
echo "  session: <short topic of this session>"
echo "  session_id: $SESSION_ID"
echo "  role: <role>"
echo "  tags: [<1-5 lowercase kebab tags>]"
echo "  schema_version: 1"
echo "  ---"
echo ""
echo "  Two to five sentences, one idea, readable with no other context."
echo "  EOF"
echo ""
echo "Rules: filename must match YYYY-MM-DD_<slug>.md; first line exactly ---;"
echo "session_id must be exactly '$SESSION_ID' or the Stop hook will not see the note."
