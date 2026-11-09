# scaffold.sh — sourced library: create a fresh cabinet's folders.
# Creates the 8 default roles, each with raw/.gitkeep and pages/.gitkeep.
# Creates no META.md, no INDEX.md, no archive/ (legacy files stay legacy).
#
#   . "<plugin>/hooks/lib/scaffold.sh"
#   scaffold_cabinet <cabinet_dir>

CABINET_DEFAULT_ROLES="chief_of_staff engineer tech_lead product_designer marketing researcher recruiter the_villain"

scaffold_cabinet() {
  _SC_DIR="$1"
  if [ -z "$_SC_DIR" ]; then
    echo "scaffold_cabinet: need a cabinet directory" >&2
    return 1
  fi
  for _SC_ROLE in $CABINET_DEFAULT_ROLES; do
    mkdir -p "$_SC_DIR/$_SC_ROLE/raw" "$_SC_DIR/$_SC_ROLE/pages" || return 1
    [ -e "$_SC_DIR/$_SC_ROLE/raw/.gitkeep" ] || : > "$_SC_DIR/$_SC_ROLE/raw/.gitkeep"
    [ -e "$_SC_DIR/$_SC_ROLE/pages/.gitkeep" ] || : > "$_SC_DIR/$_SC_ROLE/pages/.gitkeep"
  done
}

# cabinet_list_roles <cabinet_dir> [plugin_roles_dir] — print one role per
# line: union of cabinet subfolders that have raw/ or ROLE.md with the
# plugin default roles. Never hooks/, specs/, shared/, or a folder with
# neither raw/ nor ROLE.md. Same rule everywhere (start hook, save
# helper, registry doctor).
cabinet_list_roles() {
  _LR_CAB="$1"; _LR_DEFAULTS="${2:-}"
  _LR_TMP="$(mktemp /tmp/cabroles-XXXXXX 2>/dev/null || printf /tmp/cabroles-$$)"
  : > "$_LR_TMP" 2>/dev/null || _LR_TMP="/tmp/cabroles-$$"
  if [ "$_LR_DEFAULTS" = "none" ]; then
    : # cabinet folders only
  elif [ -n "$_LR_DEFAULTS" ] && [ -d "$_LR_DEFAULTS" ]; then
    for _LR_D in "$_LR_DEFAULTS"/*/; do
      [ -d "$_LR_D" ] || continue
      _LR_R="$(basename "$_LR_D")"
      printf '%s\n' "$_LR_R" >> "$_LR_TMP"
    done
  else
    for _LR_R in $CABINET_DEFAULT_ROLES; do
      printf '%s\n' "$_LR_R" >> "$_LR_TMP"
    done
  fi
  if [ -d "$_LR_CAB" ]; then
    for _LR_D in "$_LR_CAB"/*/; do
      [ -d "$_LR_D" ] || continue
      _LR_R="$(basename "$_LR_D")"
      case "$_LR_R" in
        hooks|specs|shared) continue ;;
      esac
      if [ -d "$_LR_D/raw" ] || [ -f "$_LR_D/ROLE.md" ]; then
        printf '%s\n' "$_LR_R" >> "$_LR_TMP"
      fi
    done
  fi
  sort -u "$_LR_TMP"
  rm -f "$_LR_TMP"
}
