#!/usr/bin/env bash
# Self-check for learn.sh: each hook event on fake transcripts, and the reviewer against a stub claude.
set -e
dir=$(mktemp -d); dir=$(cd "$dir" && pwd -P); trap 'rm -rf "$dir"' EXIT
learn=$(cd "$(dirname "$0")" && pwd)/learn.sh
unset LEARN_HOME
export CLAUDE_CODE_ENTRYPOINT=cli CLAUDE_CONFIG_DIR=$dir/cfg PATH=$dir/bin:$PATH STUB=$dir/stub
cfg=$CLAUDE_CONFIG_DIR
mkdir -p "$cfg/skills" "$dir/bin" "$dir/proj"
fail() { echo "FAIL: $*" >&2; exit 1; }
run() {
  local out; out=$(bash "$learn" <<<"$1")
  [ -z "$out" ] || jq -e . >/dev/null <<<"$out" || fail "not JSON: $out"
  printf '%s' "$out"
}
waitfor() { for _ in $(seq 50); do [ -e "$1" ] && return; sleep 0.1; done; fail "$2"; }
xs() { printf "%$1s" | tr ' ' x; }
turn() { # turn <prompt_id> <n>: n tool calls answered within that prompt
  for i in $(seq "$2"); do
    echo '{"type":"assistant","promptId":null,"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/x"}}]}}'
    echo "{\"type\":\"user\",\"promptId\":\"$1\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"content\":\"BODY-$i\"}]}}"
  done
}

# Stub claude: records args and stdin, sleeps STUB_SLEEP, then runs STUB_EDIT inside the stage.
cat >"$dir/bin/claude" <<'EOF'
#!/usr/bin/env bash
cat >"$STUB.stdin"; python3 -c 'import os; print(os.getsid(0))' >"$STUB.sid"; printf '%s\n' "$@" >"$STUB.args"
sleep "${STUB_SLEEP:-0}"; [ -z "$STUB_EDIT" ] || bash -c "$STUB_EDIT"
EOF
chmod +x "$dir/bin/claude"

# SessionStart injects USER.md only when there is one.
[ -z "$(run '{"hook_event_name":"SessionStart"}')" ] || fail "SessionStart output without USER.md"
echo "- prefers tabs" >"$cfg/USER.md"
run '{"hook_event_name":"SessionStart"}' | jq -e '.hookSpecificOutput.additionalContext | test("prefers tabs")' >/dev/null ||
  fail "SessionStart didn't inject USER.md"

# PostToolUse blocks over-cap memory files and nothing else.
post() { run "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$1\"}}"; }
mem=$cfg/projects/-p/memory/MEMORY.md; mkdir -p "$(dirname "$mem")"
xs 2200 >"$mem"; [ -z "$(post "$mem")" ] || fail "cap fired at 2200 chars"
xs 2201 >"$mem"; post "$mem" | jq -e '.decision == "block"' >/dev/null || fail "no block over the MEMORY.md cap"
xs 1376 >"$cfg/USER.md"; post "$cfg/USER.md" | jq -e '.decision == "block"' >/dev/null || fail "no block over the USER.md cap"
xs 9999 >"$dir/proj/MEMORY.md"; [ -z "$(post "$dir/proj/MEMORY.md")" ] || fail "cap fired outside the config dir"
amem=$cfg/agent-memory/verifier; mkdir -p "$amem"
xs 2200 >"$amem/MEMORY.md"; [ -z "$(post "$amem/MEMORY.md")" ] || fail "agent memory cap fired at 2200 chars"
xs 2201 >"$amem/MEMORY.md"; post "$amem/MEMORY.md" | jq -e '.decision == "block"' >/dev/null || fail "no block over the agent MEMORY.md cap"
xs 12000 >"$amem/topic.md"; [ -z "$(post "$amem/topic.md")" ] || fail "agent topic cap fired at 12000 chars"
xs 12001 >"$amem/topic.md"; post "$amem/topic.md" | jq -e '.decision == "block"' >/dev/null || fail "no block over the agent topic cap"
lmem=$dir/proj/.claude/agent-memory-local/verifier; mkdir -p "$lmem"
xs 12001 >"$lmem/topic.md"; post "$lmem/topic.md" | jq -e '.decision == "block"' >/dev/null || fail "no block over the local agent topic cap"
xs 20000 >"$cfg/projects/-p/memory/topic.md"; [ -z "$(post "$cfg/projects/-p/memory/topic.md")" ] || fail "cap fired on a project topic file"
rm -f "$amem/topic.md" "$lmem/topic.md" "$cfg/projects/-p/memory/topic.md"
echo "- prefers tabs" >"$cfg/USER.md"

# `learn.sh guard` (read-only agents' PreToolUse) allows Write/Edit only in the agent's own memory dir, and
# denies with exit 2, also when jq or the script itself is missing.
gin() { echo "{\"agent_type\":\"$1\",\"cwd\":\"$dir/proj\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$2\"}}"; }
guard() { local rc=0; gin "$1" "$2" | bash "$learn" guard 2>/dev/null || rc=$?; echo "$rc"; }
for ok in "$amem/MEMORY.md" "$dir/proj/.claude/agent-memory-local/verifier/x.md" "$dir/proj/.claude/agent-memory/verifier/x.md"; do
  [ "$(guard verifier "$ok")" = 0 ] || fail "guard denied $ok"
done
ln -s "$dir/proj" "$amem/link"; touch "$dir/proj/app.py"; ln -s "$dir/proj/app.py" "$amem/flink"; ln -s "$dir/proj/none" "$amem/dangle"
for bad in "$dir/proj/app.py" "$amem/../../x" "$amem/new/../../../proj/app.py" "$amem/link/app.py" "$amem/flink" "$amem/dangle" \
  "$cfg/agent-memory/critic/x.md" \
  "$dir/proj/src/agent-memory/verifier/x.py" "$dir/proj/src/.claude/agent-memory-local/verifier/x.py" \
  "$cfg/agent-memory/critic/agent-memory/verifier/x.md" "agent-memory/verifier/rel.md" ""; do
  [ "$(guard verifier "$bad")" = 2 ] || fail "guard allowed '$bad'"
done
[ "$(guard "" "$amem/x.md")" = 2 ] || fail "guard allowed a write without agent_type"
mkdir "$dir/nojq"; ln -s "$(command -v cat)" "$dir/nojq/"
rc=0; gin verifier "$amem/x.md" | PATH=$dir/nojq "$(command -v bash)" "$learn" guard 2>/dev/null || rc=$?
[ "$rc" = 2 ] || fail "guard without jq exited $rc"
hook=$(sed -n "s/^ *command: '\(.*\)'$/\1/p" "$(dirname "$learn")/../agents/verifier.md")
rc=0; gin verifier "$amem/x.md" | bash -c "$hook" 2>/dev/null || rc=$?
[ "$rc" = 2 ] || fail "frontmatter hook with learn.sh missing exited $rc"
mkdir -p "$dir/withhooks" && ln -s "$(dirname "$learn")" "$dir/withhooks/hooks"
gin verifier "$dir/withhooks/agent-memory/verifier/x.md" | CLAUDE_CONFIG_DIR=$dir/withhooks bash -c "$hook" ||
  fail "frontmatter hook denied the agent's own memory"

# SessionEnd spawns a detached reviewer with a digest of the session.
t=$dir/s1.jsonl
{
  echo '{"type":"user","message":{"content":"FIRST PROMPT"}}'
  echo '{"type":"user","message":{"content":[{"type":"image"},{"type":"text","text":"[Request interrupted by user]"}]}}'
  echo '{"type":"attachment","attachment":{"type":"queued_command","commandMode":"prompt","prompt":"MIDTURN FIX"}}'
  echo '{"type":"attachment","attachment":{"type":"queued_command","commandMode":"prompt","prompt":"<cross-session-message from=\"x\">PEER</cross-session-message>"}}'
  echo '{"type":"user","message":{"content":"<task-notification><result>SUBAGENT</result></task-notification>"}}'
  echo '{"type":"user","isCompactSummary":true,"message":{"content":"SUMMARY"}}'
  echo '{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":[{"type":"text","text":"ARRAY ERROR"}]}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"CLAUDE SAYS"}]}}'
  echo 'not json, half-written line'
  turn p1 30
} >"$t"
end() { run "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"$1\",\"transcript_path\":\"$2\",\"cwd\":\"$3\"}"; }
start=$SECONDS
STUB_SLEEP=3 end s1 "$t" "$dir/proj" >/dev/null
[ $((SECONDS - start)) -lt 2 ] || fail "SessionEnd waited for the reviewer"
waitfor "$STUB.args" "reviewer never ran"
[ "$(cat "$STUB.sid")" != "$(python3 -c 'import os; print(os.getsid(0))')" ] || fail "reviewer not in its own session"
for want in "FIRST PROMPT" "USER: [image]" "[Request interrupted by user]" "MIDTURN FIX" "ARRAY ERROR" "CLAUDE SAYS" "TOOL: Read /x"; do
  grep -qF "$want" "$STUB.stdin" || fail "digest lacks: $want"
done
for bad in PEER SUBAGENT SUMMARY BODY- "half-written"; do
  ! grep -qF "$bad" "$STUB.stdin" || fail "digest includes: $bad"
done
for flag in --restricted disableAllHooks --no-session-persistence acceptEdits; do
  grep -qF -- "$flag" "$STUB.args" || fail "reviewer launched without $flag"
done
for _ in $(seq 50); do grep -q '^== end' "$cfg/learn/learn.log" && break; sleep 0.1; done
grep -q '^== end' "$cfg/learn/learn.log" || fail "reviewer never finished"

# The same session ending again (resume, exit) is not re-reviewed, until 30 new tool calls arrive.
rm -f "$STUB.args"; end s1 "$t" "$dir/proj" >/dev/null; sleep 1
[ ! -e "$STUB.args" ] || fail "re-reviewed an already reviewed session"
turn p2 30 >>"$t"; end s1 "$t" "$dir/proj" >/dev/null
waitfor "$STUB.args" "resumed session's new work never reviewed"
! grep -qF "FIRST PROMPT" "$STUB.stdin" || fail "resumed review repeated old lines"
rm -f "$STUB.args"; turn p1 29 >"$dir/s2.jsonl"; end s2 "$dir/s2.jsonl" "$dir/proj" >/dev/null; sleep 1
[ ! -e "$STUB.args" ] || fail "reviewed a session under 30 tool calls"

# The reviewer finds project memory by git root, from a subdirectory of a repo whose path has a dot.
git init -q "$dir/re.po"; mkdir "$dir/re.po/sub"
memdir=$cfg/projects/$(printf %s "$dir/re.po" | sed 's/[^a-zA-Z0-9]/-/g')/memory
mkdir -p "$memdir"; echo x >"$memdir/marker.md"
rm -f "$STUB.args"; turn p1 30 >"$dir/s3.jsonl"; end s3 "$dir/s3.jsonl" "$dir/re.po/sub" >/dev/null
waitfor "$STUB.args" "reviewer never ran for the git subdir"
grep -qF "memory/marker.md" "$STUB.args" || fail "memory not found from a git subdirectory"
for _ in $(seq 50); do [ "$(grep -c '^== end' "$cfg/learn/learn.log")" -ge 3 ] && break; sleep 0.1; done

# review applies valid edits and refuses unsafe or stale ones.
live=$cfg/projects/-p/memory
printf -- '- [a](a.md) — x\n' >"$live/MEMORY.md"; echo a >"$live/a.md"; echo b >"$live/b.md"
mkdir -p "$cfg/skills/mine" "$cfg/skills/synced/x" "$dir/vendor"
echo mine >"$cfg/skills/mine/SKILL.md"; echo vendor >"$dir/vendor/SKILL.md"; ln -s "$dir/vendor" "$cfg/skills/vendor"
export LIVE=$live
STUB_EDIT='
  echo "- new fact" >>USER.md
  : >memory/b.md
  printf "%2201s" | tr " " x >memory/MEMORY.md
  echo changed >memory/a.md; echo peer >"$LIVE/a.md"
  echo patched >skills/mine/SKILL.md
  mkdir -p skills/evil skills/synced/x skills/vendor
  printf -- "---\nname: evil\nhooks:\n  Stop: x\n---\n" >skills/evil/SKILL.md
  echo hacked >skills/synced/x/SKILL.md
  echo hacked >skills/vendor/SKILL.md
  echo stray >notes.md' \
  bash "$learn" review "$(mktemp)" "$live" s9 /proj >"$dir/review.log" 2>&1
grep -q "new fact" "$cfg/USER.md" || fail "valid USER.md edit not applied"
[ ! -e "$live/b.md" ] || fail "emptied file not deleted"
grep -q patched "$cfg/skills/mine/SKILL.md" || fail "own skill patch not applied"
[ "$(cat "$live/MEMORY.md")" = "- [a](a.md) — x" ] || fail "over-cap MEMORY.md applied"
[ "$(cat "$live/a.md")" = peer ] || fail "overwrote a file changed live"
[ ! -e "$cfg/skills/evil" ] || fail "skill adding hooks applied"
[ ! -e "$cfg/skills/synced/x/SKILL.md" ] || fail "synced skill written"
[ "$(cat "$dir/vendor/SKILL.md")" = vendor ] || fail "wrote through a symlinked skill"
[ ! -e "$cfg/notes.md" ] && [ ! -e "$cfg/skills/notes.md" ] || fail "stray file applied"
[ "$(grep -c '^rejected' "$dir/review.log")" -eq 6 ] || fail "expected 6 rejections: $(cat "$dir/review.log")"

# A review waits while another holds the lock.
rm -f "$STUB.args"; exec 8>"$cfg/learn/lock"; python3 -c 'import fcntl; fcntl.flock(8, fcntl.LOCK_EX)'
bash "$learn" review "$(mktemp)" "$live" s10 /proj >/dev/null 2>&1 8>&- & sleep 1
[ ! -e "$STUB.args" ] || fail "review ran while another held the lock"
exec 8>&-; wait; [ -e "$STUB.args" ] || fail "review never ran once the lock was free"

# Stop reminds after long turns only, never while planning or already continuing.
t=$dir/stop.jsonl
stop() { run "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"$t\",\"prompt_id\":\"p1\",\"permission_mode\":\"${1:-auto}\",\"stop_hook_active\":${2:-false}}"; }
{ echo '{"type":"user","promptId":"p1","message":{"content":"do it"}}'; turn p1 16; } >"$t"
[ -z "$(stop plan)" ] || fail "reminder in plan mode"
[ -z "$(stop auto true)" ] || fail "reminder while stop_hook_active"
[ -z "$(CLAUDE_CODE_ENTRYPOINT=sdk-cli stop)" ] || fail "reminder in a headless run"
[ -z "$(run '{"hook_event_name":"Stop","prompt_id":"p1"}')" ] || fail "output without a transcript"
j="{\"hook_event_name\":\"Stop\",\"transcript_path\":\"$t\"}"
[ -z "$(run "$j")" ] || fail "output without a prompt_id"
stop | jq -e '.hookSpecificOutput.additionalContext | test("worth keeping")' >/dev/null || fail "no reminder after 16 tool calls"
{ turn p0 20; turn p1 14; } >"$t"
[ -z "$(stop)" ] || fail "reminder after 14 tool calls (earlier turns must not count)"

# The reminder files project workflows in the main checkout's .claude/skills/, and outside git in auto memory.
{ echo '{"type":"user","promptId":"p1","message":{"content":"do it"}}'; turn p1 16; } >"$t"
nudge() { run "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"$t\",\"prompt_id\":\"p1\",\"cwd\":\"$1\"}" | jq -r '.hookSpecificOutput.additionalContext'; }
nudge "$dir/re.po/sub" | grep -qF "in $dir/re.po/.claude/skills/ when it only applies" || fail "no project skill path in a repo"
git -C "$dir/re.po" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$dir/re.po" worktree add -q "$dir/wt"
nudge "$dir/wt" | grep -qF "in $dir/re.po/.claude/skills/ when it only applies" || fail "worktree reminder doesn't name the main checkout"
nudge "$dir/proj" | grep -qF "for this directory only goes in your auto memory" || fail "no auto memory route outside git"
! nudge "$dir/proj" | grep -qF "when it only applies to this project" || fail "project skill path outside git"

# Stop has the session that wrote an over-cap USER.md or project MEMORY.md consolidate it, and no other session.
ts() { jq -nr --argjson o "$1" 'now + $o | floor | todate | sub("Z$"; ".000Z")'; }
age() { touch -t "$(jq -nr --argjson o "$1" 'now + $o | strflocaltime("%Y%m%d%H%M.%S")')" "$2"; }
prompt() { echo "{\"type\":\"user\",\"promptId\":\"$1\",\"timestamp\":\"$(ts "$2")\",\"message\":{\"content\":\"do it\"}}"; }
append() { echo "{\"type\":\"assistant\",\"timestamp\":\"$(ts "$1")\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":\"echo x >> $2\"}}]}}"; }
{ prompt p1 -60; append -50 "$cfg/USER.md"; } >"$t"
cstop() { run "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"$t\",\"prompt_id\":\"p1\",\"cwd\":\"$1\",\"permission_mode\":\"${2:-auto}\",\"stop_hook_active\":${3:-false}}"; }
xs 1376 >"$cfg/USER.md"
cstop "$dir/proj" | jq -e '.decision == "block" and (.reason | test("USER.md is 1376/1375"))' >/dev/null || fail "no Stop block for USER.md over its cap"
[ -z "$(cstop "$dir/proj" plan)" ] || fail "cap block in plan mode"
[ -z "$(cstop "$dir/proj" auto true)" ] || fail "cap block while stop_hook_active"
age -7200 "$cfg/USER.md"
[ -z "$(cstop "$dir/proj")" ] || fail "cap block for a USER.md changed before this turn"
echo "{\"type\":\"user\",\"promptId\":\"p1\",\"timestamp\":\"$(ts 60)\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"content\":\"x\"}]}}" >>"$t"
age -30 "$cfg/USER.md"
cstop "$dir/proj" | jq -e '.decision == "block"' >/dev/null || fail "turn start not taken from the turn's first entry"
{ prompt p1 -60; append -50 "$dir/proj/notes.md"; } >"$t"; xs 1376 >"$cfg/USER.md"
[ -z "$(cstop "$dir/proj")" ] || fail "cap block for a USER.md this session never named (another session wrote it)"
{ prompt p1 -60; append -90 "$cfg/USER.md"; } >"$t"
[ -z "$(cstop "$dir/proj")" ] || fail "cap block for a USER.md named only before this turn"
echo "- prefers tabs" >"$cfg/USER.md"
{ prompt p1 -60; append -50 "~/.claude/projects/${memdir#"$cfg"/projects/}/MEMORY.md"; } >"$t"
xs 2201 >"$memdir/MEMORY.md"
cstop "$dir/re.po/sub" | jq -e '.decision == "block" and (.reason | test("memory/MEMORY.md is 2201/2200"))' >/dev/null ||
  fail "no Stop block for the project's MEMORY.md"
{ prompt p1 -60; echo "{\"type\":\"assistant\",\"timestamp\":\"$(ts -50)\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Edit\",\"input\":{\"file_path\":\"$memdir/MEMORY.md\"}}]}}"; } >"$t"
cstop "$dir/re.po/sub" | jq -e '.decision == "block"' >/dev/null || fail "an Edit's file_path doesn't count as naming the file"
xs 2200 >"$memdir/MEMORY.md"
[ -z "$(cstop "$dir/re.po/sub")" ] || fail "Stop cap block at 2200 chars"
echo '{"type":"user","promptId":"p9","message":{"content":"no timestamp"}}' >"$t"; xs 2201 >"$memdir/MEMORY.md"
[ -z "$(cstop "$dir/re.po/sub")" ] || fail "cap block for a turn not in the transcript"

# A write made while answering the reminder (a stop_hook_active continuation) is caught at the next turn's Stop.
sstop() { run "{\"hook_event_name\":\"Stop\",\"session_id\":\"s7\",\"transcript_path\":\"$t\",\"prompt_id\":\"$1\",\"cwd\":\"$dir/re.po/sub\",\"stop_hook_active\":${2:-false}}"; }
{ prompt p1 -60; append -15 "$memdir/MEMORY.md"; prompt p2 60; } >"$t"
xs 100 >"$memdir/MEMORY.md"
[ -z "$(sstop p1)" ] && [ -e "$cfg/learn/s7.stop" ] || fail "Stop left no marker"
age -20 "$cfg/learn/s7.stop"; xs 2201 >"$memdir/MEMORY.md"; age -15 "$memdir/MEMORY.md"
[ -z "$(sstop p1 true)" ] || fail "cap block while stop_hook_active"
sstop p2 | jq -e '.decision == "block"' >/dev/null || fail "write made answering the reminder not caught next turn"
age -3600 "$memdir/MEMORY.md"
[ -z "$(sstop p2)" ] || fail "cap block for a file unchanged since the last Stop"

echo PASS
