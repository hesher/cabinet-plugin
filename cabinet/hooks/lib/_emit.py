#!/usr/bin/env python3
"""Validate hook JSON output against one of 6 schemas.

Usage: echo '<json>' | python3 _emit.py <schema>

Schemas:
  session_start     {"hookSpecificOutput": {"hookEventName": "SessionStart",
                    "additionalContext": "<non-empty string>"}}
  post_tool_warn    {"hookSpecificOutput": {"hookEventName": "PostToolUse",
                    "additionalContext": "<non-empty string>"}}
  post_tool_pass    {}
  stop_block        {"decision": "block", "reason": "<non-empty string>"}
  stop_pass         {}
  stop_user_message {"systemMessage": "<non-empty string>"}

Unknown keys, wrong event names and empty strings are rejected with exit 2.
On success the input is printed back as compact JSON.
"""
import json
import sys

SCHEMAS = (
    "session_start",
    "post_tool_warn",
    "post_tool_pass",
    "stop_block",
    "stop_pass",
    "stop_user_message",
)

EVENT_FOR = {
    "session_start": "SessionStart",
    "post_tool_warn": "PostToolUse",
}


def fail(msg):
    sys.stderr.write("cabinet _emit: %s\n" % msg)
    return 2


def nonempty_string(v):
    return isinstance(v, str) and len(v) > 0


def check_hook_output(obj, event):
    if set(obj.keys()) != {"hookSpecificOutput"}:
        return "top-level keys must be exactly [hookSpecificOutput]"
    inner = obj["hookSpecificOutput"]
    if not isinstance(inner, dict):
        return "hookSpecificOutput must be an object"
    if set(inner.keys()) != {"hookEventName", "additionalContext"}:
        return "hookSpecificOutput keys must be exactly [hookEventName, additionalContext]"
    if inner["hookEventName"] != event:
        return "hookEventName must be %r" % event
    if not nonempty_string(inner["additionalContext"]):
        return "additionalContext must be a non-empty string"
    return None


def main(argv):
    if len(argv) != 2 or argv[1] not in SCHEMAS:
        sys.stderr.write("usage: _emit.py <%s>\n" % "|".join(SCHEMAS))
        return 2
    schema = argv[1]
    try:
        raw = sys.stdin.read()
        obj = json.loads(raw)
    except Exception as e:
        return fail("invalid JSON: %s" % e)
    if not isinstance(obj, dict):
        return fail("top level must be an object")
    err = None
    if schema in EVENT_FOR:
        err = check_hook_output(obj, EVENT_FOR[schema])
    elif schema in ("post_tool_pass", "stop_pass"):
        if obj != {}:
            err = "pass payload must be exactly {}"
    elif schema == "stop_block":
        if set(obj.keys()) != {"decision", "reason"}:
            err = 'keys must be exactly [decision, reason]'
        elif obj["decision"] != "block":
            err = 'decision must be "block"'
        elif not nonempty_string(obj["reason"]):
            err = "reason must be a non-empty string"
    elif schema == "stop_user_message":
        if set(obj.keys()) != {"systemMessage"}:
            err = "keys must be exactly [systemMessage]"
        elif not nonempty_string(obj["systemMessage"]):
            err = "systemMessage must be a non-empty string"
    if err:
        return fail("%s: %s" % (schema, err))
    sys.stdout.write(json.dumps(obj, separators=(",", ":")))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
