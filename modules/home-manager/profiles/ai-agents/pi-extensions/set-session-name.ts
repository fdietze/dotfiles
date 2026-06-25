// Tool letting the AI label the current pi session with a short (2-word) phrase.
// Mechanism: pi.setSessionName() is the single source of truth — pi rebuilds the
// terminal title as "pi - <name> - <cwd>" (agent-session.js:2155,
// interactive-mode.js:526), visible in kitty tabs and the niri/noctalia
// active-window bar. The name also persists in the session file and shows in the
// session selector + footer. No event handlers needed: pi has no auto-naming, so
// the title is never clobbered behind our back.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "setSessionName",
    label: "Set Session Name",
    description:
      "Set the pi session name (2 words) labeling the current main task. " +
      "Pi renders it into the terminal title as 'pi - <name> - <cwd>', " +
      "visible in the kitty tab and the niri/noctalia active-window bar.",
    promptSnippet: "Set a 2-word session name labeling the current main task",
    promptGuidelines: [
      "Call setSessionName with 2 words whenever the session's main topic/job/task changes, to relabel the window.",
    ],
    parameters: Type.Object({
      name: Type.String({
        description: "Two words summarizing the current main task",
      }),
    }),
    async execute(_toolCallId, params) {
      pi.setSessionName(params.name);
      return {
        content: [{ type: "text", text: `Session name set: "${params.name}"` }],
        details: {},
      };
    },
  });
}
