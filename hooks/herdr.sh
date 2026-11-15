#!/usr/bin/env bash
# Optional herdr integration (herdr.dev, the TUI and the desktop app). Inside herdr, work that would go to a
# background agent runs as a full `claude` session in a tab of the caller's own space instead; the tab is opened,
# awaited and closed the way a background agent's lifecycle goes.
#
# Hook events (dispatched on hook_event_name): SessionStart explains the tabs to Claude, SessionEnd closes the
# ones still open. Subcommands Claude calls through Bash: run, send, close.
#
# Only tabs this script opened are ever closed: each one is written to a per-caller ledger, and `close` trusts
# nothing else. Tabs the user made are not in it, so they are left alone.
state_dir=${HERDR_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/herdr}
self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
name_pattern='^[a-z][a-z0-9_-]{0,31}$'
wait_seconds=86400

fail() { echo "herdr.sh: $*" >&2; exit 1; }

# --- where we are -------------------------------------------------------------------------------------------

# Prints tui, desktop, or nothing. The desktop app shows only terminals labeled with a space, so a caller
# without one counts as outside herdr.
detect_backend() {
  command -v jq >/dev/null || return 0
  if [ "${HERDR_ENV:-}" = 1 ] && command -v herdr >/dev/null; then echo tui; return; fi
  if [ -n "${HC_TERMINAL_ID:-}" ] && command -v hc >/dev/null && [ -n "$(desktop_space)" ]; then echo desktop; fi
}

desktop_space() { hc get "$HC_TERMINAL_ID" --json 2>/dev/null | jq -r '.labels["herdr.space"] // empty'; }

backend=$(detect_backend)
caller=${HERDR_PANE_ID:-${HC_TERMINAL_ID:-}}
caller_key=${caller//[!A-Za-z0-9_-]/_}

# --- ledger: one "name<TAB>ref" line per tab this caller opened ---------------------------------------------

ledger_file() { echo "$state_dir/$caller_key.tabs"; }
ledger_ref() { awk -F'\t' -v name="$1" '$1 == name { print $2; exit }' "$(ledger_file)" 2>/dev/null; }
ledger_add() { mkdir -p "$state_dir" && printf '%s\t%s\n' "$1" "$2" >>"$(ledger_file)"; }
ledger_drop() {
  local file; file=$(ledger_file)
  awk -F'\t' -v name="$1" '$1 != name' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
}

# --- TUI backend (herdr CLI over the session socket) --------------------------------------------------------

tui_open() {
  local name=$1 cwd=$2 prompt=$3 created tab pane; shift 3
  created=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$cwd" --label "$name" \
    --env CLAUDE_HERDR_CHILD=1 --no-focus) || fail "tab create failed"
  tab=$(jq -r .result.tab.tab_id <<<"$created")
  pane=$(jq -r .result.root_pane.pane_id <<<"$created")
  ledger_add "$name" "$tab" || fail "cannot write the ledger"
  herdr agent start "$name" --kind claude --pane "$pane" ${1:+-- "$@"} || fail "agent start failed"
  tui_send "$name" "$prompt"
}
tui_send() { herdr agent prompt "$1" "$2" --wait; }
tui_status() { herdr agent get "$1"; }
# A tab the user already closed counts as closed, so its ledger line does not linger.
tui_close() { herdr tab get "$1" >/dev/null 2>&1 || return 0; herdr tab close "$1"; }

# --- desktop backend (hc, herdr-core; the app turns a terminal labeled with a space into a tab) -------------

desktop_open() {
  local name=$1 cwd=$2 prompt=$3 claude_path; shift 3
  # hc terminals start with the core's PATH, which may lack the directory claude lives in.
  claude_path=$(command -v claude) || fail "claude is not on PATH"
  hc run --bg --no-notify --name "$name" --cwd "$cwd" --label "herdr.space=$(desktop_space)" \
    env CLAUDE_HERDR_CHILD=1 "$claude_path" "$@" "$prompt" >/dev/null || fail "hc run failed"
  ledger_add "$name" "$name" || fail "cannot write the ledger"
  hc wait "$name" --timeout "$wait_seconds"
}
desktop_send() { hc send --wait --timeout "$wait_seconds" "$1" "$2"; }
desktop_status() { hc get "$1" --json; }
desktop_close() {
  local state; state=$(hc get "$1" --json 2>/dev/null | jq -r '.state // empty')
  [ -n "$state" ] || return 0
  if [ "$state" = live ]; then hc kill "$1" || return; fi
  hc rm "$1"
}

# --- subcommands --------------------------------------------------------------------------------------------

require_backend() { [ -n "$backend" ] || fail "not inside herdr (or herdr and jq are not installed)"; }
require_name() { [[ $1 =~ $name_pattern ]] || fail "name must match $name_pattern"; }

cmd_run() {
  local agent_args=()
  if [ "${1:-}" = --agent ]; then agent_args=(--agent "${2:?--agent needs a type}"); shift 2; fi
  [ $# -eq 3 ] || fail "usage: run [--agent TYPE] <name> <cwd> <task>"
  local name=$1 cwd=$2 task=$3 report
  require_backend; require_name "$name"
  [ -z "$(ledger_ref "$name")" ] || fail "$name is already open; use send or close"
  report=$state_dir/$caller_key/$name.md
  mkdir -p "$(dirname "$report")"
  "${backend}_open" "$name" "$cwd" \
    "$task"$'\n\n'"When finished, write your full report to $report and reply with only that path." \
    ${agent_args[@]+"${agent_args[@]}"}
  "${backend}_status" "$name"
  echo "report: $report"
}

cmd_send() {
  [ $# -eq 2 ] || fail "usage: send <name> <text>"
  require_backend
  [ -n "$(ledger_ref "$1")" ] || fail "$1 was not opened by this session"
  "${backend}_send" "$1" "$2"
  "${backend}_status" "$1"
}

cmd_close() {
  [ $# -eq 1 ] || fail "usage: close <name>"
  require_backend
  local ref; ref=$(ledger_ref "$1")
  [ -n "$ref" ] || fail "$1 was not opened by this session; leaving it alone"
  "${backend}_close" "$ref" && ledger_drop "$1"
}

# --- hook events --------------------------------------------------------------------------------------------

on_session_start() {
  [ -n "$backend" ] && [ -z "${CLAUDE_HERDR_CHILD:-}" ] || return 0
  cat <<EOF
This session runs inside herdr. Run work you would hand to a background agent as a herdr tab instead: start
\`bash $self run [--agent TYPE] <name> <cwd> "<task>"\` with run_in_background (name: lowercase letters, digits, - or _,
at most 32). It opens a full claude session in a tab, waits for its turn, and prints the child's state and the path
of its report; read that file once notified. \`send <name> "<text>"\` gives the tab another turn. Close the tab with
\`close <name>\` when you are done with it; open tabs are also closed when this session ends. Foreground work
(verifier, critic) stays an ordinary subagent. If a tab is blocked, read its screen and ask the user. Never close,
touch or reuse a tab you did not open: the user's own tabs are not yours. Tab sessions do not open tabs themselves.
EOF
  [ -s "$(ledger_file)" ] && printf 'Tabs this pane already opened: %s\n' "$(cut -f1 "$(ledger_file)" | paste -sd' ' -)"
  return 0
}

on_session_end() {
  local reason=$1 name ref
  [ -n "$backend" ] && [ -s "$(ledger_file)" ] || return 0
  [ "$reason" != clear ] || return 0
  while IFS=$'\t' read -r name ref; do
    "${backend}_close" "$ref" >&2
  done <"$(ledger_file)"
  rm -f "$(ledger_file)"
}

on_hook() {
  local input event reason
  input=$(cat)
  event=$(jq -r '.hook_event_name // empty' <<<"$input")
  reason=$(jq -r '.reason // empty' <<<"$input")
  case $event in
    SessionStart) on_session_start ;;
    SessionEnd) on_session_end "$reason" ;;
  esac
}

case ${1:-} in
  run) shift; cmd_run "$@" ;;
  send) shift; cmd_send "$@" ;;
  close) shift; cmd_close "$@" ;;
  "") on_hook ;;
  *) fail "unknown subcommand $1 (run, send, close)" ;;
esac
