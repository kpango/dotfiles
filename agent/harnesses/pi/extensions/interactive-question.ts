/**
 * Interactive Questionnaire & Disambiguation Extension for Pi Coding Agent
 *
 * Allows the agent to ask the user structured multiple-choice questions,
 * confirmation prompts, or multi-line text input using rich interactive TUI modals.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Container, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";

const QuestionParams = Type.Object({
  title: Type.String({ description: "Question title or goal" }),
  options: Type.Optional(Type.Array(Type.String(), { description: "List of options for multiple choice selection" })),
  allowCustomInput: Type.Optional(Type.Boolean({ description: "Allow user to type a custom answer. Default: true", default: true })),
});

export const CUSTOM_INPUT_SENTINEL = "Other (type custom response)";

/**
 * Build the option list shown to the user, appending the custom-input sentinel
 * only when custom input is allowed AND the user's own options don't already
 * include that exact string. Returning `customAppended` lets the caller decide
 * whether a matching selection is the custom trigger or a genuine user option,
 * so a user option literally named like the sentinel is never misrouted.
 */
export function buildQuestionOptions(
  userOptions: string[] | undefined,
  allowCustomInput: boolean
): { options: string[]; customAppended: boolean } {
  const base = userOptions ? [...userOptions] : [];
  const customAppended = allowCustomInput && !base.includes(CUSTOM_INPUT_SENTINEL);
  return { options: customAppended ? [...base, CUSTOM_INPUT_SENTINEL] : base, customAppended };
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "questionnaire",
    label: "Interactive Question",
    description: "Ask the user a structured question or choice to clarify requirements, solicit design feedback, or resolve ambiguity.",
    parameters: QuestionParams,

    async execute(_id, params, _signal, _onUpdate, ctx) {
      if (!ctx.hasUI) {
        return {
          content: [{ type: "text", text: `(Non-interactive mode) Assumed default option for: "${params.title}"` }],
          details: { chosen: params.options?.[0] || "default" },
        };
      }

      const { options, customAppended } = buildQuestionOptions(params.options, params.allowCustomInput ?? true);

      const choice = await ctx.ui.select(params.title, options);

      if (customAppended && choice === CUSTOM_INPUT_SENTINEL) {
        const custom = await ctx.ui.editor(`Custom response for: ${params.title}`, "");
        return {
          content: [{ type: "text", text: `User responded: "${custom || "(empty)"}"` }],
          details: { chosen: custom || "" },
        };
      }

      return {
        content: [{ type: "text", text: `User selected: "${choice || "(cancelled)"}"` }],
        details: { chosen: choice || "" },
      };
    },

    renderCall(args, theme) {
      return new Text(theme.fg("toolTitle", theme.bold("question ")) + theme.fg("accent", args.title), 0, 0);
    },

    renderResult(result, _opts, theme) {
      const txt = result.content[0]?.type === "text" ? result.content[0].text : "(no answer)";
      return new Text(theme.fg("success", "✓ ") + theme.fg("text", txt), 0, 0);
    },
  });
}
