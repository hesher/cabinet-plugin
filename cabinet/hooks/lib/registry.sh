# registry.sh — sourced library: read, migrate, lock, and write
# ~/.cabinet/registry.json; cross-cabinet matching.
#
# v1 shape:
#   {"schema_version":1,"cabinets":{"<name>":{"path":"...","topics":[...],"created":"..."}}}
#
# NOTE: the v1.0 fields `last_flush` (on entries) and `auto_triage` (in
# config.json) are dead: nothing writes `last_flush`, nothing reads
# `auto_triage`. New entries omit `last_flush`; it is stripped on read.
# See MIGRATION.md.
#
# Env override for tests: CABINET_REGISTRY_PATH.

_cabinet_registry_path() {
  if [ -n "${CABINET_REGISTRY_PATH:-}" ]; then
    printf '%s' "$CABINET_REGISTRY_PATH"
  else
    printf '%s' "$HOME/.cabinet/registry.json"
  fi
}

_empty_registry() {
  printf '{"schema_version":1,"cabinets":{}}'
}

# registry_read — print the registry as canonical v1 JSON on stdout.
# Migrates legacy shapes in memory; backs up the original file to
# registry.json.bak before migration. Missing file: prints an empty
# registry without creating anything. Invalid JSON: backs up, rc=4.
registry_read() {
  _RR_PATH="$(_cabinet_registry_path)"
  if [ ! -e "$_RR_PATH" ]; then
    _empty_registry
    return 0
  fi
  _RR_RAW="$(cat "$_RR_PATH" 2>/dev/null)"
  if ! printf '%s' "$_RR_RAW" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    cp "$_RR_PATH" "$_RR_PATH.bak" 2>/dev/null
    echo "cabinet registry: invalid JSON in $_RR_PATH (backed up to $_RR_PATH.bak)" >&2
    echo "fix: delete it or repair it, then retry" >&2
    return 4
  fi
  _RR_MIGRATED="$(CAB_RR_RAW="$_RR_RAW" python3 - "$_RR_PATH" <<'PYEOF'
import json, sys, os
raw = json.loads(os.environ["CAB_RR_RAW"])

def entry(path, topics, created):
    return {"path": path, "topics": topics or [], "created": created}

def clean(e):
    # Drop the dead v1.0 `last_flush` field; keep the rest.
    return {k: v for k, v in e.items() if k != "last_flush"}

out = {"schema_version": 1, "cabinets": {}}
cabs = raw.get("cabinets", None)
if isinstance(cabs, dict):
    # Already v1 (name-keyed) — strip dead fields.
    for name, e in cabs.items():
        if isinstance(e, dict) and isinstance(e.get("path"), str):
            e = clean(e)
            e.setdefault("topics", [])
            out["cabinets"][name] = e
elif isinstance(cabs, list):
    for item in cabs:
        if not isinstance(item, dict):
            continue
        if "cabinet_id" in item or "last_session_at" in item:
            # This-Mac list shape (brief item 6): path is the PROJECT
            # root, not the cabinet dir. Map to <path>/cabinet when that
            # exists, key by name, topics from [].
            name = item.get("name") or item.get("cabinet_id") or "cabinet"
            proj = item.get("path", "")
            cand = os.path.join(proj, "cabinet")
            path = cand if os.path.isdir(cand) else proj
            created = item.get("created_at") or item.get("created") or ""
            out["cabinets"][name] = entry(path, [], created)
        elif "name" in item and "path" in item:
            # v0b list shape.
            e = clean(item)
            name = e.pop("name"); path = e.pop("path")
            topics = e.pop("topics", [])
            created = e.pop("created", "")
            rec = entry(path, topics, created)
            rec.update({k: v for k, v in e.items()})
            out["cabinets"][name] = rec
elif isinstance(raw.get("mappings"), list):
    # v0a mappings shape; name from the cwd folder name.
    for m in raw["mappings"]:
        if not isinstance(m, dict):
            continue
        cab = m.get("cabinet", "")
        cwd = m.get("cwd", "")
        name = os.path.basename(cwd.rstrip("/")) or cab
        out["cabinets"][name] = entry(cab, [], "")
else:
    # Unrecognized but valid JSON: empty v1 registry.
    pass
sys.stdout.write(json.dumps(out))
PYEOF
)"
  # shellcheck disable=SC2181
  if [ $? -ne 0 ]; then
    cp "$_RR_PATH" "$_RR_PATH.bak" 2>/dev/null
    echo "cabinet registry: could not migrate $_RR_PATH (backed up)" >&2
    return 4
  fi
  # If migration changed the shape, back up the original first.
  _RR_NORM_ORIG="$(printf '%s' "$_RR_RAW" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d,sort_keys=True))' 2>/dev/null)"
  _RR_NORM_NEW="$(printf '%s' "$_RR_MIGRATED" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d,sort_keys=True))' 2>/dev/null)"
  if [ "$_RR_NORM_ORIG" != "$_RR_NORM_NEW" ]; then
    cp "$_RR_PATH" "$_RR_PATH.bak" 2>/dev/null
  fi
  printf '%s' "$_RR_MIGRATED"
}

# Locking: flock with 60 s timeout; without flock (macOS) a
# registry.lock.d/ dir holding a pid file. A dead owner's lock is removed
# with a message and retried once. Timeout returns 3.
_registry_lock_dir() {
  _RL_BASE="$(_cabinet_registry_path)"
  printf '%s' "${_RL_BASE}.lock.d"
}

registry_lock() {
  _RL_D="$(_registry_lock_dir)"
  _RL_LOCKFILE="${_RL_D%.d}"
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$_RL_LOCKFILE" 2>/dev/null || return 3
    if ! flock -w 60 9 2>/dev/null; then
      echo "cabinet registry: lock timeout" >&2
      return 3
    fi
    return 0
  fi
  # macOS fallback: pid-file lock dir.
  _RL_TRIES=0
  while [ $_RL_TRIES -lt 2 ]; do
    if mkdir "$_RL_D" 2>/dev/null; then
      printf '%s' "$$" > "$_RL_D/pid" 2>/dev/null
      return 0
    fi
    _RL_OWNER="$(cat "$_RL_D/pid" 2>/dev/null)"
    if [ -n "$_RL_OWNER" ] && ! kill -0 "$_RL_OWNER" 2>/dev/null; then
      echo "cabinet registry: removing stale lock from dead pid $_RL_OWNER" >&2
      rm -rf "$_RL_D" 2>/dev/null
      _RL_TRIES=$((_RL_TRIES + 1))
      continue
    fi
    # Live owner: wait up to 60 s.
    _RL_WAIT=0
    while [ $_RL_WAIT -lt 60 ]; do
      sleep 1
      _RL_WAIT=$((_RL_WAIT + 1))
      if mkdir "$_RL_D" 2>/dev/null; then
        printf '%s' "$$" > "$_RL_D/pid" 2>/dev/null
        return 0
      fi
    done
    echo "cabinet registry: lock timeout" >&2
    return 3
  done
  echo "cabinet registry: lock timeout" >&2
  return 3
}

registry_unlock() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>&- 2>/dev/null
    return 0
  fi
  _RL_D="$(_registry_lock_dir)"
  _RL_OWNER="$(cat "$_RL_D/pid" 2>/dev/null)"
  if [ -z "$_RL_OWNER" ] || [ "$_RL_OWNER" = "$$" ]; then
    rm -rf "$_RL_D" 2>/dev/null
  fi
  return 0
}

# registry_write <json> — validate, write tmp file, rename over original,
# all under the lock.
registry_write() {
  _RW_JSON="$1"
  if ! printf '%s' "$_RW_JSON" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "cabinet registry: refusing to write invalid JSON" >&2
    return 2
  fi
  _RW_PATH="$(_cabinet_registry_path)"
  registry_lock || return 3
  mkdir -p "$(dirname "$_RW_PATH")" 2>/dev/null
  printf '%s' "$_RW_JSON" > "$_RW_PATH.tmp" 2>/dev/null
  _RW_RC=$?
  if [ $_RW_RC -ne 0 ]; then
    registry_unlock
    return $_RW_RC
  fi
  mv "$_RW_PATH.tmp" "$_RW_PATH"
  _RW_RC=$?
  registry_unlock
  return $_RW_RC
}

# registry_register <name> <cabinet_path> [topics_csv]
registry_register() {
  _RG_NAME="$1"; _RG_PATH="$2"; _RG_TOPICS="${3:-}"
  if [ -z "$_RG_NAME" ] || [ -z "$_RG_PATH" ]; then
    echo "registry_register: need name and cabinet path" >&2
    return 2
  fi
  _RG_REG="$(registry_read)" || return $?
  CAB_RG_REG="$_RG_REG" CAB_RG_NAME="$_RG_NAME" CAB_RG_PATH="$_RG_PATH" \
    CAB_RG_TOPICS="$_RG_TOPICS" python3 - <<'PYEOF' > /tmp/cabinet-reg-out-$$.json
import json, os, sys, datetime
name = os.environ["CAB_RG_NAME"]; path = os.environ["CAB_RG_PATH"]
topics = [t for t in os.environ.get("CAB_RG_TOPICS", "").split(",") if t]
reg = json.loads(os.environ["CAB_RG_REG"])
reg.setdefault("cabinets", {})[name] = {
    "path": path, "topics": topics,
    "created": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
sys.stdout.write(json.dumps(reg))
PYEOF
  _RG_RC=$?
  if [ $_RG_RC -ne 0 ]; then rm -f /tmp/cabinet-reg-out-$$.json; return $_RG_RC; fi
  _RG_NEW="$(cat /tmp/cabinet-reg-out-$$.json; rm -f /tmp/cabinet-reg-out-$$.json)"
  registry_write "$_RG_NEW"
}

# registry_relevant_cabinets "<topic>" [exclude_name] — print
# name<TAB>path<TAB>count<TAB>keywords for cabinets sharing 2+ tokens
# with the topic, best first.
registry_relevant_cabinets() {
  _RQ_TOPIC="$1"; _RQ_EXCLUDE="${2:-}"
  _RQ_REG="$(registry_read)" || return $?
  CAB_RQ_REG="$_RQ_REG" CAB_RQ_TOPIC="$_RQ_TOPIC" CAB_RQ_EXCLUDE="$_RQ_EXCLUDE" python3 - <<'PYEOF'
import json, os, re, sys
topic = os.environ.get("CAB_RQ_TOPIC", "")
exclude = os.environ.get("CAB_RQ_EXCLUDE", "")
reg = json.loads(os.environ["CAB_RQ_REG"])
def toks(s):
    return {t for t in re.split(r"[^a-z0-9]+", s.lower()) if len(t) >= 2}
tt = toks(topic)
rows = []
for name, e in reg.get("cabinets", {}).items():
    if name == exclude:
        continue
    kw = " ".join([name] + list(e.get("topics", [])))
    shared = tt & toks(kw)
    if len(shared) >= 2:
        rows.append((len(shared), name, e.get("path", ""), ",".join(sorted(shared))))
rows.sort(key=lambda r: (-r[0], r[1]))
for n, name, path, kw in rows:
    sys.stdout.write("%s\t%s\t%d\t%s\n" % (name, path, n, kw))
PYEOF
}
