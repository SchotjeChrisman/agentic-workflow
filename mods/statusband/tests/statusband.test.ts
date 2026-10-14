import { expect, mock, test } from 'claude-code/testing'

import { modelName, paceTone, repoName, resetLabel } from '../hooks/format'

const BAND = {
  plugin: 'statusband',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 120, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

test('band draws context, limits and cost from session.measure', async ($, on) => {
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  mock.env(on, { HOME: '/Users/x' })
  const resetsAt = new Date(Date.now() + 4 * 3600_000).toISOString()
  await $.session.measure({
    context: { tokens: 420_000, window: 1_000_000, percent: 42 },
    rateLimits: [{ kind: 'five_hour', percentUsed: 23, resetsAt }],
    cost: { usd: 1.84 },
    changed: ['context', 'rateLimits', 'cost'],
  })
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect(await ui.find({ type: 'Text', text: /42%/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /of 1M/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Context/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Session/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /resets \d\d:\d\d/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Cost/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /[█░]/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /23%/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /\$1\.84/ })).toBeDefined()
    await ui.unmount()
  }
})

test('pace: ahead of the window is a warning, behind is fine', async () => {
  const now = Date.parse('2026-10-14T12:00:00Z')
  const in1h = new Date(now + 3600_000).toISOString() // 80% of 5h elapsed
  expect(paceTone(50, 'five_hour', in1h, now)).toBe('success')
  expect(paceTone(85, 'five_hour', in1h, now)).toBe('warning')
  expect(paceTone(95, 'five_hour', in1h, now)).toBe('error')
  const in4h = new Date(now + 4 * 3600_000).toISOString() // 20% elapsed
  expect(paceTone(45, 'five_hour', in4h, now)).toBe('error')
  expect(paceTone(60, 'spend_limit', undefined, now)).toBe('warning')
})

test('formatting helpers', async () => {
  expect(modelName('claude-opus-5-5[1m]')).toBe('Opus 5.5')
  expect(modelName('Opus 5.5')).toBe('Opus 5.5')
  expect(modelName('claude-sonnet-4-20250514')).toBe('Sonnet 4')
  expect(modelName('claude-sonnet-4-5-20250929')).toBe('Sonnet 4.5')
  expect(repoName('git@github.com:you/foo.git', '')).toBe('you/foo')
  expect(repoName('https://github.com/you/foo', '')).toBe('you/foo')
  expect(repoName('', '/Users/x/Repositories/site/.bare')).toBe('site')
  expect(repoName('', '')).toBeUndefined()
  expect(resetLabel('2026-10-14T12:00:00Z', 'five_hour')).toBe('14:00')
})

test('band re-reads git after a turn: sc layout worktree on a branch', async ($, on) => {
  mock.env(on, { HOME: '/Users/x' })
  on('session.cwd', () => ({ value: '/Users/x/Repositories/site/main' }))
  const out: Record<string, string> = {
    'rev-parse --path-format=absolute --git-dir --git-common-dir':
      '/Users/x/Repositories/site/.bare/worktrees/main\n/Users/x/Repositories/site/.bare',
    'rev-parse --show-toplevel': '/Users/x/Repositories/site/main',
    'branch --show-current': 'feature/x',
    'rev-parse --short HEAD': 'abc1234',
    'remote get-url origin': 'git@github.com:you/site.git',
  }
  on('process.run', (_$, e) => {
    const stdout = out[e.argv.slice(2).join(' ')]
    return { value: { exitCode: stdout ? 0 : 1, stdout: stdout ?? '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  await $.turn.complete({ turnId: 't1', reason: 'answer', answer: '', durationMs: 1, isAborted: false })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /you\/site/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /feature\/x/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Worktree/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^main$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /~\/Repositories\/site\/main/ })).toBeDefined()
  for (const label of ['Directory', 'Repository', 'Branch', 'Worktree']) {
    expect(await ui.find({ type: 'Text', text: new RegExp(`^\\S+ ${label} $`) })).toBeDefined()
  }
  expect(await ui.find({ type: 'Text', text: /^\u{f07c} Directory $/u })).toBeDefined()
  await ui.unmount()
})

test('/clear re-reads usage; a passed reset and no limits are not shown as live figures', async ($, on) => {
  mock.env(on, { HOME: '/Users/x' })
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 1_000_000 }, rateLimits: [] } }))
  on('session.end', (_$, e) => ({ sessionId: e.sessionId }))
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  const past = new Date(Date.now() - 60_000).toISOString()
  await $.session.measure({
    context: { tokens: 900_000, window: 1_000_000, percent: 90 },
    rateLimits: [{ kind: 'five_hour', percentUsed: 97, resetsAt: past }],
    changed: ['context', 'rateLimits'],
  })
  let ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /reset, awaiting next reading/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /97%/ })).toBeUndefined()
  await ui.unmount()

  await $.session.end({ reason: 'clear', sessionId: 's1', resume: { id: 's1' } })
  ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /Context/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Limits/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /90%/ })).toBeUndefined()
  await ui.unmount()
})

test('/model and /effort update the band without waiting for a request', async ($, on) => {
  mock.env(on, { HOME: '/Users/x' })
  on('session.model', () => ({ value: 'claude-sonnet-5-5' }))
  on('command.run', () => ({ text: '' }))
  const run = (command: string, args: string) =>
    $.command.run({ command, args, origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 120 } })
  await run('model', 'sonnet')
  await run('effort', 'high')
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /Sonnet 5\.5/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /high/ })).toBeDefined()
  await ui.unmount()
})

test('session.start: a failing usage read still leaves model and git drawn', async ($, on) => {
  mock.env(on, { HOME: '/Users/x' })
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('session.usage', () => {
    throw new Error('usage unavailable')
  })
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  on('session.cwd', () => ({ value: '/Users/x/Repositories/site' }))
  on('process.run', (_$, e) => {
    const stdout = e.argv.includes('--show-current') ? 'main' : e.argv.includes('--git-dir') ? '/r/.git\n/r/.git' : ''
    return { value: { exitCode: stdout ? 0 : 1, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  await $.session.start({ cwd: '/Users/x/Repositories/site', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /Opus 5\.5/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^\u{f06a9} Model $/u })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /main/ })).toBeDefined()
  await ui.unmount()
})

test('no repo still gets its row; no mode row; subagent model switches are ignored', async ($, on) => {
  mock.env(on, { HOME: '/Users/x' })
  on('classic.PostModelSwitch', () => ({}))
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  await $.session.measure({ context: { window: 200_000 }, rateLimits: [], changed: ['context'] })
  const band = async (re: RegExp) => {
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    const found = await ui.find({ type: 'Text', text: re })
    await ui.unmount()
    return found
  }
  expect(await band(/^none$/)).toBeDefined()
  expect(await band(/^\S+ Mode $/)).toBeUndefined()

  const sw = (to: string, agent?: string) =>
    $.classic.PostModelSwitch({
      from_model: 'claude-opus-5-5', to_model: to, requested_model: null, source: 'picker',
      context_tokens: 0, prompt_cache_warm: false, cache_ttl: '5m', ...(agent ? { agent_id: agent } : {}),
    } as never)
  await sw('claude-sonnet-5-5', 'a1')
  expect(await band(/Sonnet 5\.5/)).toBeUndefined()
  await sw('claude-haiku-5-5')
  expect(await band(/Haiku 5\.5/)).toBeDefined()
})
