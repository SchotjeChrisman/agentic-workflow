export type Tone = 'success' | 'warning' | 'error'

const WINDOW_MS: Record<string, number> = {
  five_hour: 5 * 3600_000,
  seven_day: 7 * 86400_000,
}

export const LABEL: Record<string, string> = { five_hour: 'Session', seven_day: 'Week', spend_limit: 'Spend' }

// Nerd Font glyphs (JetBrainsMono Nerd Font)
export const ICON = {
  folder: '\uf07c',
  model: '\u{f06a9}',
  effort: '\uf0e7',
  repo: '\uf401',
  branch: '\ue725',
  worktree: '\u{f0645}',
  context: '\u{f035b}',
  five_hour: '\u{f051f}',
  seven_day: '\u{f00ed}',
  spend_limit: '\uf155',
  limit: '\u{f051f}',
  cost: '\uf155',
} as const

export function contextTone(pct: number): Tone {
  return pct >= 80 ? 'error' : pct >= 50 ? 'warning' : 'success'
}

// used vs. expected-at-this-point-in-window, so 50% with most of the window left stays green
export function paceTone(pct: number, kind: string, resetsAt: string | undefined, now: number): Tone {
  const window = WINDOW_MS[kind]
  const resets = resetsAt ? Date.parse(resetsAt) : NaN
  if (!window || Number.isNaN(resets)) return contextTone(pct)
  if (pct >= 90) return 'error'
  const elapsed = Math.min(window, Math.max(0, window - (resets - now)))
  const diff = pct - (elapsed / window) * 100
  return diff >= 20 ? 'error' : diff >= 0 ? 'warning' : 'success'
}

// a window whose reset time has gone by still carries its last (stale) percent
export function isPast(resetsAt: string | undefined, now: number): boolean {
  const t = resetsAt ? Date.parse(resetsAt) : NaN
  return !Number.isNaN(t) && t <= now
}

export function windowSize(tokens: number): string {
  return tokens >= 1_000_000 ? `${tokens / 1_000_000}M` : `${Math.round(tokens / 1000)}K`
}

// ponytail: pinned to Amsterdam like the old script; fallback is the runtime's own zone
export function resetLabel(iso: string, kind: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  const opts: Intl.DateTimeFormatOptions = { hour: '2-digit', minute: '2-digit', hour12: false }
  if (kind !== 'five_hour') opts.weekday = 'short'
  try {
    return d.toLocaleString('en-GB', { ...opts, timeZone: 'Europe/Amsterdam' })
  } catch {
    return d.toLocaleString('en-GB', opts)
  }
}

// "claude-opus-5-5[1m]" -> "Opus 5.5"; anything unrecognised passes through
export function modelName(id: string): string {
  const m = /(opus|sonnet|haiku|fable)-(\d+)(?:-(\d{1,2}))?(?!\d)/i.exec(id)
  if (!m) return id
  const family = m[1]!
  return `${family[0]!.toUpperCase()}${family.slice(1).toLowerCase()} ${m[2]}${m[3] ? '.' + m[3] : ''}`
}

// owner/name from an origin URL (ssh or https), else the main repo dir's name
export function repoName(remote: string, commonDir: string): string | undefined {
  const m = /[:/]([^/:]+)\/([^/]+?)(?:\.git)?\/?$/.exec(remote)
  if (m) return `${m[1]}/${m[2]}`
  if (!commonDir) return undefined
  const parts = commonDir.replace(/\/+$/, '').split('/')
  return parts.at(-2) || undefined
}

export function basename(path: string): string {
  return path.replace(/\/+$/, '').split('/').at(-1) ?? path
}

export function tildify(path: string, home: string | undefined): string {
  return home && (path === home || path.startsWith(home + '/')) ? '~' + path.slice(home.length) : path
}
