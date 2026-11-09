#!/usr/bin/env bash
# apply.sh — write one synthesized page.
#
# Usage: apply.sh --cabinet <dir> --role <role> --page <name.md>
#                  [--dry-run] [--allow-first-touch-merge] < content
#
# Input must start with `---`, else exit 3. Bad arguments exit 2.
# Writes go to a temp file in the same folder, then a rename.
#
# Existing-page actions:
#   none                              -> created
#   no frontmatter (human-owned)      -> proposed-legacy (.proposed.md),
#                                        unless --allow-first-touch-merge
#   frontmatter, no last_synthesized_at -> proposed-no-timestamp
#   mtime more than 5 s after last_synthesized_at -> proposed-handedit
#   otherwise                         -> updated
# last_synthesized_at is stamped at write time, inside apply.sh, so a
# write is never immediately mistaken for a later hand edit.

set -u
CABINET=""; ROLE=""; PAGE=""; DRY_RUN=0; ALLOW_MERGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --cabinet) CABINET="${2:-}"; shift 2 ;;
    --role) ROLE="${2:-}"; shift 2 ;;
    --page) PAGE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --allow-first-touch-merge) ALLOW_MERGE=1; shift ;;
    *) echo "apply.sh: bad argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$CABINET" ] || [ -z "$ROLE" ] || [ -z "$PAGE" ]; then
  echo "apply.sh: need --cabinet, --role, --page" >&2
  exit 2
fi
case "$PAGE" in
  *.md) ;;
  *) echo "apply.sh: page must end in .md" >&2; exit 2 ;;
esac

CONTENT="$(cat)"
if [ "$(printf '%s' "$CONTENT" | head -n 1)" != "---" ]; then
  echo "apply.sh: content must start with ---" >&2
  exit 3
fi

PAGES_DIR="$CABINET/$ROLE/pages"
mkdir -p "$PAGES_DIR" || exit 2
TARGET="$PAGES_DIR/$PAGE"
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Stamp last_synthesized_at at write time: replace the field if present,
# else insert it as the last frontmatter line.
STAMPED="$(CAB_AP_CONTENT="$CONTENT" CAB_AP_NOW="$NOW_UTC" python3 - <<'PYEOF'
import os, sys
lines = os.environ["CAB_AP_CONTENT"].split("\n")
now = os.environ["CAB_AP_NOW"]
out, fm, done, inserted = [], 0, False, False
for i, l in enumerate(lines):
    if l.strip() == "---":
        fm += 1
        if fm == 2 and not inserted:
            out.append("last_synthesized_at: " + now)
            inserted = True
        out.append(l)
        if fm == 2:
            done = True
        continue
    if fm == 1 and l.startswith("last_synthesized_at:"):
        out.append("last_synthesized_at: " + now)
        inserted = True
        continue
    out.append(l)
sys.stdout.write("\n".join(out))
PYEOF
)"

ACTION=""
DEST="$TARGET"
if [ ! -e "$TARGET" ]; then
  ACTION="created"
elif [ "$(head -n 1 "$TARGET" 2>/dev/null)" != "---" ]; then
  if [ "$ALLOW_MERGE" = "1" ]; then
    ACTION="updated"
  else
    ACTION="proposed-legacy"
    DEST="${TARGET%.md}.proposed.md"
  fi
else
  _TS="$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f&&$1=="last_synthesized_at:"{print $2; exit}' "$TARGET" 2>/dev/null)"
  if [ -z "$_TS" ]; then
    ACTION="proposed-no-timestamp"
    DEST="${TARGET%.md}.proposed.md"
  else
    _PAGE_MTIME="$(python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "$TARGET" 2>/dev/null || echo 0)"
    _TS_EPOCH="$(python3 -c 'import sys,datetime; print(int(datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()))' "$_TS" 2>/dev/null || echo 0)"
    if [ "$((_PAGE_MTIME - _TS_EPOCH))" -gt 5 ]; then
      ACTION="proposed-handedit"
      DEST="${TARGET%.md}.proposed.md"
    else
      ACTION="updated"
    fi
  fi
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "$ACTION"
  exit 0
fi

_TMP="$PAGES_DIR/.apply-$$-$PAGE.tmp"
printf '%s' "$STAMPED" > "$_TMP" || exit 2
mv "$_TMP" "$DEST" || exit 2

# log.md: one line per write.
printf '[%s] process | page=%s action=%s\n' "$NOW_UTC" "$PAGE" "$ACTION" >> "$PAGES_DIR/log.md" 2>/dev/null
echo "$ACTION"
