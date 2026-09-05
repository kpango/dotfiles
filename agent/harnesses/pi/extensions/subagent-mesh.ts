/**
 * Subagent Mesh Extension for Pi Coding Agent
 *
 * Implements GrokBot-style autonomous P2P subagent messaging, Blackboard mesh,
 * Bayesian confidence propagation, refutational dissent, and autonomous peer
 * handoff workflows.
 */

import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

import {
  // Types & Interfaces
  SubagentTopic,
  MeshMessage,
  MeshSender,
  ConfidenceScore,
  ObjectiveVerificationEvidence,
  SpecPayload,
  DraftPayload,
  CritiquePayload,
  VerificationPayload,
  BlockerPayload,
  HandoffState,
  ArbitrationResult,
  BenchmarkResult,

  // Constants
  GATE_CONFIDENCE_THRESHOLD,
  MAX_ATTEMPTS_HARD_CAP,
  SOFT_CHECKPOINT_ATTEMPT,
  DEFAULT_PRIOR_CONFIDENCE,
  DEFAULT_PRIOR_LOG_ODDS,

  // Classes
  SubagentMesh,
  BlackboardStream,
  CoordinatorEngine,
  ConfidenceEngine,
  PeerHandoffController,

  // Functions
  calculateConfidence,
  sigmoid,
  logOdds,
  calculatePercentiles,
  createMeshMessage,
} from "./lib/subagent-mesh-core";

// Re-export everything from core
export * from "./lib/subagent-mesh-core";

// Global in-memory singleton instances for current agent session
export const globalMesh = new SubagentMesh();
export const globalCoordinator = new CoordinatorEngine();
export const activeControllers = new Map<string, PeerHandoffController>();
export const activeStreams = new Map<string, BlackboardStream>();

export function getOrCreateStream(correlationId: string, basePath?: string): BlackboardStream {
  let stream = activeStreams.get(correlationId);
  if (!stream) {
    const dir = basePath ?? path.join(os.homedir(), ".pi", "agent", "relay", "blackboard");
    stream = new BlackboardStream({ basePath: dir, correlationId });
    activeStreams.set(correlationId, stream);
  }
  return stream;
}

export function getOrCreateController(correlationId: string): PeerHandoffController {
  let ctrl = activeControllers.get(correlationId);
  if (!ctrl) {
    ctrl = new PeerHandoffController({
      correlationId,
      onGateReady: async (verdict) => {
        const stream = getOrCreateStream(correlationId);
        const gateReadyMsg = createMeshMessage({
          topic: "verification",
          sender: { id: "coordinator", role: "coordinator" },
          correlationId,
          recipient: "*",
          payload: {
            taskSlug: verdict.taskSlug ?? "task",
            status: "GATE_READY",
            verdict: "PASS",
            confidence: 1.0,
          },
          evidence: verdict.evidence,
        });
        // Publish to mesh and append to blackboard stream
        globalMesh.publish(gateReadyMsg);
        await stream.append(gateReadyMsg);
      },
    });
    activeControllers.set(correlationId, ctrl);
  }
  return ctrl;
}

let subscriptionsInitialized = false;

/**
 * Wire active mesh subscriptions: listen on all topics, pipe events to
 * CoordinatorEngine, track task states, and autonomously coordinate peer handoff.
 */
export function setupMeshSubscriptions(): void {
  if (subscriptionsInitialized) return;
  subscriptionsInitialized = true;

  const topics: SubagentTopic[] = ["spec", "draft", "critique", "verification", "blocker"];
  for (const topic of topics) {
    globalMesh.subscribe(topic, async (msg: MeshMessage) => {
      // 1. Pipe all events to CoordinatorEngine for deduplication and status aggregation
      globalCoordinator.processMessage(msg);

      // 2. Drive autonomous peer handoff finite state machine
      const ctrl = getOrCreateController(msg.correlationId);

      if (msg.topic === "draft") {
        ctrl.submitDraft(msg.payload as DraftPayload, msg.evidence);
      } else if (msg.topic === "critique") {
        ctrl.receiveCritiques([msg.payload as CritiquePayload]);
      } else if (msg.topic === "verification") {
        const payload = msg.payload as any;
        // Ignore internal coordinator announcements to prevent recursion
        if (payload?.status !== "GATE_READY" && msg.sender.role !== "coordinator") {
          const res = ctrl.receiveVerification(payload as VerificationPayload);
          if (res.state === "GATE_READY") {
            const gateReadyMsg = createMeshMessage({
              topic: "verification",
              sender: { id: "coordinator", role: "coordinator" },
              correlationId: msg.correlationId,
              recipient: "*",
              parentMessageId: msg.id,
              payload: {
                taskSlug: payload?.taskSlug ?? "task",
                status: "GATE_READY",
                verdict: "PASS",
                confidence: 1.0,
              },
              evidence: payload?.evidence ?? msg.evidence,
            });
            globalMesh.publish(gateReadyMsg);
            const stream = getOrCreateStream(msg.correlationId);
            await stream.append(gateReadyMsg);
          }
        }
      }
    });
  }
}

// Automatically initialize active mesh subscriptions
setupMeshSubscriptions();

export default function (pi: ExtensionAPI) {
  // --------------------------------------------------------------------------
  // Lifecycle Integration
  // --------------------------------------------------------------------------
  pi.on("session_start", async (_event, ctx) => {
    const defaultCorrelation = process.env.SWARM_MISSION || `session-${Date.now()}`;
    const stream = getOrCreateStream(defaultCorrelation);
    setupMeshSubscriptions();
    ctx.ui?.notify?.(`Subagent Mesh initialized (stream: ${stream.getFilePath()})`, "info");
  });

  pi.on("session_shutdown", async () => {
    for (const stream of activeStreams.values()) {
      stream.close();
    }
    activeStreams.clear();
  });

  // --------------------------------------------------------------------------
  // Tool: mesh_publish
  // --------------------------------------------------------------------------
  pi.registerTool({
    name: "mesh_publish",
    description: "Publish a message to the subagent mesh blackboard (topics: spec, draft, critique, verification, blocker).",
    parameters: Type.Object({
      topic: Type.Union([
        Type.Literal("spec"),
        Type.Literal("draft"),
        Type.Literal("critique"),
        Type.Literal("verification"),
        Type.Literal("blocker"),
      ]),
      correlationId: Type.String({ description: "Task or mission correlation ID" }),
      payload: Type.Any({ description: "Structured JSON payload matching topic" }),
      sender: Type.Optional(Type.Any({ description: "Sender identity: { id, role, model? } or sender ID string" })),
      confidence: Type.Optional(Type.Any({ description: "Confidence score object or numeric value" })),
      recipient: Type.Optional(Type.String({ description: "Target subagent ID or '*' for broadcast" })),
      parentMessageId: Type.Optional(Type.String({ description: "Parent message ID for causal DAG linking" })),
      evidence: Type.Optional(Type.Any({ description: "Objective verification evidence" })),
    }),
    handler: async (args, ctx) => {
      try {
        const stream = getOrCreateStream(args.correlationId);

        // Resolve sender identity
        let sender: MeshSender;
        if (typeof args.sender === "string") {
          sender = { id: args.sender, role: "worker" };
        } else if (args.sender && typeof args.sender === "object") {
          sender = {
            id: args.sender.id ?? "pi-user",
            role: args.sender.role ?? "operator",
            model: args.sender.model,
          };
        } else {
          sender = { id: "pi-user", role: "operator" };
        }

        // Respect Outcome Non-Disclosure for draft submissions:
        // Mask author confidence, internal reasoning, self scores before broadcasting
        let payload = args.payload;
        if (args.topic === "draft" && payload && typeof payload === "object") {
          const raw = { ...payload } as Record<string, unknown>;
          delete raw.authorConfidence;
          delete raw.authorInternalReasoning;
          delete raw.attemptNumber;
          delete raw.selfScore;
          payload = raw;
        }

        // Resolve confidence score
        let confidence: ConfidenceScore | undefined;
        if (typeof args.confidence === "number") {
          confidence = {
            score: args.confidence,
            value: args.confidence,
            prior: DEFAULT_PRIOR_LOG_ODDS,
            toolDelta: 0,
            toolWeight: 0,
            peerDelta: 0,
            peerWeight: 0,
            dissentDelta: 0,
            dissentPenalty: 0,
            sycophancyDiscount: 0,
          };
        } else if (args.confidence && typeof args.confidence === "object") {
          confidence = args.confidence as ConfidenceScore;
        }

        const msg = createMeshMessage({
          topic: args.topic as SubagentTopic,
          sender,
          correlationId: args.correlationId,
          recipient: args.recipient ?? "*",
          parentMessageId: args.parentMessageId ?? null,
          payload,
          confidence,
          evidence: args.evidence as ObjectiveVerificationEvidence,
        });

        // 1. In-Memory Pub/Sub (invokes active topic subscribers)
        globalMesh.publish(msg);

        // 2. Persistent IPC Blackboard with flock
        await stream.append(msg);

        // 3. Coordinator Stream Processing
        const procResult = globalCoordinator.processMessage(msg);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  published: true,
                  messageId: msg.id,
                  accepted: procResult.accepted,
                  duplicate: procResult.duplicate,
                  sender: msg.sender,
                  confidence: msg.confidence?.score,
                },
                null,
                2
              ),
            },
          ],
        };
      } catch (err: any) {
        return {
          content: [{ type: "text", text: `Error publishing to mesh: ${err.message}` }],
        };
      }
    },
  });

  // --------------------------------------------------------------------------
  // Tool: mesh_query
  // --------------------------------------------------------------------------
  pi.registerTool({
    name: "mesh_query",
    description: "Query messages from the subagent blackboard event stream.",
    parameters: Type.Object({
      correlationId: Type.String({ description: "Task correlation ID to query" }),
      topic: Type.Optional(
        Type.Union([
          Type.Literal("spec"),
          Type.Literal("draft"),
          Type.Literal("critique"),
          Type.Literal("verification"),
          Type.Literal("blocker"),
        ])
      ),
      limit: Type.Optional(Type.Number({ description: "Maximum messages to return (default 20)" })),
    }),
    handler: async (args) => {
      try {
        const stream = getOrCreateStream(args.correlationId);
        let msgs = await stream.readAll();
        if (args.topic) {
          msgs = msgs.filter((m) => m.topic === args.topic);
        }
        const limit = args.limit ?? 20;
        const recent = msgs.slice(-limit);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  total: msgs.length,
                  returned: recent.length,
                  messages: recent,
                },
                null,
                2
              ),
            },
          ],
        };
      } catch (err: any) {
        return {
          content: [{ type: "text", text: `Error querying mesh: ${err.message}` }],
        };
      }
    },
  });

  // --------------------------------------------------------------------------
  // Tool: mesh_confidence
  // --------------------------------------------------------------------------
  pi.registerTool({
    name: "mesh_confidence",
    description: "Calculate Bayesian confidence score from objective evidence, peer reviews, and critiques.",
    parameters: Type.Object({
      prior: Type.Optional(Type.Number({ description: "Optional custom log-odds prior" })),
      toolEvidence: Type.Optional(Type.Any({ description: "Deterministic tool verification evidence" })),
      peerReviews: Type.Optional(Type.Array(Type.Any(), { description: "Peer review approvals" })),
      critiques: Type.Optional(Type.Array(Type.Any(), { description: "Critique objections and dissents" })),
    }),
    handler: async (args) => {
      try {
        const conf = calculateConfidence({
          prior: args.prior,
          toolEvidence: args.toolEvidence as ObjectiveVerificationEvidence,
          peerReviews: args.peerReviews,
          critiques: args.critiques as CritiquePayload[],
        });

        const isGateReady = conf.score >= GATE_CONFIDENCE_THRESHOLD && (conf.breakdown?.activeBlockers ?? 0) === 0;

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  confidence: conf.score,
                  prior: conf.prior,
                  gateReady: isGateReady,
                  gateThreshold: GATE_CONFIDENCE_THRESHOLD,
                  toolDelta: conf.toolDelta,
                  peerDelta: conf.peerDelta,
                  dissentDelta: conf.dissentDelta,
                  breakdown: conf.breakdown,
                },
                null,
                2
              ),
            },
          ],
        };
      } catch (err: any) {
        return {
          content: [{ type: "text", text: `Error calculating confidence: ${err.message}` }],
        };
      }
    },
  });

  // --------------------------------------------------------------------------
  // Tool: mesh_handoff
  // --------------------------------------------------------------------------
  pi.registerTool({
    name: "mesh_handoff",
    description: "Manage autonomous peer task handoff lifecycle (draft, critiques, verification, remediation).",
    parameters: Type.Object({
      correlationId: Type.String({ description: "Task correlation ID" }),
      action: Type.Union([
        Type.Literal("submit_draft"),
        Type.Literal("receive_critiques"),
        Type.Literal("receive_verification"),
        Type.Literal("remediate"),
        Type.Literal("get_state"),
      ]),
      draft: Type.Optional(Type.Any()),
      critiques: Type.Optional(Type.Array(Type.Any())),
      verification: Type.Optional(Type.Any()),
    }),
    handler: async (args) => {
      try {
        const ctrl = getOrCreateController(args.correlationId);

        if (args.action === "get_state") {
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  correlationId: args.correlationId,
                  state: ctrl.getState(),
                  attempt: ctrl.getAttemptCount(),
                }, null, 2),
              },
            ],
          };
        }

        if (args.action === "submit_draft") {
          if (!args.draft) throw new Error("Missing 'draft' parameter");
          const res = ctrl.submitDraft(args.draft as DraftPayload);
          return {
            content: [{ type: "text", text: JSON.stringify(res, null, 2) }],
          };
        }

        if (args.action === "receive_critiques") {
          const res = ctrl.receiveCritiques((args.critiques as CritiquePayload[]) ?? []);
          return {
            content: [{ type: "text", text: JSON.stringify(res, null, 2) }],
          };
        }

        if (args.action === "receive_verification") {
          if (!args.verification) throw new Error("Missing 'verification' parameter");
          const res = ctrl.receiveVerification(args.verification as VerificationPayload);
          return {
            content: [{ type: "text", text: JSON.stringify(res, null, 2) }],
          };
        }

        if (args.action === "remediate") {
          const res = ctrl.remediate();
          return {
            content: [{ type: "text", text: JSON.stringify({ ...res, state: ctrl.getState() }, null, 2) }],
          };
        }

        throw new Error(`Unknown action: ${args.action}`);
      } catch (err: any) {
        return {
          content: [{ type: "text", text: `Error in mesh handoff: ${err.message}` }],
        };
      }
    },
  });

  // --------------------------------------------------------------------------
  // Slash Command: /mesh
  // --------------------------------------------------------------------------
  pi.registerCommand("mesh", {
    description: "Inspect subagent mesh status, blackboard streams, or reset state.",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/);
      const subcmd = parts[0] || "status";
      const correlationId = parts[1] || process.env.SWARM_MISSION || "default";

      if (subcmd === "status") {
        const statusLine = globalCoordinator.renderStatusLine(correlationId);
        const ctrl = activeControllers.get(correlationId);
        const stateStr = ctrl ? `\nHandoff State: ${ctrl.getState()} (Attempt: ${ctrl.getAttemptCount()})` : "";
        ctx.ui?.notify?.(statusLine + stateStr, "info");
        return;
      }

      if (subcmd === "stream") {
        const stream = getOrCreateStream(correlationId);
        const recent = await stream.readRecent(5);
        let out = `### Subagent Mesh Blackboard (${correlationId})\n`;
        for (const m of recent) {
          out += `- [${m.topic.toUpperCase()}] ${m.sender.id} (${new Date(m.timestamp).toLocaleTimeString()})\n`;
        }
        ctx.ui?.notify?.(out, "info");
        return;
      }

      if (subcmd === "reset") {
        globalMesh.clear();
        activeControllers.delete(correlationId);
        activeStreams.delete(correlationId);
        ctx.ui?.notify?.(`Reset mesh state for correlationId: ${correlationId}`, "info");
        return;
      }

      ctx.ui?.notify?.(`Unknown mesh subcommand: ${subcmd}. Usage: /mesh [status|stream|reset] [correlationId]`, "error");
    },
  });
}
