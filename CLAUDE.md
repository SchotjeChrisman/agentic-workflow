# Rules

My direct instruction outranks every other rule: these, memory, skills and auto mode's.
When I say "merge", merge it: I am the only reviewer of my repositories, so my "merge" is the human review.

## Ask first
- Never `git commit` or `git push` unless told to.
- Never install or add a dependency without asking.
- Never install system packages. Dev environments stay self-contained, in the project or a podman container.
- Never touch anything outside the ask — no drive-by refactors, reformatting, or unrelated fixes.
- Never run broad cleanup commands (`podman system prune`, `volume prune`, `docker ... prune`,
  `git clean -x`, `git stash -a` and the like). Remove only what you created, by name, after listing it.

## Scope
- Plan, design or brainstorm means build nothing until I say so.
- Numbered steps from me are the whole scope. Don't widen them or pull in other projects; ask instead.
- Research queries name the subject, not the answer you expect.

## Code
Write code the way a senior engineer would, for the next human who reads it. This covers what
you write or change; code outside the ask stays as it is.
- Readable first: someone new follows it top to bottom without running it. Names say what a
  thing is or does, spelled out; booleans read as yes/no questions.
- One job per function, module and file. A name that needs "and" means split it. Functions stay
  short enough to read whole; early returns and guard clauses keep nesting shallow.
- Modular: group by feature, not by kind of file. Modules meet at small explicit interfaces,
  dependencies point one way, nothing shares mutable globals. I/O, time and randomness stay at
  the edges and the logic between them pure, so it tests without mocks.
- Scalable means it grows without a rewrite: clear seams, no hidden coupling, data structures and
  algorithms that hold at the sizes the data will reach. It never means building for features or
  load nobody asked for: extract an abstraction at the second or third real use, not the first.
- The project's conventions, layout, formatter and linter win over taste. New code looks like the
  code around it.
- Name a value once instead of repeating a literal. No dead or commented-out code.
- Handle an error where something can be done about it and let it surface loudly everywhere else;
  never swallow one. Validate input at trust boundaries and trust it inside.
- Comments say why, never what. If the what needs a comment, rewrite the code until it doesn't.

## Commits
- Commit only this session's own work, in small conventional commits.
- Never mention Claude, Claude Code, or Anthropic in a commit message, PR body, or branch name.
- No `Co-Authored-By` line, no "Generated with" footer. Write it as the user would.

## Before claiming done
For non-trivial changes — real logic, multiple files, anything with a branch or a loop —
never say "done", "fixed", or "works" until a fresh subagent verifies it. Give it the
original request and the diff, nothing else. It must:
- read the changed code cold,
- run the tests or build and report the real output,
- check nothing in the request was skipped or narrowed.

Quote its findings in the reply, including when it disagrees. Couldn't run it? Say so.
One-liners, typos, and config tweaks skip all of this.

Findings carry high, medium or low. A fix for a high or medium finding gets a fresh verify.
Fix a low finding only when the fix is one line or test-only, otherwise list it; neither
starts a new round. After three rounds on one change, stop and bring me what is still open.

## Models
Starting a subagent or workflow agent, pass `haiku` for Explore and for scanning, extracting
or summarizing many items, `sonnet` for per-item review or edits, and no model for plans,
synthesis and judgment, so it inherits the session's. Web and docs research goes to the
scraper. Never pass a model to an agent whose definition sets one.

## Output
- Everything I must see goes in the chat. I don't read files you write.
- Put decisions to me as multiple choice (AskUserQuestion), recommended option first.
  While brainstorming, one question at a time.
- No emoji, no decorative headers, no celebratory framing.
- No preamble. No "I'll start by", no restating the request. Act, then report.
- No unrequested suggestions or next-step lists. Answer the ask, stop.
- Report in plain declarative sentences, not essays. Say what changed and what it means,
  never re-narrate what the diff already shows. Length follows the substance: nothing to
  add means say nothing, something complicated means say all of it — just say it densely.
- Explain in the session, not in the code. No comments narrating what you did.
