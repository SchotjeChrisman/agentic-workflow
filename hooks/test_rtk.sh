#!/usr/bin/env bash
# Self-check for rtk.sh: anything an ask or deny rule names (user, start-dir, repo-root and main-checkout files),
# diffs and subagent calls pass through untouched; everything else goes to rtk.
set -e
command -v rtk >/dev/null || { echo "SKIP: rtk not installed"; exit 0; }
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/cfg" "$dir/repo/.claude" "$dir/repo/sub/.claude"
git -C "$dir/repo" init -q && git -C "$dir/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$dir/repo" worktree add -q "$dir/wt"
echo '{"permissions":{"ask":["Bash(git commit *)","Bash(git -C * push *)","Bash(git push *)","Read(x)"]}}' >"$dir/cfg/settings.json"
echo '{"permissions":{"ask":["Bash(cargo test *)"]}}' >"$dir/repo/sub/.claude/settings.json"
echo '{"permissions":{"deny":["Bash(npx:*)"]}}' >"$dir/repo/.claude/settings.local.json"
run() { jq -nc --arg c "$1" --arg d "${3:-$dir/repo/sub}" --arg a "${2:-}" \
  '{tool_name:"Bash",tool_input:{command:$c},cwd:$d} + (if $a == "" then {} else {agent_id:$a} end)' |
  CLAUDE_CONFIG_DIR=$dir/cfg CLAUDE_PROJECT_DIR=${4:-${3:-$dir/repo/sub}} bash "$(dirname "$0")/rtk.sh"; }
for c in 'git status' 'ls -la' 'cargo build' 'timeout 60 cargo build'; do
  [[ $(run "$c" | jq -r .hookSpecificOutput.updatedInput.command) == *"rtk ${c#timeout 60 }" ]] || { echo "FAIL: '$c' not rewritten"; exit 1; }
done
for c in 'git commit -m x' 'timeout 5 git push origin main' 'git status && git push' 'git -C /tmp push' \
  'git  commit -m x' $'git \\\ncommit -m x' 'cargo test' 'npx vitest run' 'git diff' 'git show HEAD' 'git -C /tmp diff' 'git --no-pager diff' \
  'git -c color.ui=never diff HEAD' 'git --no-pager show HEAD' 'git log -p -1' 'git log --patch' 'git stash show -p' 'gh pr diff 12'; do
  [ -z "$(run "$c")" ] || { echo "FAIL: rewrote guarded '$c'"; exit 1; }
done
[ -z "$(run 'cargo test' '' "$dir/repo" "$dir/repo/sub")" ] || { echo "FAIL: missed the start dir's rules after cd"; exit 1; }
[ -z "$(run 'npx vitest run' '' "$dir/wt")" ] || { echo "FAIL: missed the main checkout's local rules from a worktree"; exit 1; }
[ -z "$(run 'cargo build' agent-1)" ] || { echo "FAIL: rewrote inside a subagent"; exit 1; }
echo PASS
