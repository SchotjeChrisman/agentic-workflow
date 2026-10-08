<div align="center">

# agentic-workflow

**A stack-agnostic Claude Code setup: global rules, five method-driven subagents, self-improving memory hooks and a rate-limit-aware status line.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20BSD-lightgrey)
![Shell](https://img.shields.io/badge/bash-3.2%2B-4EAA25?logo=gnubash&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude%20Code-config-D97757)

</div>

---

## Contents

- [What's inside](#whats-inside)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Customizing](#customizing)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [Development](#development)
- [License](#license)

## What's inside

```
agentic-workflow/
├── CLAUDE.md               global rules, loaded in every project
├── rules/
│   └── context7.md         check library APIs against current docs
├── agents/
│   ├── verifier.md         cold check of a finished change
│   ├── critic.md           stress-tests a plan before it's built
│   ├── auditor.md          checks docs or data against reality
│   ├── scraper.md          researches the web and docs on Haiku
│   └── debugger.md         root-causes and fixes a bug
├── hooks/
│   ├── learn.sh            memory caps, "worth keeping?" nudges, background review
│   ├── peers.sh            tells Claude about other live sessions in the repo
│   ├── rtk.sh              optional: compressed command output via rtk
│   └── test_*.sh           self-checks for each hook
├── statusline-command.sh   model, repo, context and rate-limit status line
└── settings.json           permissions, hooks, status line and plugins
```

Your `~/.claude` links to the files in this repo, so a `git pull` updates the rules, agents, hooks and status line at once.

## Features

### Global rules

`CLAUDE.md` holds working rules that apply in every project:

- **Ask first:** no commits, pushes, new dependencies or broad cleanups unless told.
- **Scope:** a plan or brainstorm means build nothing yet; numbered steps are the whole job.
- **Commits:** small conventional commits, with no AI attribution lines.
- **Verify before "done":** every non-trivial change gets a fresh verifier subagent, with severity-ranked findings and at most three rounds.
- **Models:** subagents and workflow stages get Haiku, Sonnet or the session's model by task, and web research goes to the scraper.
- **Output:** dense plain reports and multiple-choice decisions, with no preamble or emoji.

`rules/context7.md` makes Claude check third-party APIs against current docs through [Context7](https://context7.com) instead of relying on memory.

### Subagents

Five user-scope agents, each built around a method rather than a stack. Each keeps its own memory per project under `~/.claude/agent-memory/<agent>/`.

| Agent | Use it for | Model | Edits code? |
| --- | --- | --- | --- |
| **verifier** | An independent check of a finished change: re-runs the tests and makes sure nothing in the request was skipped | Sonnet | No |
| **critic** | Stress-testing a plan: false claims, failure modes, over- and under-built parts, test gaps | Session model | No |
| **auditor** | Checking a document, list or dataset against reality, item by item | Sonnet | No |
| **scraper** | Web and docs research: returns each fact as a verbatim quote with its URL, so the pages stay out of your context | Haiku | No |
| **debugger** | Finding the root cause of a bug or failing test, then fixing it with a regression check | Session model | Yes, never commits |

A hook guards the read-only agents: they can write only inside their own memory folder.

### Hooks

**`learn.sh`: memory that maintains itself**
- At session start it gives Claude `~/.claude/USER.md`, a short file of notes about you that carries across projects.
- It caps memory files: USER.md at 1,375 characters, each `MEMORY.md` index at 2,200 and each agent topic file at 12,000. A file over its cap gets consolidated rather than allowed to grow.
- After a turn with 15 or more tool calls, it asks Claude whether anything is worth keeping as a skill, a note about you, or project memory.
- After a session with 30 or more tool calls, it starts a background reviewer in a sandbox. The reviewer proposes edits, and only those that pass safety checks are copied back: no symlinks, nothing over its cap, nothing changed meanwhile, no skill gaining hooks.

**`peers.sh`: session awareness.** At startup it lists other live Claude Code sessions in the same directory or repository, so Claude messages them before editing shared files.

**`rtk.sh`: quieter output (optional).** When [rtk](https://github.com/rtk-ai/rtk) is installed, it routes the main session's Bash commands through rtk to compress their output. Diffs, subagent commands, and anything your `ask` or `deny` permission rules name are passed through untouched. Without rtk it does nothing. It assumes auto mode: rewritten read-only commands lose their built-in approval, so outside auto mode they prompt.

### Status line

```
~/projects/app · Opus 5.5 – xhigh
repo you/app · branch main · worktree fix-login
Context 23% (1M) · Session 41% (resets 14:30) · Week 12% (resets Mon 09:00)
```

The session and week percentages are colored by pace, not by a flat threshold:
- green while your usage trails the share of the window that has passed;
- yellow once it gets ahead of that share;
- red once it is 20 points ahead, or above 90%.

### Settings

`settings.json` wires up the hooks and the status line and turns on a few plugins:
- [ponytail](https://github.com/DietrichGebert/ponytail)
- context7
- claude-security
- plugin-dev

It also:
- sets auto mode as the default permission mode;
- denies destructive `docker`/`podman` prune commands;
- turns off commit and PR attribution;
- sets personal defaults: light theme, fullscreen TUI, xhigh effort on Opus 5.5, Remote Control at startup, push notifications, and worktrees branched from HEAD.

## Requirements

| | |
| --- | --- |
| **OS** | Linux, macOS or a BSD |
| **Claude Code** | the `claude` CLI |
| **Tools** | bash 3.2+, jq 1.7+, git, python3, awk, diff |
| **Optional** | [rtk](https://github.com/rtk-ai/rtk) for compressed output |

On macOS, the Xcode Command Line Tools provide git and python3, and macOS 15 and later ship jq 1.7.

## Installation

**1. Clone the repository**

```sh
git clone https://github.com/SchotjeChrisman/agentic-workflow.git ~/agentic-workflow
```

The commands below assume this path. If you clone elsewhere, change `~/agentic-workflow` in them.

**2. Link it into `~/.claude`**

This loop never overwrites anything that's already there:

```sh
mkdir -p ~/.claude && cd ~/.claude
for f in CLAUDE.md agents hooks rules statusline-command.sh; do
  if [ -e "$f" ] || [ -L "$f" ]; then echo "skipped, already exists: $f"; else ln -s "$HOME/agentic-workflow/$f" "$f"; fi
done
```

If something is skipped, keep your own version and combine the two by hand:
- For `CLAUDE.md`, add the line `@~/agentic-workflow/CLAUDE.md` to your file.
- For a folder such as `agents/`, link the repo's files into it one at a time.

**3. Merge the settings**

`settings.json` is merged into yours, never copied over it:
- your plugins, marketplaces, permission rules and hooks stay, and the repo's are added;
- where both files set the same value (`theme`, say), yours wins;
- if anything fails, your file is left untouched.

```sh
mkdir -p ~/.claude && cd ~/.claude
[ -f settings.json ] || echo '{}' > settings.json
[ -f settings.json.bak ] || cp settings.json settings.json.bak
jq -s 'def m($a; $b):
    if ($a|type) == "object" and ($b|type) == "object" then reduce ($b|keys_unsorted[]) as $k ($a; .[$k] = m($a[$k]; $b[$k]))
    elif ($a|type) == "array" and ($b|type) == "array" then $a + ($b - $a)
    else $b end;
  m(.[1]; .[0])' settings.json ~/agentic-workflow/settings.json > settings.json.new || rm -f settings.json.new
diff <(jq -S . settings.json) <(jq -S . settings.json.new)
mv settings.json.new settings.json
```

The diff shows what the merge changed. The first run saves your original settings as `settings.json.bak`. Running the step again adds nothing twice.

**4. Install the plugins**

```sh
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add DietrichGebert/ponytail
claude plugin install ponytail@ponytail
claude plugin install context7@claude-plugins-official
claude plugin install claude-security@claude-plugins-official
claude plugin install plugin-dev@claude-plugins-official
```

**5. Check it**

```sh
cd ~/agentic-workflow && bash hooks/test_learn.sh && bash hooks/test_peers.sh && bash hooks/test_rtk.sh
```

Each test prints `PASS` (`test_rtk.sh` prints `SKIP` without rtk). Then start `claude`:
- the status line appears at the bottom;
- `/agents` lists verifier, critic, auditor, scraper and debugger;
- `/hooks` shows the hooks.

## Customizing

- **Rules:** `CLAUDE.md` is written in the first person as the author's own rules. Read it, then edit what doesn't fit how you work. Note that your edits land in your clone.
- **Time zone:** the status line pins reset times to `Europe/Amsterdam`. Change the `TZ` line at the top of `statusline-command.sh`.
- **Caps and thresholds:** these are the constants at the top of `hooks/learn.sh` (`USER_CAP`, `MEMORY_CAP`, `NUDGE_AFTER`, `REVIEW_AFTER`, `REVIEW_MODEL`).
- **Settings:** change values in `~/.claude/settings.json`; rerunning step 3 keeps them. A key you delete there comes back on the next merge, and so does the original of a list entry you edit (a hook, a permission rule). Make those changes in `~/agentic-workflow/settings.json` too.
- **Auto mode:** if your plan or organization doesn't offer auto mode, change `permissions.defaultMode`.
- **Attribution:** commit and PR attribution is off. If your workplace requires AI disclosure, remove the `attribution` block, both from your settings and from the clone's, and the matching commit rules from `CLAUDE.md`.

## Updating

```sh
cd ~/agentic-workflow && git pull
```

Rules, agents, hooks and the status line update through the links. When `settings.json` changes, run step 3 again. It adds new entries, but it never removes old ones: if the repo changes or drops a hook or permission rule, the old entry stays next to the new one. Delete it by hand; the diff in step 3 shows both.

## Uninstalling

```sh
cd ~/.claude
for f in CLAUDE.md agents hooks rules statusline-command.sh; do
  [ "$(readlink "$f")" = "$HOME/agentic-workflow/$f" ] && rm "$f"
done
mv settings.json.bak settings.json
```

This removes only the links that point into the clone, then restores your settings from before the first install. Settings changes made since then are lost.

The hooks keep their data in:
- `~/.claude/USER.md`
- `~/.claude/learn/`
- `~/.claude/agent-memory/`

Delete those too if you want a clean slate. If you combined files by hand in step 2, also remove the `@~/agentic-workflow/CLAUDE.md` line and the per-file links you made.

## Development

The tests run in a temporary sandbox and never touch your live config:

```sh
bash hooks/test_learn.sh
bash hooks/test_peers.sh
bash hooks/test_rtk.sh
```

`test_learn.sh` takes about 6 seconds because it waits on detached reviewers. `test_rtk.sh` prints `SKIP` without rtk.

The scripts must keep working on Linux, macOS and the BSDs, so:
- stick to bash 3.2 (no `mapfile`, no `${x,,}`);
- use only flags that GNU and BSD tools share;
- where they differ, try one form and fall back to the other.

`.gitignore` denies everything by default. A new file gets published only once it has a `!` line there.

## License

[MIT](LICENSE)
