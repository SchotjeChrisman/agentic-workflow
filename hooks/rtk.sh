#!/usr/bin/env bash
# PreToolUse (Bash) hook: rtk (github.com/rtk-ai/rtk) rewrites main-session commands so their output reaches
# Claude compressed. Claude Code checks permission rules against the rewritten command, so `rtk git commit`
# would slip past `Bash(git commit *)`: anything an ask or deny rule names is left untouched. Diffs in any form
# stay exact for the verifier, and subagents get raw output to quote as evidence. Read-only commands lose their
# built-in approval as `rtk ...` and go to the classifier instead: this assumes auto mode.
input=$(cat)
command -v rtk >/dev/null && command -v jq >/dev/null || exit 0
field() { jq -r "$1 // empty" <<<"$input"; }
[ -z "$(field .agent_id)" ] || exit 0
cmd=$(sed -z 's/\\\n/ /g' <<<"$(field .tool_input.command)" | tr -s '[:space:]' ' ') cwd=$(field .cwd)
# Project files load from the start dir, the repo root and, in a worktree, the main checkout; reading extra ones only skips more.
mapfile -t roots < <(git -C "$cwd" rev-parse --path-format=absolute --show-toplevel --git-common-dir 2>/dev/null)
files=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json")
for d in "${CLAUDE_PROJECT_DIR:-$cwd}" "$cwd" "${roots[@]%/.git}"; do files+=("$d/.claude/settings.json" "$d/.claude/settings.local.json"); done
guarded=("git diff" "git show" "git * diff" "git * show" "git * -p" "git * --patch" "gh * diff")
for f in "${files[@]}"; do
  [ -f "$f" ] && mapfile -t -O "${#guarded[@]}" guarded < <(jq -r '.permissions? | (.ask // [])[], (.deny // [])[]
    | select(startswith("Bash(")) | .[5:-1] | sub("(:| )\\*$"; "")' "$f" 2>/dev/null)
done
# A substring match is a superset of Claude Code's per-subcommand match, wrappers and chains included.
for g in "${guarded[@]}"; do [[ $cmd == *$g* ]] && exit 0; done
exec rtk hook claude <<<"$input"
