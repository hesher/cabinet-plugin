#!/usr/bin/env bash
# scan.sh — list raw notes that no page cites yet.
#
# Usage: scan.sh <cabinet> <role> [--validate]
# Prints `raw/<stem>.md` per uncited, unskipped note. --validate exits 1
# (listing on stderr) when any note is neither cited nor skipped.
# A citation is `[[raw/<stem>|src: <stem>]]` in any pages/*.md.
# `.processed-skip` holds one note stem per line; `#` starts a comment.
# No raw/ folder exits 0.

set -u
VALIDATE=0
ARGS=""
for _A in "$@"; do
  if [ "$_A" = "--validate" ]; then
    VALIDATE=1
  else
    ARGS="$ARGS $_A"
  fi
done
# shellcheck disable=SC2086
set -- $ARGS
if [ $# -ne 2 ]; then
  echo "usage: scan.sh [--validate] <cabinet> <role>" >&2
  exit 2
fi
CABINET="$1"; ROLE="$2"
RAW_DIR="$CABINET/$ROLE/raw"
PAGES_DIR="$CABINET/$ROLE/pages"
SKIP_FILE="$CABINET/$ROLE/pages/.processed-skip"

if [ ! -d "$RAW_DIR" ]; then
  exit 0
fi

# Cited stems: [[raw/<stem>| ...]] anywhere in pages.
CITED="$(grep -rhoE '\[\[raw/[^]|]+' "$PAGES_DIR"/*.md 2>/dev/null | sed 's/^\[\[raw\///' | sort -u)"
SKIPPED=""
if [ -f "$SKIP_FILE" ]; then
  SKIPPED="$(grep -vE '^\s*(#|$)' "$SKIP_FILE" 2>/dev/null | sed 's/[[:space:]]//g' | sort -u)"
fi

UNCITED=""
for _N in "$RAW_DIR"/*.md; do
  [ -f "$_N" ] || continue
  _STEM="$(basename "$_N" .md)"
  if printf '%s\n' "$CITED" | grep -Fxq "$_STEM"; then
    continue
  fi
  if [ -n "$SKIPPED" ] && printf '%s\n' "$SKIPPED" | grep -Fxq "$_STEM"; then
    continue
  fi
  UNCITED="$UNCITED
raw/$_STEM.md"
done
UNCITED="$(printf '%s' "$UNCITED" | sed '/^$/d')"

if [ "$VALIDATE" = "1" ]; then
  if [ -n "$UNCITED" ]; then
    printf '%s\n' "$UNCITED" >&2
    exit 1
  fi
  exit 0
fi
[ -n "$UNCITED" ] && printf '%s\n' "$UNCITED"
