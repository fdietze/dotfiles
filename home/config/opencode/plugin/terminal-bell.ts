import type { Plugin } from "@opencode-ai/plugin"

export const TerminalBell: Plugin = async ({ project, client, $, directory, worktree }) => {
  return {
    event: async ({ event }) => {
      if (event.type === "session.idle") {
        // console.log("Session went idle")
        await Bun.write(Bun.stdout, "\x07")
      }
    }
  }
}
