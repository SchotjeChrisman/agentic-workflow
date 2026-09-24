# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repo is the published half of the user's Claude Code config. `~/.claude/{CLAUDE.md,agents,hooks,rules,statusline-command.sh}` are symlinks into it, so every edit here is live on this machine: hooks and the statusline on their next run, instructions and agents in the next session.

## Files that aren't what they look like
- The root `CLAUDE.md` is the user's global rules (`~/.claude/CLAUDE.md`), loaded in every project. Guidance about this repo goes in this file, never there. `rules/*.md` likewise load as user rules everywhere.
- `settings.json` is not linked: Claude Code replaces `~/.claude/settings.json` on write, and the live file holds a private `autoMode` block. The repo copy is an allowlisted export; refresh it and check it with:
  ```
  jq '{permissions, worktree, statusLine, enabledPlugins, extraKnownMarketplaces, modelSettings, attribution, hooks, tui, theme, skipWorkflowUsageWarning, preferredNotifChannel, remoteControlAtStartup, inputNeededNotifEnabled, agentPushNotifEnabled} | with_entries(select(.value != null))' ~/.claude/settings.json > settings.json
  jq -e 'has("autoMode") | not' settings.json
  ```
  Never add `autoMode` to the allowlist. A hook added only to the repo's `settings.json` doesn't run until it is merged into `~/.claude/settings.json`.
- `.gitignore` is deny-by-default: a new file outside the `agents/*.md`, `hooks/*.sh` and `rules/*.md` globs stays unpublished until it gets a `!` line there.

## Tests
No build or lint step. The tests:
```
bash hooks/test_learn.sh    # ~6s, waits on detached reviewers
bash hooks/test_peers.sh
bash hooks/test_rtk.sh      # prints SKIP without rtk
```
Each prints `PASS` or exits at the first `FAIL: <reason>`; there is no per-case selection. They sandbox themselves in a mktemp dir (`CLAUDE_CONFIG_DIR`, `CLAUDE_SESSIONS_DIR`, and a stub `claude` on `PATH` that records the reviewer's args and stdin), so they never touch the live config. `test_learn.sh` pulls the guard command out of `agents/verifier.md` with sed, so keep that frontmatter `command: '...'` on one line.

The statusline reads Claude Code's statusLine JSON on stdin: `echo '{"model":{"display_name":"M"},"workspace":{"current_dir":"'$PWD'"}}' | bash statusline-command.sh`.

Runtime deps: bash, jq, git, awk, diffutils, GNU coreutils (`realpath -m`), util-linux (`setsid`, `flock`), python3 (statusline), the `claude` CLI (reviewer), and optionally rtk (`rtk.sh` does nothing without it).

## hooks/learn.sh
One script behind four hook events in `settings.json`, dispatched on `hook_event_name`, plus two subcommands:
- SessionStart injects `~/.claude/USER.md`. PostToolUse on Write|Edit blocks with a "consolidate" reason once USER.md or a MEMORY.md (project auto memory or agent memory) passes its char cap; the write has already landed. Stop nudges "anything worth keeping?" after long turns, never in headless (`sdk-*` entrypoint) runs or plan mode. Caps and thresholds are the constants at the top.
- SessionEnd, after enough tool calls since the last review, digests the transcript and starts `learn.sh review` detached with `setsid -f`. The review stages copies of USER.md, the project's memory dir (keyed by git common dir) and the user's own skills in a temp dir, lets a restricted headless `claude -p` edit them there, and `apply` copies back only what passes (no symlinks, no `skills/synced/`, nothing changed live meanwhile, nothing over cap, no skill gaining `hooks` or `allowed-tools`). Per-session offsets and `learn.log` live in `~/.claude/learn/`.
- `learn.sh guard` is not in `settings.json`: it is the PreToolUse hook in the frontmatter of the read-only agents (verifier, critic, auditor), allowing Write/Edit only inside the agent's own memory dir and exiting 2 otherwise. The frontmatter's `|| exit 2` makes a missing script deny too.
- `LEARN_HOME` moves the script's data (USER.md, memory, skills, `learn/`) to a sandbox for trial runs.

`hooks/peers.sh` (SessionStart) lists other live sessions from `~/.claude/sessions/*.json` in the same directory or git repo, and tells Claude to message them before editing shared files.

`hooks/rtk.sh` (PreToolUse on Bash, main session only) hands commands to rtk so their output arrives compressed. Claude Code checks permission rules against the rewritten command, so anything matching a `Bash(...)` ask or deny rule in the user, project or local settings, plus `git diff` and `git show`, passes through untouched. A new ask or deny rule exempts its commands automatically. Subagents get raw output.

## agents/
Four user-scope agents built around a method, not a stack. They share one section layout (Orient, Method, Evidence, Running things, Memory, Report), keep `memory: user` under `~/.claude/agent-memory/<agent>/` with one MEMORY.md line per project titled by absolute path, and cap their report length. Only debugger edits. Because they are live, a trial `claude -p` run that keeps the real config dir (a `LEARN_HOME` sandbox, for one) and uses an agent writes into the real agent memory: afterwards remove that topic file, its MEMORY.md line and the sandbox transcript dirs.
