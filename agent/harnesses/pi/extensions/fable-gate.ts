/**
 * Fable Spot Budget Gate for Pi Coding Agent
 *
 * pi 版 `swarm-fable-gate.sh`(claude の PreToolUse:Task|Agent hook)相当。SWARM.md §1
 * スポット判断層の機械的ゲート: `model: 'Max'` / `'fable'`(= claude-fable-5 / 5-1)で起動される
 * subagent スポーンは、`budget-guard.sh --fable <task-id>` が発行した未消費 grant トークン
 * (.fable-grants/)を 1 つ消費して初めて許可される(1 grant = 1 スポーン、TTL 失効あり)。
 * grant なし・期限切れはブロック。「発動 4 条件 + 1 タスク 1 回・1 ミッション 2 回」の prose
 * 規範を hook レベルで閉じる(pi では従来 hook 強制点が無く SKILL.md prose のみだった)。
 *
 * claude 版との差異(移行時の設計判断、2026-09-07 kpango 承認):
 *  - claude hook は `tool_input.model` で fable 起動を判定するが、pi の `subagent` ツールは
 *    single/parallel/chain モードで model を LLM に露出しない(workflow ステップのみ model
 *    override)。よって fable/Max spawn の検知は subagents.ts の discoverAgents() でエージェント
 *    frontmatter の tier を解決して行う(D1=(a) 全モードカバー)。
 *  - grant 消費ロジック(TTL 判定 + 原子的 mv)は swarm-lint-lib.sh の grant_consume() を
 *    bash ブリッジ経由で再利用する(TypeScript への再実装はしない — Ponytail Step2 二重化回避)。
 *  - grant の state-dir は budget-guard.sh --fable が書く共有 dir(swarm_state_dir())をそのまま
 *    読む(writer/reader 一致。SWARM_STATE_DIR での隔離は別途 Tier B 拡張、D2=共有)。
 *
 * fail-open 方針: bash/スクリプト欠落等のインフラ障害では **ブロックしない**(予算ゲートで
 * あり安全ゲートではない — security-gate.ts の Tier B fail-closed とは対照的)。ただし
 * 「fable spawn なのに grant が無い」正当なケースは確実にブロックする。
 */

import { spawnSync } from "node:child_process";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { type AgentConfig, discoverAgents } from "./subagents";

// SWARM.md §1 で spot 層を起動する model 指定。抽象 tier 名("Max"/"fable")と、それが解決する
// 具体モデル id(claude-fable-5 / claude-fable-5-1、provider prefix の有無を問わず)の双方を拾う。
export function isFableModel(model: string | undefined | null): boolean {
  if (!model) return false;
  const m = model.toLowerCase();
  // 抽象 tier 名(完全一致): "max" / "fable"
  if (m === "max" || m === "fable") return true;
  // 具体モデル id(部分一致): "claude-fable-5" は "claude-fable-5" と "claude-fable-5-1" の
  // 両方に、"anthropic/claude-fable-5-1" のような provider prefix 付きにもマッチする。
  if (m.includes("claude-fable-5")) return true;
  return false;
}

// スポーン prompt/task に埋め込まれた [fable-spot:<task-id>] マーカーから task-id を取り出す。
// grant は task に束縛される(budget-guard.sh --fable に渡したのと同一 task-id の grant のみ
// 消費できる)ため、マーカーが無い fable spawn はブロックする。
export function extractFableSpotMarker(text: string | undefined | null): string | null {
  if (!text) return null;
  const m = text.match(/\[fable-spot:([^\]]+)\]/);
  return m ? m[1] : null;
}

export interface SpawnSpec {
  agent: string;
  model?: string;
  task: string;
}

// subagent ツール入力(single / tasks[] / chain[] / workflow[])を横断し、全スポーンの
// (agent, model override, task)を平坦化する。model override は workflow ステップのみ持つ
// (TaskItem/ChainItem スキーマは model を持たない — subagents.ts の Type.Object 定義準拠)。
export function collectSpawnSpecs(input: Record<string, unknown>): SpawnSpec[] {
  const specs: SpawnSpec[] = [];
  const agentOf = (v: unknown): string => {
    const s = typeof v === "string" ? v.trim() : "";
    return s || "auto";
  };
  // single mode
  if (typeof input.task === "string" && input.task) {
    specs.push({ agent: agentOf(input.agent), task: input.task });
  }
  for (const key of ["tasks", "chain"] as const) {
    const arr = input[key];
    if (Array.isArray(arr)) {
      for (const item of arr) {
        if (item && typeof item === "object" && typeof (item as any).task === "string") {
          specs.push({ agent: agentOf((item as any).agent), task: (item as any).task });
        }
      }
    }
  }
  if (Array.isArray(input.workflow)) {
    for (const step of input.workflow) {
      if (step && typeof step === "object" && typeof (step as any).task === "string") {
        const model = typeof (step as any).model === "string" ? (step as any).model : undefined;
        specs.push({ agent: agentOf((step as any).agent), model, task: (step as any).task });
      }
    }
  }
  return specs;
}

// spawn の実効モデルを解決する: 明示 override(workflow の model)を最優先、無ければエージェント
// frontmatter の raw tier(modelTier)、それも無ければ解決済み具体 id(model)を見る。
export function resolveSpawnModel(
  spec: SpawnSpec,
  agents: AgentConfig[],
): string | undefined {
  if (spec.model) return spec.model;
  const a = agents.find((x) => x.name === spec.agent);
  if (!a) return undefined;
  return a.modelTier ?? a.model;
}

export type GrantConsumeResult = { consumed: string | null; infra: boolean };

// grant_consume() を bash ブリッジ経由で呼ぶ（swarm_state_dir/budget/.fable-grants から
// TTL 判定 + 原子的 mv で 1 grant 消費）。exit 0=消費(stdout=grant名) / 1=grant無し(block) /
// 3 or spawn error=インフラ障害(fail-open)。envOverride はテストから SWARM_STATE_DIR を
// 注入するための依存性注入口（本番は未指定で process.env を継承）。グローバルな
// process.env を変異せず引数で渡すことで、並列テスト間の env 汚染を避ける。
//
// 既知の限界(claude の swarm-fable-gate.sh と同様): grant は `[fable-spot:<task-id>]`
// マーカーの task-id と grant ファイル名の task-id を突き合わせるのみで、呼び出し元セッション/
// エージェントとの紐付けは無い(なりすまし耐性なし)。同一 task-id の未消費 grant なら
// budget-guard を通していない別の呼び出しでも消費できる。single-session/single-user 前提では
// 実害は限定的(集約上限は保たれる)。mission/agent 識別子のバインドは将来の強化余地(follow-up)。
export function consumeFableGrant(
  scriptsDir: string,
  sanitizedTid: string,
  envOverride?: Record<string, string>,
): GrantConsumeResult {
  const bridge =
    'set -uo pipefail; scripts="$1"; tid="$2"; ' +
    '[ -f "$scripts/swarm-common-lib.sh" ] || { echo "__INFRA__:no-common-lib" >&2; exit 3; }; ' +
    '[ -f "$scripts/swarm-lint-lib.sh" ] || { echo "__INFRA__:no-lint-lib" >&2; exit 3; }; ' +
    '. "$scripts/swarm-common-lib.sh"; swarm_load_budget_conf; : "${FABLE_GRANT_TTL_SECONDS:=600}"; ' +
    '. "$scripts/swarm-lint-lib.sh"; ' +
    'command -v grant_consume >/dev/null 2>&1 || { echo "__INFRA__:no-grant_consume" >&2; exit 3; }; ' +
    'gd="$(swarm_state_dir)/budget/.fable-grants"; ' +
    'if out=$(grant_consume "$gd" "$FABLE_GRANT_TTL_SECONDS" "$tid"); then printf "%s" "$out"; exit 0; else exit 1; fi';
  try {
    const res = spawnSync("bash", ["-c", bridge, "_", scriptsDir, sanitizedTid], {
      encoding: "utf-8",
      env: envOverride ? { ...process.env, ...envOverride } : process.env,
    });
    if (res.error) return { consumed: null, infra: true };
    if (res.status === 0) {
      const out = (res.stdout || "").trim();
      return { consumed: out || null, infra: false };
    }
    if (res.status === 1) return { consumed: null, infra: false }; // 正当な grant 無し
    return { consumed: null, infra: true }; // exit 3(インフラ)等
  } catch {
    return { consumed: null, infra: true };
  }
}

function scriptsDirDefault(): string {
  // 実行時デプロイ先。~/.pi/agent/skills は dotfiles の agent/skills へ **直接 symlink** される
  // (AGENTS.md 参照。「merged directory」は ~/.pi/agent/extensions 専用の用語なのでここでは使わない)。
  // budget-guard.sh --fable が grant を書く経路と
  // 同一の swarm_state_dir() をこのスクリプト群経由で解決するため writer/reader が一致する。
  return path.join(os.homedir(), ".pi", "agent", "skills", "swarm-implement", "scripts");
}

function noMarkerMessage(agent: string): string {
  return (
    `fable/Max スポーン(agent=${agent})の task に [fable-spot:<task-id>] マーカーが無い — ` +
    `grant は task に束縛される。budget-guard.sh --fable に渡したのと同一の task-id を task に ` +
    `含めること(SWARM.md §1 スポット判断層)`
  );
}

function noGrantMessage(tid: string): string {
  return (
    `task '${tid}' の未消費 fable grant が無い — budget-guard.sh --fable <task-id> ` +
    `[--mission=<slug>] を先に通すこと(発動 4 条件・回数上限は SWARM.md §1 スポット判断層。` +
    `grant は TTL で失効・1 grant = 1 スポーン・task 束縛)`
  );
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "subagent") return;
    const input = (event.input ?? {}) as Record<string, unknown>;
    const specs = collectSpawnSpecs(input);
    if (specs.length === 0) return;

    let agents: AgentConfig[];
    try {
      agents = discoverAgents(ctx.cwd);
    } catch {
      // エージェント探索不能はインフラ障害 → fail-open(予算ゲートは安全ゲートではない)
      return;
    }

    // 既知の限界(Checker 2026-09-07 advisory、いずれも現状無害・fail-safe方向):
    //  (1) agent:"auto" は実行時 inferAgentFromTask で動的解決されるため resolveSpawnModel
    //      では未知エージェント扱いになり検知外になる。現状カタログに Max/fable tier を
    //      宣言するエージェントは存在せず実害無。将来 Max tier エージェントを追加する際は
    //      明示 agent: 指定を要求するか auto 解決を共有すること(follow-up)。
    //  (2) 複数 fable spec が1コールに混在し先行 spec の grant 消費後に後続 spec が marker/grant
    //      欠如だと、呼び出し全体を block しつつ消費済 grant は巻き戻せない(grant leak)。
    //      「1 grant=1 spawn」を破らず fail-safe 方向(過剰にblock)のため安全上の欠陥ではないが、
    //      fable spawn はスポット層(1タスク1回)で単一が典型のため実害は稀(follow-up)。
    const scriptsDir = scriptsDirDefault();
    for (const spec of specs) {
      const model = resolveSpawnModel(spec, agents);
      if (!isFableModel(model)) continue; // fable/Max 以外は素通り(inherit 含む — 移植元踏襲の受容済限界)

      const tid = extractFableSpotMarker(spec.task);
      if (!tid) {
        return { block: true, reason: noMarkerMessage(spec.agent) };
      }
      const sanitized = tid.replace(/\//g, "_");
      const { consumed, infra } = consumeFableGrant(scriptsDir, sanitized);
      if (infra) {
        // インフラ障害は fail-open。非ブロッキングに通知だけ行い次の spec へ。
        if (ctx.hasUI) {
          ctx.ui.notify(
            `swarm-fable-gate: grant 検証をスキップ(スクリプト/bash 到達不能、task=${tid})`,
            "warning",
          );
        }
        continue;
      }
      if (!consumed) {
        return { block: true, reason: noGrantMessage(tid) };
      }
      // grant 消費成功 → この spawn は許可。次の spec へ。
      if (ctx.hasUI) {
        ctx.ui.notify(`swarm-fable-gate: fable spot grant consumed (${consumed}, task=${tid})`, "info");
      }
    }
  });
}
