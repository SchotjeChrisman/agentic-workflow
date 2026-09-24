#!/bin/bash
LC_NUMERIC=C
export TZ=Europe/Amsterdam  # ponytail: pin reset times to local time
input=$(cat)
# ponytail: uncomment to capture one real payload for debugging
# echo "$input" > "$HOME/.claude/statusline-input-debug.json"

RESET=$'\033[0m'
GREEN=$'\033[1;92m'
YELLOW=$'\033[1;93m'
RED=$'\033[1;91m'
DIM=$'\033[2m'
BOLD=$'\033[1m'

# color a "N%" value by threshold (low=green, mid=yellow, high=red)
color_pct() {
  pct=$1
  [ -z "$pct" ] && return
  pct_int=$(printf '%.0f' "$pct")
  if [ "$pct_int" -ge 80 ]; then c=$RED
  elif [ "$pct_int" -ge 50 ]; then c=$YELLOW
  else c=$GREEN
  fi
  printf "%b%s%%%b" "$c" "$pct_int" "$RESET"
}

# color a rate-limit "N%" value against pace-to-reset (used vs. expected-at-this-point-in-window),
# not a flat threshold — 50% used with most of the window still open is fine, not a warning.
color_rate_pct() {
  pct=$1; resets_at=$2; window=$3
  [ -z "$pct" ] && return
  pct_int=$(printf '%.0f' "$pct")
  if [ -z "$resets_at" ]; then
    color_pct "$pct"; return
  fi
  now=$(date +%s)
  color=$(awk -v pct="$pct" -v resets="$resets_at" -v now="$now" -v window="$window" 'BEGIN{
    remaining = resets - now
    if (remaining < 0) remaining = 0
    elapsed = window - remaining
    if (elapsed < 0) elapsed = 0
    expected = (elapsed / window) * 100
    diff = pct - expected
    if (pct >= 90) print "red"
    else if (diff >= 20) print "red"
    else if (diff >= 0) print "yellow"
    else print "green"
  }')
  case "$color" in
    red) c=$RED ;;
    yellow) c=$YELLOW ;;
    *) c=$GREEN ;;
  esac
  printf "%b%s%%%b" "$c" "$pct_int" "$RESET"
}

eval "$(printf '%s' "$input" | python3 -c '
import json, shlex, sys
d = json.load(sys.stdin)
def dig(*ks):
    v = d
    for k in ks:
        v = v.get(k) if isinstance(v, dict) else None
    return "" if v is None else str(v)
for name, val in [
    ("cwd", dig("workspace", "current_dir")),
    ("repo", dig("workspace", "repo", "name")),
    ("repo_owner", dig("workspace", "repo", "owner")),
    ("worktree", dig("worktree", "name")),
    ("model", dig("model", "display_name")),
    ("effort", dig("effort", "level")),
    ("ctx_used", dig("context_window", "used_percentage")),
    ("ctx_size", dig("context_window", "context_window_size")),
    ("five", dig("rate_limits", "five_hour", "used_percentage")),
    ("five_reset", dig("rate_limits", "five_hour", "resets_at")),
    ("week", dig("rate_limits", "seven_day", "used_percentage")),
    ("week_reset", dig("rate_limits", "seven_day", "resets_at")),
]:
    print(f"{name}={shlex.quote(val)}")
')"

# git fallbacks: repo name from the main repo dir (not the worktree dir),
# worktree name only when cwd is in a linked worktree
# ponytail: --show-toplevel fails in a bare repo, so it stays out of this call
if info=$(cd "$cwd" 2>/dev/null && git --no-optional-locks rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null); then
  { read -r gitdir; read -r common; } <<<"$info"
  [ -z "$repo" ] && repo=$(basename "$(dirname "$common")")
  if [ -z "$worktree" ] && [ "$gitdir" != "$common" ]; then
    toplevel=$(cd "$cwd" 2>/dev/null && git --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
    [ -n "$toplevel" ] && worktree=$(basename "$toplevel")
  fi
  branch=$(cd "$cwd" 2>/dev/null && git --no-optional-locks branch --show-current 2>/dev/null)
  # owner/name fallback via origin remote (json only gives us this on GitHub-recognized remotes)
  if [ -z "$repo_owner" ] && remote_url=$(cd "$cwd" 2>/dev/null && git --no-optional-locks remote get-url origin 2>/dev/null); then
    owner_name=$(printf '%s' "$remote_url" | sed -E 's#\.git/?$##; s#.*[:/]([^/]+)/([^/]+)$#\1/\2#')
    case "$owner_name" in
      */*) repo_owner="${owner_name%/*}"; repo="${owner_name##*/}" ;;
    esac
  fi
fi

repo_full="${repo:-none}"
[ -n "$repo_owner" ] && [ -n "$repo" ] && repo_full="$repo_owner/$repo"

repo_part="${DIM}repo${RESET} ${BOLD}${repo_full}${RESET}"
[ -n "$branch" ] && repo_part="$repo_part · ${DIM}branch${RESET} ${BOLD}${branch}${RESET}"
[ -n "$worktree" ] && repo_part="$repo_part · ${DIM}worktree${RESET} ${BOLD}${worktree}${RESET}"

# ponytail: $HOME must be quoted — bash 5.3 treats its slashes as pattern/replacement separators
loc="${cwd/#"$HOME"/\~}"
loc_part="${DIM}${loc}${RESET}"

model_part="${loc_part} · ${BOLD}${model}${RESET}"
[ -n "$effort" ] && model_part="$model_part – $effort"

ctx_label=""
if [ -n "$ctx_size" ]; then
  if [ "$ctx_size" -ge 1000000 ]; then ctx_label=" ($((ctx_size / 1000000))M)"; else ctx_label=" ($((ctx_size / 1000))K)"; fi
fi
# ponytail: BSD date is `-r <epoch>`, GNU is `-d @<epoch>` — try BSD, fall back to GNU
fmt_epoch() { date -r "$1" +"$2" 2>/dev/null || date -d "@$1" +"$2"; }
five_label=""; week_label=""
[ -n "$five_reset" ] && five_label=" (resets $(fmt_epoch "${five_reset%.*}" %H:%M))"
[ -n "$week_reset" ] && week_label=" (resets $(fmt_epoch "${week_reset%.*}" "%a %H:%M"))"

ctx_part="Context $(color_pct "$ctx_used")$ctx_label"; [ -z "$ctx_used" ] && ctx_part="Context n/a"
session_part="Session $(color_rate_pct "$five" "$five_reset" 18000)$five_label"; [ -z "$five" ] && session_part="Session n/a"
week_part="Week $(color_rate_pct "$week" "$week_reset" 604800)$week_label"; [ -z "$week" ] && week_part="Week n/a"

printf "%s\n%s\n%s · %s · %s\n" "$model_part" "$repo_part" "$ctx_part" "$session_part" "$week_part"
