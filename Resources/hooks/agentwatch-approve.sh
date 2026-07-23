#!/bin/bash
# AgentWatch PreToolUse hook shim.
#
# Reads the hook JSON on stdin, hands it to the running AgentWatch app via a
# file drop, and blocks until the user clicks Allow / Deny / Ask in the app —
# then emits the permission decision Claude Code expects.
#
# Fail-safe by design: if AgentWatch isn't running (no .listening marker) or it
# doesn't answer in time, this exits 0 with no output, which defers to Claude
# Code's normal in-terminal permission prompt. It never auto-allows and never
# hangs an agent.

set -u
umask 077                       # request files carry command/content → keep them 0600
BASE="$HOME/Library/Application Support/AgentWatch/approvals"
REQ="$BASE/requests"
RES="$BASE/responses"
MARKER="$BASE/.listening"

# App must be listening AND fresh. The app rewrites the marker every ~0.3s, so a
# marker older than 5s means it crashed/quit → defer to the normal terminal flow.
[ -f "$MARKER" ] || exit 0
NOW=$(date +%s)
MT=$(stat -f %m "$MARKER" 2>/dev/null || echo 0)
[ $((NOW - MT)) -le 5 ] || exit 0

mkdir -p "$REQ" "$RES" 2>/dev/null || exit 0

ID=$(/usr/bin/uuidgen)
# Persist the raw hook payload atomically (write to temp, then rename) so the
# app never reads a half-written file. Filename (the id) correlates the response.
TMP="$REQ/.$ID.json.tmp"
cat > "$TMP" || { rm -f "$TMP"; exit 0; }
mv -f "$TMP" "$REQ/$ID.json" || { rm -f "$TMP"; exit 0; }

# Poll for the decision (~110s; settings.json sets the hook timeout to 120s).
i=0
while [ "$i" -lt 550 ]; do
    if [ -f "$RES/$ID" ]; then
        DEC=$(cat "$RES/$ID" 2>/dev/null)
        rm -f "$RES/$ID" "$REQ/$ID.json" 2>/dev/null
        case "$DEC" in
            allow)
                printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Approved in AgentWatch"}}'
                ;;
            deny)
                printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Denied in AgentWatch"}}'
                ;;
            *)
                : # "ask" or anything else → empty output = normal permission flow
                ;;
        esac
        exit 0
    fi
    sleep 0.2
    i=$((i + 1))
done

# Timed out waiting for the user → clean up and defer to normal flow.
rm -f "$REQ/$ID.json" 2>/dev/null
exit 0
