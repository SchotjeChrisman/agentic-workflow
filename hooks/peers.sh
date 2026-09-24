#!/usr/bin/env bash
# SessionStart hook: tell Claude which other live Claude sessions are working near it.
input=$(cat)
me=$(jq -r .session_id <<<"$input")
my_cwd=$(jq -r .cwd <<<"$input")
registry=${CLAUDE_SESSIONS_DIR:-$HOME/.claude/sessions}

# Peers are relevant only in the same directory or the same git repo (subdirs and worktrees included).
repo() { git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }
my_repo=$(repo "$my_cwd")
relevant() {
  [ "$1" = "$my_cwd" ] || { [ -n "$my_repo" ] && [ "$(repo "$1")" = "$my_repo" ]; }
}

peers=$(for f in "$registry"/*.json; do
    jq -r --arg me "$me" 'select(.sessionId != $me) | [.pid, .name, .cwd, .status] | @tsv' "$f" 2>/dev/null
  done | while IFS=$'\t' read -r pid name cwd status; do
    kill -0 "$pid" 2>/dev/null && relevant "$cwd" && echo "- $name ($status) in $cwd"
  done)

if [ -n "$peers" ]; then
  cat <<EOF
Other Claude sessions are working in this same directory/repo:
$peers
Before editing files a peer may also be touching, tell it what you're about to change with SendMessage (to: its name). Once you know what this session is working on, send each of them a one-line note saying so.
EOF
fi
