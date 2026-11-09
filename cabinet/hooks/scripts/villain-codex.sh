#!/usr/bin/env bash
# villain-codex.sh — run The Villain's review on OpenAI Codex so the
# reviewer isn't the same model family as the builders.
#
# Usage:
#   villain-codex.sh --preflight
#   villain-codex.sh --prompt-file <path> --out <path>
#
# Status line (always first on stdout):
#   CABINET_VILLAIN status=ok model=<id> effort=<level> fatal=<n|unknown|n/a>
#   CABINET_VILLAIN status=unavailable reason=<slug>
#   CABINET_VILLAIN status=failed reason=<text> exit=<n>
# The review body follows on `ok`. Exit codes: 0 ok, 3 unavailable
# (never ran), 4 failed (ran, no usable output).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TIMEOUT_SECS="${CABINET_CODEX_TIMEOUT:-480}"
TMP_STDERR="$(mktemp /tmp/cabvillain-XXXXXX)"
TMP_OUT="$(mktemp /tmp/cabvillain-XXXXXX)"
cleanup() {
  rm -f "$TMP_STDERR" "$TMP_OUT"
}
trap cleanup EXIT
trap 'cleanup; trap - INT TERM HUP; kill -INT $$ 2>/dev/null' INT
trap 'cleanup; trap - INT TERM HUP; kill -TERM $$ 2>/dev/null' TERM HUP

PREFLIGHT=0
PROMPT_FILE=""
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --preflight) PREFLIGHT=1; shift ;;
    --prompt-file)
      [ -n "${2:-}" ] || { echo "CABINET_VILLAIN status=unavailable reason=bad-usage"; exit 3; }
      PROMPT_FILE="$2"; shift 2 ;;
    --out)
      [ -n "${2:-}" ] && [ "$2" != "--"* ] || { echo "CABINET_VILLAIN status=unavailable reason=bad-usage"; exit 3; }
      OUT="$2"; shift 2 ;;
    *) echo "CABINET_VILLAIN status=unavailable reason=bad-usage"; exit 3 ;;
  esac
done

# Model: env override, else top-level `model` in the codex config (read
# stops at the first [table] header). Never hardcoded.
resolve_model() {
  if [ -n "${CABINET_CODEX_MODEL:-}" ]; then
    printf '%s' "$CABINET_CODEX_MODEL"
    return 0
  fi
  _CFG="${CODEX_HOME:-$HOME/.codex}/config.toml"
  [ -f "$_CFG" ] || return 1
  awk '
    /^\[.*\]/ { exit }
    /^[[:space:]]*model[[:space:]]*=/ {
      v = $0; sub(/^[^=]*=/, "", v)
      gsub(/^[[:space:]"\x27]+|[[:space:]"\x27]+$/, "", v)
      print v; exit
    }
  ' "$_CFG" | head -n 1
}

resolve_effort() {
  _CFG="${CODEX_HOME:-$HOME/.codex}/config.toml"
  [ -f "$_CFG" ] || { echo "n/a"; return 0; }
  _E="$(awk '
    /^\[.*\]/ { exit }
    /^[[:space:]]*model_reasoning_effort[[:space:]]*=/ {
      v = $0; sub(/^[^=]*=/, "", v)
      gsub(/^[[:space:]"\x27]+|[[:space:]"\x27]+$/, "", v)
      print v; exit
    }
  ' "$_CFG" | head -n 1)"
  [ -n "$_E" ] || _E="n/a"
  printf '%s' "$_E"
}

if ! command -v codex >/dev/null 2>&1; then
  echo "CABINET_VILLAIN status=unavailable reason=codex-not-installed"
  exit 3
fi
MODEL="$(resolve_model)"
if [ -z "$MODEL" ]; then
  echo "CABINET_VILLAIN status=unavailable reason=no-codex-model-configured"
  exit 3
fi

# Timeout binary: timeout or gtimeout (macOS coreutils).
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
else
  echo "CABINET_VILLAIN status=unavailable reason=no-timeout-bin"
  exit 3
fi

EFFORT="$(resolve_effort)"

if [ "$PREFLIGHT" = "1" ]; then
  echo "CABINET_VILLAIN status=ok model=$MODEL effort=$EFFORT fatal=n/a"
  exit 0
fi

if [ -z "$PROMPT_FILE" ] || [ ! -r "$PROMPT_FILE" ]; then
  echo "CABINET_VILLAIN status=unavailable reason=no-prompt-file"
  exit 3
fi
if [ -z "$OUT" ]; then
  echo "CABINET_VILLAIN status=unavailable reason=no-out-path"
  exit 3
fi
if ! : > "$OUT" 2>/dev/null; then
  echo "CABINET_VILLAIN status=unavailable reason=out-not-writable"
  exit 3
fi
# Empty $OUT first so a previous round's clean review can't be re-read.
: > "$OUT"

"$TIMEOUT_BIN" "$TIMEOUT_SECS" codex exec - -m "$MODEL" \
  --skip-git-repo-check --sandbox read-only -o "$OUT" \
  < "$PROMPT_FILE" 2>"$TMP_STDERR"
_RC=$?

if [ "$_RC" -eq 124 ]; then
  echo "CABINET_VILLAIN status=failed reason=timed-out-after-${TIMEOUT_SECS}s exit=124"
  exit 4
fi
if [ "$_RC" -ne 0 ]; then
  _REASON="$(head -n 1 "$TMP_STDERR" 2>/dev/null | tr ' ' '-' | tr -cd 'A-Za-z0-9_.:@+,/-' | cut -c1-120)"
  [ -n "$_REASON" ] || _REASON="codex-exit-$_RC"
  echo "CABINET_VILLAIN status=failed reason=$_REASON exit=$_RC"
  exit 4
fi
if [ ! -s "$OUT" ]; then
  _REASON="$(head -n 1 "$TMP_STDERR" 2>/dev/null | tr ' ' '-' | tr -cd 'A-Za-z0-9_.:@+,/-' | cut -c1-120)"
  [ -n "$_REASON" ] || _REASON="empty-output"
  echo "CABINET_VILLAIN status=failed reason=$_REASON exit=$_RC"
  exit 4
fi

# fatal= from a line-anchored COUNTS: fatal=N. No line, or two different
# counts, gives unknown.
FATAL="$(grep -E '^COUNTS: fatal=[0-9]+' "$OUT" 2>/dev/null | sed 's/^COUNTS: fatal=//' | sort -u)"
if [ -z "$FATAL" ] || [ "$(printf '%s\n' "$FATAL" | grep -c .)" -gt 1 ]; then
  FATAL="unknown"
fi
echo "CABINET_VILLAIN status=ok model=$MODEL effort=$EFFORT fatal=$FATAL"
cat "$OUT"
