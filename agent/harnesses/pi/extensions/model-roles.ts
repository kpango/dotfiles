/**
 * Virtual Model Roles Extension for Pi 1.7.0
 *
 * Registers `role/*` virtual models (`role/default`, `role/slow`, `role/plan`,
 * `role/good`, `role/smol`, `role/fast`, `role/review`, `role/judge`, `role/tiny`,
 * `role/memory`) via Pi 1.7.0's `pi.registerVirtualModel` API backed by `model-routing.json`.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  ROLE_DEFINITIONS,
  loadModelRoutingJson,
  resolveRoleCandidateChain,
  selectPhysicalCandidate,
  type ThinkingLevel,
} from "./lib/model-roles-core";

export * from "./lib/model-roles-core";

const ALL_THINKING_LEVELS: ThinkingLevel[] = ["off", "minimal", "low", "medium", "high", "xhigh", "max"];

export default function (pi: ExtensionAPI) {
  if (typeof pi.registerVirtualModel !== "function") return;

  for (const role of ROLE_DEFINITIONS) {
    pi.registerVirtualModel({
      provider: "role",
      id: role.id,
      name: role.name,
      thinkingLevels: ALL_THINKING_LEVELS,
      route(request, ctx) {
        const routing = loadModelRoutingJson();
        const requested = request.thinkingLevel !== "off" ? request.thinkingLevel : undefined;
        const candidates = resolveRoleCandidateChain(routing, role, requested as ThinkingLevel | undefined);
        const picked = selectPhysicalCandidate(
          candidates,
          request,
          {
            find: (provider, id) => {
              // In Pi, OpenAI Codex auth exposes models under "openai-codex" and
              // Antigravity bridge exposes models under "antigravity".
              const direct = ctx.modelRegistry.find(provider, id);
              if (direct) return direct;
              if (provider === "openai") return ctx.modelRegistry.find("openai-codex", id);
              if (provider === "antigravity-cli") return ctx.modelRegistry.find("antigravity", id);
              return undefined;
            },
            isAvailable: (m) => {
              const reg = ctx.modelRegistry as unknown as { hasConfiguredAuth?: (model: unknown) => boolean };
              return typeof reg.hasConfiguredAuth === "function" ? reg.hasConfiguredAuth(m) : true;
            },
          },
        );
        if (!picked) {
          throw new Error(`No physical model available in registry for virtual role "role/${role.id}".`);
        }
        return picked;
      },
    });
  }
}
