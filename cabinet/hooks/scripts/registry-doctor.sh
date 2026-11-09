#!/usr/bin/env bash
# registry-doctor.sh — manual CLI: compare the registry with cabinets found
# under project_roots. Reports stale entries, unregistered cabinets, and
# empty topics. --apply drops stale entries and registers missing ones.
#
# Discovery rule matches the start hook: a folder counts as a cabinet when
# it has cabinet/META.md or cabinet/chief_of_staff/. (Scaffolded cabinets
# have no META.md, so requiring it would hide them.)
#
# Env overrides: CABINET_REGISTRY_PATH, CABINET_CONFIG_PATH.
# Exit 2 bad args, 3 registry failure.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/registry.sh"

APPLY=0
JSON=0
for _A in "$@"; do
  case "$_A" in
    --apply) APPLY=1 ;;
    --json) JSON=1 ;;
    *) echo "usage: registry-doctor.sh [--apply] [--json]" >&2; exit 2 ;;
  esac
done

CONFIG="${CABINET_CONFIG_PATH:-$HOME/.cabinet/config.json}"

REG="$(registry_read)" || exit 3

# Discovered cabinets: name<TAB>path, one per project dir with a cabinet.
DISC="$(mktemp /tmp/cabdoc-disc-XXXXXX)"
if [ -f "$CONFIG" ]; then
  jq -r '.project_roots // [] | .[]' "$CONFIG" 2>/dev/null | while read -r _R; do
    [ -n "$_R" ] || continue
    # shellcheck disable=SC2086
    for _EXP in $(eval echo "$_R"); do
      [ -d "$_EXP" ] || continue
      for _P in "$_EXP"/*/; do
        [ -d "$_P" ] || continue
        _CAND="$_P/cabinet"
        [ -d "$_CAND" ] || continue
        if [ -f "$_CAND/META.md" ] || [ -d "$_CAND/chief_of_staff" ]; then
          printf '%s\t%s\n' "$(basename "$_P")" "$_CAND"
        fi
      done
    done
  done | sort -u > "$DISC"
else
  : > "$DISC"
fi

# shellcheck disable=SC2034
REPORT="$(REG_CABS="$REG" REG_DISC="$DISC" python3 - <<'PYEOF'
import json, os, sys
reg = json.loads(os.environ["REG_CABS"])
disc = {}
with open(os.environ["REG_DISC"]) as f:
    for line in f:
        line = line.rstrip("\n")
        if "\t" in line:
            name, path = line.split("\t", 1)
            disc[name] = path
cabs = reg.get("cabinets", {})
stale = sorted([n for n, e in cabs.items()
                if not os.path.isdir(e.get("path", ""))])
missing = sorted([(n, p) for n, p in disc.items() if n not in cabs])
empty_topics = sorted([n for n, e in cabs.items() if not e.get("topics")])
sys.stdout.write(json.dumps({"stale": stale, "missing": missing,
                             "empty_topics": empty_topics}))
PYEOF
)"

STALE="$(printf '%s' "$REPORT" | jq -r '.stale[]?' 2>/dev/null)"
MISSING="$(printf '%s' "$REPORT" | jq -c '.missing[]?' 2>/dev/null)"
EMPTY_TOPICS="$(printf '%s' "$REPORT" | jq -r '.empty_topics[]?' 2>/dev/null)"

if [ "$JSON" = "1" ]; then
  printf '%s\n' "$REPORT" | jq .
  rm -f "$DISC"
  exit 0
fi

[ -n "$STALE" ] && printf 'stale entries (path gone):\n%s\n' "$STALE"
[ -n "$MISSING" ] && printf 'unregistered cabinets:\n%s\n' "$(printf '%s\n' "$MISSING" | jq -r '"\(.[0]) -> \(.[1])"')"
[ -n "$EMPTY_TOPICS" ] && printf 'cabinets with empty topics (never pass the cross-cabinet gate):\n%s\n' "$EMPTY_TOPICS"
if [ -z "$STALE$MISSING$EMPTY_TOPICS" ]; then
  echo "cabinet registry: healthy"
fi

if [ "$APPLY" = "1" ]; then
  # Stale first (direct write), then missing (locked register per entry).
  if [ -n "$STALE" ]; then
    NEWREG="$(printf '%s' "$REG" | STALE_LIST="$STALE" python3 -c '
import json, os, sys
reg = json.load(sys.stdin)
for n in os.environ["STALE_LIST"].split("\n"):
    if n: reg.get("cabinets", {}).pop(n, None)
sys.stdout.write(json.dumps(reg))')"
    registry_write "$NEWREG" || exit 3
  fi
  if [ -n "$MISSING" ]; then
    printf '%s\n' "$MISSING" | while read -r _M; do
      _MN="$(printf '%s' "$_M" | jq -r '.[0]')"
      _MP="$(printf '%s' "$_M" | jq -r '.[1]')"
      registry_register "$_MN" "$_MP" >/dev/null || exit 3
    done
  fi
  echo "cabinet registry: applied"
fi
rm -f "$DISC"
