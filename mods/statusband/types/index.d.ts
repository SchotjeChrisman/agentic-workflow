export type Limit = { kind: string; percentUsed: number; resetsAt?: string }
export type Usage = {
  tokens?: number
  window: number
  percent?: number
  limits: Limit[]
  costUsd?: number
}
export type Git = { cwd: string; repo?: string; branch?: string; worktree?: string }
export type Model = { name: string; effort?: string }

declare module 'claude-code' {
  interface PluginState {
    statusband: { usage: Usage | null; git: Git | null; model: Model | null; now: number }
  }
}
