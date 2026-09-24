#!/usr/bin/env bash
# Self-check for learn.sh: each hook event on fake transcripts, and the reviewer against a stub claude.
set -e
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
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
xs() { head -c "$1" /dev/zero | tr '\0' x; }
turn() { # turn <prompt_id> <n>: n tool calls answered within that prompt
  for i in $(seq "$2"); do
    echo '{"type":"assistant","promptId":null,"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/x"}}]}}'
    echo "{\"type\":\"user\",\"promptId\":\"$1\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"content\":\"BODY-$i\"}]}}"
  done
}

# Stub claude: records args and stdin, sleeps STUB_SLEEP, then runs STUB_EDIT inside the stage.
cat >"$dir/bin/claude" <<'EOF'
#!/usr/bin/env bash
cat >"$STUB.stdin"; printf '%s\n' "$@" >"$STUB.args"
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
echo "- prefers tabs" >"$cfg/USER.md"

# `learn.sh guard` (read-only agents' PreToolUse) allows Write/Edit only in the agent's own memory dir, and
# denies with exit 2, also when jq or the script itself is missing.
gin() { echo "{\"agent_type\":\"$1\",\"cwd\":\"$dir/proj\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$2\"}}"; }
guard() { local rc=0; gin "$1" "$2" | bash "$learn" guard 2>/dev/null || rc=$?; echo "$rc"; }
for ok in "$amem/MEMORY.md" "$dir/proj/.claude/agent-memory-local/verifier/x.md" "$dir/proj/.claude/agent-memory/verifier/x.md"; do
  [ "$(guard verifier "$ok")" = 0 ] || fail "guard denied $ok"
done
ln -s "$dir/proj" "$amem/link"
for bad in "$dir/proj/app.py" "$amem/../../x" "$amem/link/app.py" "$cfg/agent-memory/critic/x.md" \
  "$dir/proj/src/agent-memory/verifier/x.py" "$dir/proj/src/.claude/agent-memory-local/verifier/x.py" \
  "$cfg/agent-memory/critic/agent-memory/verifier/x.md" "agent-memory/verifier/rel.md" ""; do
  [ "$(guard verifier "$bad")" = 2 ] || fail "guard allowed '$bad'"
done
[ "$(guard "" "$amem/x.md")" = 2 ] || fail "guard allowed a write without agent_type"
mkdir "$dir/nojq"; ln -s "$(command -v cat)" "$(command -v realpath)" "$dir/nojq/"
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
  xs() { head -c "$1" /dev/zero | tr "\0" x; }; xs 2201 >memory/MEMORY.md
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

# Stop reminds after long turns only, never while planning or already continuing.
t=$dir/stop.jsonl
stop() { run "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"$t\",\"prompt_id\":\"p1\",\"permission_mode\":\"${1:-auto}\",\"stop_hook_active\":${2:-false}}"; }
{ echo '{"type":"user","promptId":"p1","message":{"content":"do it"}}'; turn p1 16; } >"$t"
[ -z "$(stop plan)" ] || fail "reminder in plan mode"
[ -z "$(stop auto true)" ] || fail "reminder while stop_hook_active"
[ -z "$(CLAUDE_CODE_ENTRYPOINT=sdk-cli stop)" ] || fail "reminder in a headless run"
[ -z "$(run '{"hook_event_name":"Stop","prompt_id":"p1"}')" ] || fail "output without a transcript"
[ -z "$(run "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"$t\"}")" ] || fail "output without a prompt_id"
stop | jq -e '.hookSpecificOutput.additionalContext | test("worth keeping")' >/dev/null || fail "no reminder after 16 tool calls"
{ turn p0 20; turn p1 14; } >"$t"
[ -z "$(stop)" ] || fail "reminder after 14 tool calls (earlier turns must not count)"

echo PASS
