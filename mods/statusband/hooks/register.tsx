import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, SessionContextUsage, SessionCost, SessionRateLimit } from 'claude-code'

import type { Git, Model, Usage } from '../types'
import {
  ICON,
  LABEL,
  basename,
  contextTone,
  isPast,
  modelName,
  paceTone,
  repoName,
  resetLabel,
  tildify,
  windowSize,
} from './format'

const usage = atom({ plugin: 'statusband', key: 'usage' } as const, null)
const git = atom({ plugin: 'statusband', key: 'git' } as const, null)
const model = atom({ plugin: 'statusband', key: 'model' } as const, null)
const now = atom({ plugin: 'statusband', key: 'now' } as const, 0)

const GIT_TOOLS = new Set(['Bash', 'EnterWorktree', 'ExitWorktree'])
const MODEL_COMMANDS = new Set(['model', 'effort', 'config'])
const EFFORTS = new Set(['low', 'medium', 'high', 'xhigh', 'max'])

function toUsage(m: { context: SessionContextUsage; rateLimits: SessionRateLimit[]; cost?: SessionCost }): Usage {
  return {
    tokens: m.context.tokens,
    window: m.context.window,
    percent: m.context.percent,
    limits: m.rateLimits.map(({ kind, percentUsed, resetsAt }) => ({ kind, percentUsed, resetsAt })),
    costUsd: m.cost?.usd,
  }
}

async function readGit($: EngineInterface): Promise<Git> {
  const cwd = await $.session.cwd()
  const run = (...args: string[]) =>
    $.process
      .run(['git', '--no-optional-locks', ...args], { cwd, timeoutMs: 5000 })
      .then(r => (r.exitCode === 0 ? r.stdout.trim() : ''), () => '')
  // ponytail: --show-toplevel fails in a bare repo, so it runs on its own
  const [dirs, top, branch, sha, remote] = await Promise.all([
    run('rev-parse', '--path-format=absolute', '--git-dir', '--git-common-dir'),
    run('rev-parse', '--show-toplevel'),
    run('branch', '--show-current'),
    run('rev-parse', '--short', 'HEAD'),
    run('remote', 'get-url', 'origin'),
  ])
  if (!dirs) return { cwd }
  const [gitDir = '', common = ''] = dirs.split('\n')
  return {
    cwd,
    repo: repoName(remote, common),
    branch: branch || (sha ? `@${sha}` : undefined),
    worktree: gitDir !== common && top ? basename(top) : undefined,
  }
}

async function refreshGit($: EngineInterface) {
  const next = await readGit($)
  await update($, git, () => next)
}

async function refreshUsage($: EngineInterface) {
  const u = await $.session.usage()
  await update($, usage, () => toUsage(u))
}

async function refreshModel($: EngineInterface, effort?: string, id?: string) {
  const name = modelName(id ?? (await $.session.model()))
  await update($, model, m => ({ name, effort: effort ?? m?.effort }))
}

const quiet = () => {}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    await Promise.all([refreshUsage($).catch(quiet), refreshModel($).catch(quiet), refreshGit($).catch(quiet)])
    await update($, now, () => Date.now())
    // ponytail: minute tick only re-colors pace and nothing else; drop it if pace coloring goes
    $.clock.every(60_000, () => void update($, now, () => Date.now()))
    return result
  })

  // /clear fires no session.start; the old window's figures must go
  on('session.end', async ($, e, next) => {
    const result = await next(e)
    if (e.reason === 'clear') await refreshUsage($).catch(quiet)
    return result
  })

  on('command.run', async ($, e, next) => {
    const result = await next(e)
    if (MODEL_COMMANDS.has(e.command)) {
      const level = e.args.trim().toLowerCase()
      await refreshModel($, e.command === 'effort' && EFFORTS.has(level) ? level : undefined).catch(quiet)
    }
    return result
  }).catch(($, e, next) => next(e))

  // the model picker runs no command.run with the choice; the switch itself is a classic event
  on('classic.PostModelSwitch', async ($, e, next) => {
    if (e.agent_id === undefined) await refreshModel($, undefined, e.to_model).catch(quiet)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.measure', async ($, e, next) => {
    await update($, usage, () => toUsage(e))
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    if (e.agentId === undefined) {
      const fresh: Model = { name: modelName(e.model), effort: e.effort === undefined ? undefined : String(e.effort) }
      const cur = await read($, model)
      if (cur?.name !== fresh.name || cur?.effort !== fresh.effort) await update($, model, () => fresh)
    }
    return yield* next(e)
  })

  on('tool.call', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined && GIT_TOOLS.has(String(e.tool))) await refreshGit($).catch(quiet)
    return result
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined) await refreshGit($).catch(quiet)
    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const [u, g, m, t, home] = await Promise.all([read($, usage), read($, git), read($, model), read($, now), $.env.get('HOME')])
    if (!u && !g && !m) return next(e)

    const { Box, Text } = $.ui.resolve(e)
    const sep = <Text dimColor>{'  ·  '}</Text>
    const clock = t || Date.now()
    const field = (icon: string, label: string) => <Text dimColor>{icon} {label} </Text>

    const ctx =
      u?.percent === undefined ? (
        <Text>
          {field(ICON.context, 'Context')}
          <Text dimColor>n/a</Text>
        </Text>
      ) : (
        <Text>
          {field(ICON.context, 'Context')}
          <Text color={contextTone(u.percent)}>{u.percent}%</Text>
          <Text dimColor> of {windowSize(u.window)}</Text>
        </Text>
      )

    const limits = u?.limits.length ? (
      u.limits.map(l => (
        <Text key={l.kind}>
          {sep}
          {field(ICON[l.kind as keyof typeof ICON] ?? ICON.limit, LABEL[l.kind] ?? l.kind)}
          {isPast(l.resetsAt, clock) ? (
            <Text dimColor>reset, awaiting next reading</Text>
          ) : (
            <Text>
              <Text color={paceTone(l.percentUsed, l.kind, l.resetsAt, clock)}>{Math.round(l.percentUsed)}%</Text>
              {l.resetsAt ? <Text dimColor> resets {resetLabel(l.resetsAt, l.kind)}</Text> : null}
            </Text>
          )}
        </Text>
      ))
    ) : (
      <Text>
        {sep}
        {field(ICON.limit, 'Limits')}
        <Text dimColor>n/a</Text>
      </Text>
    )

    return (
      <Box flexDirection="column">
        <Text wrap="truncate-start">
          {field(ICON.folder, 'Directory')}
          <Text>{g ? tildify(g.cwd, home) : 'n/a'}</Text>
          {m ? (
            <Text>
              {sep}
              {field(ICON.model, 'Model')}
              <Text bold>{m.name}</Text>
              {m.effort ? (
                <Text>
                  {sep}
                  {field(ICON.effort, 'Effort')}
                  <Text>{m.effort}</Text>
                </Text>
              ) : null}
            </Text>
          ) : null}
        </Text>
        <Text wrap="truncate-end">
          {field(ICON.repo, 'Repository')}
          {g?.repo ? <Text bold color="claude">{g.repo}</Text> : <Text dimColor>none</Text>}
          {g?.branch ? (
            <Text>
              {sep}
              {field(ICON.branch, 'Branch')}
              <Text color="suggestion">{g.branch}</Text>
            </Text>
          ) : null}
          {g?.worktree ? (
            <Text>
              {sep}
              {field(ICON.worktree, 'Worktree')}
              <Text>{g.worktree}</Text>
            </Text>
          ) : null}
        </Text>
        <Text wrap="wrap">
          {ctx}
          {limits}
          {u?.costUsd !== undefined ? (
            <Text>
              {sep}
              {field(ICON.cost, 'Cost')}
              <Text>${u.costUsd.toFixed(2)}</Text>
            </Text>
          ) : null}
        </Text>
      </Box>
    )
  })
}
