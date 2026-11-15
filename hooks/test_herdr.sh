#!/usr/bin/env bash
# Self-check for herdr.sh with stub `herdr` and `hc` binaries that log their arguments.
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/bin"
log=$dir/calls.log
script=$(cd "$(dirname "$0")" && pwd)/herdr.sh

cat >"$dir/bin/herdr" <<'STUB'
#!/usr/bin/env bash
echo "herdr $*" >>"$STUB_LOG"
[ "$1 $2" = "tab create" ] && echo '{"result":{"tab":{"tab_id":"w1:t7"},"root_pane":{"pane_id":"w1:p9"}}}'
exit 0
STUB
cat >"$dir/bin/hc" <<'STUB'
#!/usr/bin/env bash
echo "hc $*" >>"$STUB_LOG"
if [ "$1" = get ] && [ "$2" = t8 ]; then echo "$STUB_CALLER_JSON"
elif [ "$1" = get ]; then echo '{"state":"live"}'; fi
exit 0
STUB
printf '#!/bin/sh\n' >"$dir/bin/claude"
chmod +x "$dir/bin/herdr" "$dir/bin/hc" "$dir/bin/claude"

fail() { echo "FAIL: $1"; exit 1; }
calls() { cat "$log" 2>/dev/null; }
# Each case runs in a clean environment so the host's own herdr variables cannot leak in.
as() {
  local kind=$1; shift
  : >"$log"
  case $kind in
    tui) set -- env HERDR_ENV=1 HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p1 "$@" ;;
    desktop) set -- env HC_TERMINAL_ID=t8 "$@" ;;
    none) set -- env "$@" ;;
  esac
  env -i PATH="$dir/bin:$PATH" HOME="$dir" HERDR_STATE_DIR="$dir/state" STUB_LOG="$log" \
    STUB_CALLER_JSON='{"labels":{"herdr.space":"spX"}}' "$@"
}
event() { echo "{\"hook_event_name\":\"$1\",\"reason\":\"${2:-other}\"}"; }

# Outside herdr: no output, no calls.
out=$(event SessionStart | as none bash "$script")
[ -z "$out" ] && [ -z "$(calls)" ] || fail "output or calls outside herdr"
as none bash "$script" run a "$dir" task 2>/dev/null && fail "run outside herdr succeeded"

# The desktop app without a space label counts as outside herdr.
out=$(event SessionStart | as desktop env STUB_CALLER_JSON='{"labels":{}}' bash "$script")
[ -z "$out" ] || fail "note for a desktop terminal without a space"

# TUI: note for the main session, none for a tab session.
out=$(event SessionStart | as tui bash "$script")
grep -q 'run \[--agent TYPE\]' <<<"$out" || fail "no note in the TUI"
out=$(event SessionStart | as tui CLAUDE_HERDR_CHILD=1 bash "$script")
[ -z "$out" ] || fail "tab session got the note"

# TUI run: tab in the caller's workspace, agent started in its pane, ledger written, user tab untouched.
as tui bash "$script" run --agent verifier probe "$dir" "do it" >/dev/null || fail "tui run failed"
calls | grep -q 'tab create --workspace w1 --cwd .* --label probe --env CLAUDE_HERDR_CHILD=1 --no-focus' || fail "tui tab create"
calls | grep -q 'agent start probe --kind claude --pane w1:p9 -- --agent verifier' || fail "tui agent start"
calls | grep -q 'agent prompt probe do it' && calls | grep -q 'write your full report to .*/probe.md' || fail "tui agent prompt"
grep -q "^probe	w1:t7$" "$dir/state/w1_p1.tabs" || fail "tui ledger"
as tui bash "$script" run probe "$dir" again 2>/dev/null && fail "duplicate name accepted"
as tui bash "$script" run Bad "$dir" task 2>/dev/null && fail "bad name accepted"

# TUI close: refuses unlisted tabs, closes the listed one by its tab id and drops it.
as tui bash "$script" close theirs 2>/dev/null && fail "closed a tab it did not open"
[ -z "$(calls)" ] || fail "calls made for an unlisted tab"
as tui bash "$script" close probe || fail "tui close failed"
calls | grep -qx "herdr tab close w1:t7" || fail "tui close call: $(calls)"
[ ! -s "$dir/state/w1_p1.tabs" ] || fail "ledger not emptied"

# TUI SessionEnd: closes what is left, only those, and not on /clear.
as tui bash "$script" run one "$dir" t >/dev/null; as tui bash "$script" run two "$dir" t >/dev/null
event SessionEnd clear | as tui bash "$script"
[ -z "$(calls)" ] || fail "SessionEnd closed tabs on /clear"
event SessionEnd logout | as tui bash "$script"
[ "$(calls | grep -c 'tab close')" = 2 ] && [ ! -e "$dir/state/w1_p1.tabs" ] || fail "SessionEnd close: $(calls)"

# Desktop: terminal labeled with the caller's space, killed and removed on close.
as desktop bash "$script" run job "$dir" "do it" >/dev/null || fail "desktop run failed"
calls | grep -q 'hc run --bg --no-notify --name job --cwd .* --label herdr.space=spX env CLAUDE_HERDR_CHILD=1 .*/bin/claude' || fail "desktop run"
calls | grep -q 'hc wait job' || fail "desktop wait"
as desktop bash "$script" send job "more" >/dev/null || fail "desktop send failed"
calls | grep -q 'hc send --wait .* job more' || fail "desktop send"
as desktop bash "$script" close t2 2>/dev/null && fail "desktop closed a terminal it did not open"
as desktop bash "$script" close job || fail "desktop close failed"
calls | grep -q 'hc kill job' && calls | grep -q 'hc rm job' || fail "desktop close calls"

echo PASS
