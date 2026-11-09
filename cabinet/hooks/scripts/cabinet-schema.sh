# cabinet-schema.sh — sourced helper: filename regex, frontmatter check,
# session_id extractor. Shared by the Stop hook and the lint hook.
#
#   . "<plugin>/hooks/scripts/cabinet-schema.sh"
#   validate_raw_entry <file>      # exit 0 valid; exit 1 + reason on stderr
#   extract_frontmatter_session_id <file>  # prints id or empty string

CABINET_FILENAME_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}_.+\.md$'

_cabinet_basename() {
  _CB_P="$1"
  printf '%s' "${_CB_P##*/}"
}

validate_raw_entry() {
  _VE_FILE="$1"
  _VE_BASE="$(_cabinet_basename "$_VE_FILE")"
  case "$_VE_BASE" in
    *[!a-zA-Z0-9._-]*)
      # regex check below covers the date rule; this branch is unreachable
      ;;
  esac
  if ! printf '%s' "$_VE_BASE" | grep -Eq "$CABINET_FILENAME_RE"; then
    echo "bad filename '$_VE_BASE': want YYYY-MM-DD_<slug>.md" >&2
    return 1
  fi
  if [ ! -f "$_VE_FILE" ]; then
    echo "not a file: $_VE_FILE" >&2
    return 1
  fi
  _VE_FIRST="$(head -n 1 "$_VE_FILE" 2>/dev/null)"
  if [ "$_VE_FIRST" != "---" ]; then
    echo "missing frontmatter in $_VE_BASE: first line must be ---" >&2
    return 1
  fi
  return 0
}

# Validate the schema_version frontmatter field (Stop-hook choice for
# covering Bash-written notes, which never trigger the PostToolUse lint).
# Exit 0 when schema_version is exactly 1; exit 1 + reason otherwise.
validate_schema_version() {
  _VS_FILE="$1"
  _VS_BASE="$(_cabinet_basename "$1")"
  _VS_VER="$(awk '
    NR==1 && $0=="---" { in_fm=1; next }
    in_fm && $0=="---" { exit }
    in_fm && $1=="schema_version:" { gsub(/["'"'"']/,"",$2); print $2; exit }
  ' "$_VS_FILE" 2>/dev/null)"
  if [ -z "$_VS_VER" ]; then
    echo "missing schema_version in $_VS_BASE (want schema_version: 1)" >&2
    return 1
  fi
  if [ "$_VS_VER" != "1" ]; then
    echo "bad schema_version '$_VS_VER' in $_VS_BASE (want 1)" >&2
    return 1
  fi
  return 0
}

# Print the session_id frontmatter value with surrounding quotes stripped,
# or an empty string when absent.
extract_frontmatter_session_id() {
  _ES_FILE="$1"
  awk '
    NR==1 && $0=="---" { in_fm=1; next }
    in_fm && $0=="---" { exit }
    in_fm && $1=="session_id:" {
      v=$0; sub(/^[^:]*:[[:space:]]*/, "", v)
      gsub(/^["'"'"']|["'"'"']$/, "", v)
      print v; exit
    }
  ' "$_ES_FILE" 2>/dev/null
}
