#!/usr/bin/env bash
# Cabinet test harness (macOS-safe: no `touch -d`, no `grep -P`; file
# aging goes through the python `age` helper). Every suite runs with a
# throwaway HOME so the real ~/.cabinet is never touched.
#
# Suites: smoke (§7.3 table), emit, empty_registry, registry_migrate,
# skip_path, pages_without_schema, discovery, brief_cap, villain_bridge,
# apply_self_write, raw_lint.
set -u

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
age() { python3 -c 'import os,sys,time; t=time.time()-int(sys.argv[2]); os.utime(sys.argv[1],(t,t),follow_symlinks=False)' "$1" "$2"; }

ok()   { PASS=$((PASS+1)); echo "ok   $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL $1 -- $2"; }

fresh_home() {
  # $1 = test dir; sets HOME + XDG_RUNTIME_DIR with state dir.
  export HOME="$1/home" XDG_RUNTIME_DIR="$1/state"
  mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
  unset CLAUDE_CODE_CURRENT_SESSION_ID
}

# --- 1. smoke (§7.3): start -> quick pass -> block -> bad note -> good -> receipt -> dedup -> scan
suite_smoke() {
  D=$(mktemp -d /tmp/cabsmoke-XXXXXX); fresh_home "$D"; mkdir -p "$D/proj"
  # shellcheck disable=SC1091
  . "$PLUGIN_ROOT/hooks/lib/scaffold.sh"; scaffold_cabinet "$D/proj/cabinet"
  # NOTE: hooks resolve the session via ppid-$PPID, so they must run as
  # direct children of this shell — output goes to files, never $(...),
  # or each substitution's forked subshell changes their PPID.
  echo '{"source":"startup","cwd":"'"$D/proj"'"}' | bash "$PLUGIN_ROOT/hooks/scripts/session-start-triage.sh" > "$D/start.json"
  CTX=$(jq -r '.hookSpecificOutput.additionalContext' < "$D/start.json")
  case "$CTX" in *FRESH_CABINET*pid*) ok "smoke step 1 (FRESH + pid sid)";; *) bad "smoke step 1" "$CTX"; rm -rf "$D"; return;; esac
  M=$(echo "$XDG_RUNTIME_DIR"/.cabinet-session-start-ppid-*); SID=$(sed -n 2p "$M")
  case "$SID" in pid*) ok "smoke sid form";; *) bad "smoke sid" "$SID"; rm -rf "$D"; return;; esac
  echo '{}' | bash "$PLUGIN_ROOT/hooks/scripts/session-stop-guard.sh" > "$D/stop2.json"
  R2=$(cat "$D/stop2.json")
  case "$R2" in *"quick session"*) ok "smoke step 2 (quick pass)";; *) bad "smoke step 2" "$R2";; esac
  age "$M" 600
  echo '{}' | bash "$PLUGIN_ROOT/hooks/scripts/session-stop-guard.sh" > "$D/stop3.json"
  R3=$(jq -r .decision < "$D/stop3.json")
  [ "$R3" = "block" ] && ok "smoke step 3 (10min block)" || bad "smoke step 3" "$R3"
  printf -- "---\nsession_id: %s\n---\nx\n" "$SID" > "$D/proj/cabinet/engineer/raw/badname.md"
  echo '{}' | bash "$PLUGIN_ROOT/hooks/scripts/session-stop-guard.sh" > "$D/stop4.json"
  R4=$(jq -r .decision < "$D/stop4.json")
  [ "$R4" = "block" ] && ok "smoke step 4 (bad name blocks)" || bad "smoke step 4" "$R4"
  rm "$D/proj/cabinet/engineer/raw/badname.md"
  F="$D/proj/cabinet/engineer/raw/$(date +%Y-%m-%d)_smoke_test.md"
  printf -- "---\ndate: %s\nsession: smoke\nsession_id: %s\nrole: engineer\ntags: [t]\nschema_version: 1\n---\n\nSmoke entry.\n" "$(date +%F)" "$SID" > "$F"
  jq -nc --arg f "$F" '{tool_name:"Write",tool_input:{file_path:$f}}' | bash "$PLUGIN_ROOT/hooks/scripts/raw-entry-lint.sh" > "$D/lint5.json"
  R5=$(cat "$D/lint5.json")
  [ "$R5" = "{}" ] && ok "smoke step 5 (lint pass)" || bad "smoke step 5" "$R5"
  echo '{}' | bash "$PLUGIN_ROOT/hooks/scripts/session-stop-guard.sh" > "$D/stop6.json"
  R6=$(jq -r .systemMessage < "$D/stop6.json")
  case "$R6" in *"Cabinet saved (1 specialist updated):"*Engineer*"1 note on"*) ok "smoke step 6 (receipt)";; *) bad "smoke step 6" "$R6";; esac
  echo '{}' | bash "$PLUGIN_ROOT/hooks/scripts/session-stop-guard.sh" > "$D/stop7.json"
  R7=$(cat "$D/stop7.json")
  [ "$R7" = "{}" ] && ok "smoke step 7 (receipt dedup)" || bad "smoke step 7" "$R7"
  R8=$(bash "$PLUGIN_ROOT/skills/process/scripts/scan.sh" "$D/proj/cabinet" engineer)
  case "$R8" in *"raw/$(date +%Y-%m-%d)_smoke_test.md"*) ok "smoke step 8 (scan)";; *) bad "smoke step 8" "$R8";; esac
  bash "$PLUGIN_ROOT/skills/process/scripts/scan.sh" --validate "$D/proj/cabinet" engineer 2>/dev/null
  [ $? -eq 1 ] && ok "smoke validate rc=1" || bad "smoke validate rc" "expected 1"
  rm -rf "$D"
}

# --- 2. hook JSON validator
suite_emit() {
  echo '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"x"}}' | python3 "$PLUGIN_ROOT/hooks/lib/_emit.py" stop_block >/dev/null 2>&1
  [ $? -eq 2 ] && ok "emit rejects wrong event" || bad "emit wrong-event" "expected rc=2"
  OUT=$(echo '{"decision":"block","reason":"x"}' | python3 "$PLUGIN_ROOT/hooks/lib/_emit.py" stop_block)
  [ "$OUT" = '{"decision":"block","reason":"x"}' ] && ok "emit stop_block round-trip" || bad "emit round-trip" "$OUT"
  echo '{"systemMessage":""}' | python3 "$PLUGIN_ROOT/hooks/lib/_emit.py" stop_user_message >/dev/null 2>&1
  [ $? -eq 2 ] && ok "emit rejects empty string" || bad "emit empty" "expected rc=2"
  echo '{"decision":"block","reason":"x","extra":1}' | python3 "$PLUGIN_ROOT/hooks/lib/_emit.py" stop_block >/dev/null 2>&1
  [ $? -eq 2 ] && ok "emit rejects unknown keys" || bad "emit extra-keys" "expected rc=2"
  echo '{}' | python3 "$PLUGIN_ROOT/hooks/lib/_emit.py" stop_pass >/dev/null 2>&1
  [ $? -eq 0 ] && ok "emit stop_pass" || bad "emit stop_pass" "expected rc=0"
}

# --- 3. empty registry read: prints empty, creates nothing
suite_empty_registry() {
  D=$(mktemp -d /tmp/cabreg-XXXXXX); fresh_home "$D"
  export CABINET_REGISTRY_PATH="$D/reg.json"
  OUT=$(bash -c "source '$PLUGIN_ROOT/hooks/lib/registry.sh'; registry_read")
  [ "$OUT" = '{"schema_version":1,"cabinets":{}}' ] && [ ! -e "$D/reg.json" ] \
    && ok "empty registry read" || bad "empty registry" "$OUT"
  unset CABINET_REGISTRY_PATH; rm -rf "$D"
}

# --- 4. legacy migration incl. this-Mac list shape
suite_registry_migrate() {
  D=$(mktemp -d /tmp/cabregmig-XXXXXX); fresh_home "$D"
  export CABINET_REGISTRY_PATH="$D/reg.json"
  printf '{"mappings":[{"cwd":"/w/alpha","cabinet":"/c/alpha/cabinet"}]}' > "$D/reg.json"
  OUT=$(bash -c "source '$PLUGIN_ROOT/hooks/lib/registry.sh'; registry_read")
  case "$OUT" in *'"alpha"'*) ok "migrate v0a mappings";; *) bad "migrate v0a" "$OUT";; esac
  printf '{"cabinets":[{"name":"b","path":"/c/b/cabinet","topics":["x"]}]}' > "$D/reg.json"
  OUT=$(bash -c "source '$PLUGIN_ROOT/hooks/lib/registry.sh'; registry_read")
  case "$OUT" in *'"b"'*'/c/b/cabinet'*) ok "migrate v0b list";; *) bad "migrate v0b" "$OUT";; esac
  mkdir -p "$D/legacy-proj/cabinet" "$D/bare-proj"
  printf '{"version":1,"cabinets":[{"cabinet_id":"c1","path":"%s/legacy-proj","name":"legacy-proj","created_at":"2026-01-01","last_session_at":"2026-02-01","roles":[]},{"cabinet_id":"c2","path":"%s/bare-proj","name":"bare","created_at":"","last_session_at":"","roles":[]}]}' "$D" "$D" > "$D/reg.json"
  OUT=$(bash -c "source '$PLUGIN_ROOT/hooks/lib/registry.sh'; registry_read")
  case "$OUT" in *legacy-proj/cabinet*) ok "migrate mac shape (cabinet subdir)";; *) bad "migrate mac path" "$OUT";; esac
  case "$OUT" in *'"bare"'*) ok "migrate mac shape (name key)";; *) bad "migrate mac name" "$OUT";; esac
  [ -f "$D/reg.json.bak" ] && ok "migration backup" || bad "migration backup" "no .bak"
  unset CABINET_REGISTRY_PATH; rm -rf "$D"
}

# --- 5. skip path from the brief works (Stop-hook id)
suite_skip_path() {
  D=$(mktemp -d /tmp/cabskip-XXXXXX); fresh_home "$D"; mkdir -p "$D/proj"
  # shellcheck disable=SC1091
  . "$PLUGIN_ROOT/hooks/lib/scaffold.sh"; scaffold_cabinet "$D/proj/cabinet" >/dev/null
  echo '{"source":"startup","cwd":"'"$D/proj"'"}' | bash "$PLUGIN_ROOT/hooks/scripts/session-start-triage.sh" > "$D/start.json"
  CTX=$(jq -r '.hookSpecificOutput.additionalContext' < "$D/start.json")
  SKIP=$(printf '%s' "$CTX" | grep -oE '/[^ ]*\.cabinet-flush-skip-[^ ]*' | head -n 1)
  [ -n "$SKIP" ] || { bad "skip path" "no skip path in brief"; rm -rf "$D"; return; }
  M=$(echo "$XDG_RUNTIME_DIR"/.cabinet-session-start-ppid-*); age "$M" 600
  touch "$SKIP"
  echo '{}' | bash "$PLUGIN_ROOT/hooks/scripts/session-stop-guard.sh" > "$D/stopA.json"
  R=$(cat "$D/stopA.json")
  [ "$R" = "{}" ] && ok "skip path passes once" || bad "skip path" "$R"
  echo '{}' | bash "$PLUGIN_ROOT/hooks/scripts/session-stop-guard.sh" > "$D/stopB.json"
  R2=$(jq -r .decision < "$D/stopB.json")
  [ "$R2" = "block" ] && ok "skip consumed (blocks again)" || bad "skip consumed" "$R2"
  rm -rf "$D"
}

# --- 6. pages load without schema.md
suite_pages_without_schema() {
  D=$(mktemp -d /tmp/cabpages-XXXXXX); fresh_home "$D"; mkdir -p "$D/proj"
  # shellcheck disable=SC1091
  . "$PLUGIN_ROOT/hooks/lib/scaffold.sh"; scaffold_cabinet "$D/proj/cabinet" >/dev/null
  printf -- "---\nsource: synthesized\nsynthesized_from: [x]\nlast_synthesized_at: 2026-01-01T00:00:00Z\nschema_version: 1\n---\n# P\nUNIQUEPAGESTRING\n" > "$D/proj/cabinet/engineer/pages/topic.md"
  CTX=$(echo '{"source":"startup","cwd":"'"$D/proj"'"}' | bash "$PLUGIN_ROOT/hooks/scripts/session-start-triage.sh" | jq -r '.hookSpecificOutput.additionalContext')
  case "$CTX" in *UNIQUEPAGESTRING*) ok "pages load without schema.md";; *) bad "pages without schema" "page content missing";; esac
  printf 'x\n' > "$D/proj/cabinet/engineer/pages/log.md"
  printf -- "---\nnope\n---\nPROPOSESTRING\n" > "$D/proj/cabinet/engineer/pages/other.proposed.md"
  CTX2=$(echo '{"source":"startup","cwd":"'"$D/proj"'"}' | bash "$PLUGIN_ROOT/hooks/scripts/session-start-triage.sh" | jq -r '.hookSpecificOutput.additionalContext')
  case "$CTX2" in *PROPOSESTRING*) bad "pages exclude proposed" "proposed.md leaked";; *) ok "pages exclude log/proposed";; esac
  rm -rf "$D"
}

# --- 7. role discovery ignores specs/hooks (+shared, empty, no-either)
suite_discovery() {
  D=$(mktemp -d /tmp/cabdisc-XXXXXX); fresh_home "$D"; mkdir -p "$D/proj"
  # shellcheck disable=SC1091
  . "$PLUGIN_ROOT/hooks/lib/scaffold.sh"; scaffold_cabinet "$D/proj/cabinet" >/dev/null
  mkdir -p "$D/proj/cabinet/specs" "$D/proj/cabinet/hooks" "$D/proj/cabinet/shared" \
    "$D/proj/cabinet/emptydir" "$D/proj/cabinet/customrole/raw"
  mkdir -p "$D/proj/cabinet/rolemdonly"; printf '# R\n' > "$D/proj/cabinet/rolemdonly/ROLE.md"
  ROLES=$(bash -c "source '$PLUGIN_ROOT/hooks/lib/scaffold.sh'; cabinet_list_roles '$D/proj/cabinet' '$PLUGIN_ROOT/roles'")
  for BAD in specs hooks shared emptydir; do
    case "$(printf '%s\n' "$ROLES" | grep -Fx "$BAD" || true)" in
      "") ok "discovery excludes $BAD";;
      *) bad "discovery $BAD" "leaked";;
    esac
  done
  case "$(printf '%s\n' "$ROLES" | grep -Fx customrole || true)" in customrole) ok "discovery includes raw-only role";; *) bad "discovery customrole" "$ROLES";; esac
  case "$(printf '%s\n' "$ROLES" | grep -Fx rolemdonly || true)" in rolemdonly) ok "discovery includes ROLE.md-only role";; *) bad "discovery rolemdonly" "$ROLES";; esac
  for R in chief_of_staff engineer tech_lead product_designer marketing researcher recruiter the_villain; do
    printf '%s\n' "$ROLES" | grep -Fxq "$R" && ok "default role $R" || bad "default role $R" "missing"
  done
  N=$(printf '%s\n' "$ROLES" | grep -c .)
  [ "$N" -eq 10 ] && ok "role count 10 (8 defaults + customrole + rolemdonly)" || bad "role count" "$N: $ROLES"
  rm -rf "$D"
}

# --- 8. brief size cap (default ~40KB, oldest trimmed first)
suite_brief_cap() {
  D=$(mktemp -d /tmp/cabcap-XXXXXX); fresh_home "$D"; mkdir -p "$D/proj"
  # shellcheck disable=SC1091
  . "$PLUGIN_ROOT/hooks/lib/scaffold.sh"; scaffold_cabinet "$D/proj/cabinet" >/dev/null
  python3 - "$D/proj/cabinet/engineer/raw/2026-01-01_big.md" <<'PYEOF'
import sys
with open(sys.argv[1], "w") as f:
    f.write("---\ndate: 2026-01-01\nsession: big\nsession_id: x\nrole: engineer\ntags: [t]\nschema_version: 1\n---\n\n")
    f.write("padding line number nine filler text here\n" * 4000)
PYEOF
  CTX=$(echo '{"source":"startup","cwd":"'"$D/proj"'"}' | CABINET_BRIEF_MAX_BYTES=2000 bash "$PLUGIN_ROOT/hooks/scripts/session-start-triage.sh" | jq -r '.hookSpecificOutput.additionalContext')
  case "$CTX" in *"oldest memory was trimmed first"*) ok "brief cap trims oldest first";; *) bad "brief cap" "no trim note";; esac
  case "$CTX" in *"Session Save Protocol"*) ok "brief keeps protocol after trim";; *) bad "brief protocol" "protocol lost";; esac
  rm -rf "$D"
}

# --- 9. villain bridge: fake codex + not-installed
suite_villain_bridge() {
  chmod +x "$PLUGIN_ROOT/tests/fixtures/villain/bin/"* 2>/dev/null
  VB="$PLUGIN_ROOT/hooks/scripts/villain-codex.sh"
  R=$(PATH="/usr/bin:/bin" bash "$VB" --preflight 2>&1); RC=$?
  case "$R" in *"status=unavailable reason=codex-not-installed"*) [ $RC -eq 3 ] && ok "villain not-installed" || bad "villain not-installed rc" "$RC";; *) bad "villain not-installed" "$R";; esac
  export PATH="$PLUGIN_ROOT/tests/fixtures/villain/bin:$PATH"
  export CABINET_CODEX_MODEL="gpt-6-fake"
  R=$(bash "$VB" --preflight); RC=$?
  case "$R" in "CABINET_VILLAIN status=ok model=gpt-6-fake"*"fatal=n/a") [ $RC -eq 0 ] && ok "villain preflight (fake codex)" || bad "villain preflight rc" "$RC";; *) bad "villain preflight" "$R";; esac
  D=$(mktemp -d /tmp/cabvil-XXXXXX)
  echo "Proposal: ship it." > "$D/prompt.md"
  R=$(bash "$VB" --prompt-file "$D/prompt.md" --out "$D/out.md"); RC=$?
  FIRST=$(printf '%s' "$R" | head -n 1)
  case "$FIRST" in "CABINET_VILLAIN status=ok model=gpt-6-fake effort=n/a fatal=1") [ $RC -eq 0 ] && ok "villain review fatal=1" || bad "villain review rc" "$RC";; *) bad "villain review" "$FIRST";; esac
  case "$R" in *"COUNTS: fatal=1"*) ok "villain review body follows";; *) bad "villain body" "$R";; esac
  R2=$(FAKE_CODEX_EMPTY=1 bash "$VB" --prompt-file "$D/prompt.md" --out "$D/out.md" 2>&1); RC=$?
  case "$R2" in *"status=failed reason=empty-output"*) [ $RC -eq 4 ] && ok "villain empty output fails" || bad "villain empty rc" "$RC";; *) bad "villain empty" "$R2";; esac
  R3=$(CODEX_EXIT=7 bash "$VB" --prompt-file "$D/prompt.md" --out "$D/out.md" 2>&1); RC=$?
  case "$R3" in *"status=failed"*) [ $RC -eq 4 ] && ok "villain nonzero exit fails" || bad "villain nonzero rc" "$RC";; *) bad "villain nonzero" "$R3";; esac
  R4=$(bash "$VB" --out 2>&1); RC=$?
  case "$R4" in *"status=unavailable reason=bad-usage"*) [ $RC -eq 3 ] && ok "villain bad usage" || bad "villain bad-usage rc" "$RC";; *) bad "villain bad-usage" "$R4";; esac
  unset CABINET_CODEX_MODEL; rm -rf "$D"
}

# --- 10. apply.sh self-write is not a hand edit
suite_apply_self_write() {
  D=$(mktemp -d /tmp/cabapply-XXXXXX); mkdir -p "$D/cabinet/engineer/raw"
  AP="$PLUGIN_ROOT/skills/process/scripts/apply.sh"
  BODY='---
source: synthesized
synthesized_from: [2026-01-01_x]
schema_version: 1
---
# X
- Claim. [[raw/2026-01-01_x|src: 2026-01-01_x]]'
  R1=$(printf '%s' "$BODY" | bash "$AP" --cabinet "$D/cabinet" --role engineer --page x.md)
  [ "$R1" = "created" ] && ok "apply created" || bad "apply created" "$R1"
  R2=$(printf '%s' "$BODY" | bash "$AP" --cabinet "$D/cabinet" --role engineer --page x.md)
  [ "$R2" = "updated" ] && ok "apply self-write is updated (not handedit)" || bad "apply updated" "$R2"
  age "$D/cabinet/engineer/pages/x.md" -30
  R3=$(printf '%s' "$BODY" | bash "$AP" --cabinet "$D/cabinet" --role engineer --page x.md)
  [ "$R3" = "proposed-handedit" ] && ok "apply detects real handedit" || bad "apply handedit" "$R3"
  printf -- "---\ndate: 2026-02-02\nsession: s\nsession_id: z\nrole: engineer\ntags: [t]\nschema_version: 1\n---\n\nUncited note.\n" > "$D/cabinet/engineer/raw/2026-02-02_unrelated.md"
  SCAN=$(bash "$PLUGIN_ROOT/skills/process/scripts/scan.sh" --validate "$D/cabinet" engineer 2>&1)
  [ $? -eq 1 ] && ok "apply uncited note still validates rc=1" || bad "apply scan" "$SCAN"
  rm -rf "$D"
}

# --- 11. lint: bad name warns; good passes; non-Write/Bash/missing pass
suite_raw_lint() {
  D=$(mktemp -d /tmp/cablint-XXXXXX); fresh_home "$D"; mkdir -p "$D/proj/cabinet/engineer/raw"
  LINT="$PLUGIN_ROOT/hooks/scripts/raw-entry-lint.sh"
  printf -- "---\nno session\n---\nx\n" > "$D/proj/cabinet/engineer/raw/2026-01-01_ok.md"
  R=$(jq -nc --arg f "$D/proj/cabinet/engineer/raw/2026-01-01_ok.md" '{tool_name:"Write",tool_input:{file_path:$f}}' | bash "$LINT" | jq -r '.hookSpecificOutput.additionalContext')
  case "$R" in *"schema violation"*) ok "lint warns missing schema_version";; *) bad "lint schema_version" "$R";; esac
  printf -- "---\nnope\n" > "$D/proj/cabinet/engineer/raw/badname.md"
  R2=$(jq -nc --arg f "$D/proj/cabinet/engineer/raw/badname.md" '{tool_name:"Write",tool_input:{file_path:$f}}' | bash "$LINT" | jq -r '.hookSpecificOutput.additionalContext')
  case "$R2" in *"schema violation"*) ok "lint warns bad filename";; *) bad "lint badname" "$R2";; esac
  R3=$(jq -nc --arg f "$D/nowhere.md" '{tool_name:"Write",tool_input:{file_path:$f}}' | bash "$LINT")
  [ "$R3" = "{}" ] && ok "lint passes missing file" || bad "lint missing" "$R3"
  R4=$(jq -nc --arg f "$D/proj/cabinet/engineer/raw/2026-01-01_ok.md" '{tool_name:"Bash",tool_input:{file_path:$f}}' | bash "$LINT")
  [ "$R4" = "{}" ] && ok "lint passes Bash writes (Stop hook covers them)" || bad "lint Bash" "$R4"
  rm -rf "$D"
}

for S in smoke emit empty_registry registry_migrate skip_path pages_without_schema discovery brief_cap villain_bridge apply_self_write raw_lint; do
  "suite_$S"
done
echo "---"
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
