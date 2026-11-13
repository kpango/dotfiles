import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  type AgentConfig,
  collectSpawnSpecs,
  consumeFableGrant,
  extractFableSpotMarker,
  isFableModel,
  resolveSpawnModel,
  type SpawnSpec,
} from "../fable-gate";

let pass = 0;
let fail = 0;
function check(name: string, ok: boolean, msg?: string) {
  if (ok) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}: ${msg || ""}`);
    fail++;
  }
}

// 1. isFableModel: tier 名 + 具体 id + provider prefix を拾い、非 fable は落とす
check("isFableModel: 'Max' tier", isFableModel("Max"));
check("isFableModel: 'fable' tier (lowercase)", isFableModel("fable"));
check("isFableModel: 'FABLE' case-insensitive", isFableModel("FABLE"));
check("isFableModel: concrete claude-fable-5", isFableModel("claude-fable-5"));
check("isFableModel: concrete claude-fable-5-1", isFableModel("claude-fable-5-1"));
check("isFableModel: provider-prefixed anthropic/claude-fable-5-1", isFableModel("anthropic/claude-fable-5-1"));
check("isFableModel: non-fable 'High' → false", !isFableModel("High"));
check("isFableModel: non-fable 'sonnet' → false", !isFableModel("sonnet"));
check("isFableModel: 'anthropic/claude-sonnet-5' → false", !isFableModel("anthropic/claude-sonnet-5"));
check("isFableModel: undefined → false", !isFableModel(undefined));
check("isFableModel: empty string → false", !isFableModel(""));

// 2. extractFableSpotMarker
check("marker: extracts task-id", extractFableSpotMarker("do X [fable-spot:t1.3] please") === "t1.3");
check("marker: first match wins", extractFableSpotMarker("[fable-spot:a] [fable-spot:b]") === "a");
check("marker: slash preserved (sanitize later)", extractFableSpotMarker("[fable-spot:sub/task]") === "sub/task");
check("marker: none → null", extractFableSpotMarker("no marker here") === null);
check("marker: empty → null", extractFableSpotMarker("") === null);
check("marker: undefined → null", extractFableSpotMarker(undefined) === null);

// 3. collectSpawnSpecs: 全モード横断、model は workflow のみ
const singleSpecs = collectSpawnSpecs({ agent: "go-expert", task: "impl" });
check("collect: single mode", singleSpecs.length === 1 && singleSpecs[0].agent === "go-expert" && singleSpecs[0].model === undefined);
const parallelSpecs = collectSpawnSpecs({ tasks: [{ agent: "a", task: "t1" }, { task: "t2" }] });
check("collect: tasks[] (missing agent → auto)", parallelSpecs.length === 2 && parallelSpecs[1].agent === "auto" && parallelSpecs[1].model === undefined);
const chainSpecs = collectSpawnSpecs({ chain: [{ agent: "b", task: "c1" }] });
check("collect: chain[]", chainSpecs.length === 1 && chainSpecs[0].agent === "b");
const wfSpecs = collectSpawnSpecs({ workflow: [{ id: "s1", agent: "arch", task: "diag", model: "Max" }, { id: "s2", task: "x" }] });
check("collect: workflow[] carries model override", wfSpecs.length === 2 && wfSpecs[0].model === "Max" && wfSpecs[1].model === undefined);
const mixed = collectSpawnSpecs({ task: "s", tasks: [{ task: "p" }], workflow: [{ id: "w", task: "wf", model: "fable" }] });
check("collect: mixed modes flattened", mixed.length === 3);
check("collect: empty input → []", collectSpawnSpecs({}).length === 0);
// TaskItem/ChainItem に model は無い(スキーマ準拠) — 混入しても拾わない
const noModelLeak = collectSpawnSpecs({ tasks: [{ agent: "a", task: "t", model: "Max" } as any] });
check("collect: tasks[] model is NOT read (schema has no model)", noModelLeak[0].model === undefined);

// 4. resolveSpawnModel: override > modelTier > model
const agents: AgentConfig[] = [
  { name: "fable-arch", description: "", modelTier: "Max", model: "anthropic/claude-fable-5-1", systemPrompt: "", source: "user", filePath: "" },
  { name: "go-expert", description: "", modelTier: "High", model: "anthropic/claude-sonnet-5", systemPrompt: "", source: "user", filePath: "" },
  { name: "concrete-only", description: "", model: "anthropic/claude-fable-5", systemPrompt: "", source: "user", filePath: "" },
];
check("resolve: workflow override wins over frontmatter", resolveSpawnModel({ agent: "go-expert", model: "Max", task: "" }, agents) === "Max");
check("resolve: falls back to modelTier", resolveSpawnModel({ agent: "fable-arch", task: "" }, agents) === "Max");
check("resolve: falls back to concrete model when no tier", resolveSpawnModel({ agent: "concrete-only", task: "" }, agents) === "anthropic/claude-fable-5");
check("resolve: unknown agent → undefined", resolveSpawnModel({ agent: "nope", task: "" }, agents) === undefined);
// 統合: fable-arch は frontmatter だけで fable 判定される(全モードカバーの肝)
check("integration: fable-arch detected via frontmatter tier",
  isFableModel(resolveSpawnModel({ agent: "fable-arch", task: "[fable-spot:x]" }, agents)));
check("integration: go-expert NOT detected (High tier)",
  !isFableModel(resolveSpawnModel({ agent: "go-expert", task: "" }, agents)));

// 5. consumeFableGrant e2e: 実 grant_consume を bash ブリッジで叩く(env 注入で SWARM_STATE_DIR
//    を隔離、グローバル process.env は変異させない)
const scriptsDir = path.resolve(import.meta.dir, "../../../../skills/swarm-implement/scripts");
const budgetGuard = path.join(scriptsDir, "budget-guard.sh");
if (fs.existsSync(budgetGuard)) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "fable-gate-e2e-"));
  const envIso = { SWARM_STATE_DIR: path.join(tmp, "st") };
  try {
    // 5a. インフラ障害(スクリプト dir 不在)→ fail-open(infra:true, ブロックしない)
    const infra = consumeFableGrant(path.join(tmp, "nonexistent-scripts"), "t-e2e", envIso);
    check("consume: missing scripts dir → infra=true (fail-open)", infra.infra === true && infra.consumed === null);

    // 5b. grant 未発行 → grant 無し(infra=false, consumed=null → block 対象)
    const noGrant = consumeFableGrant(scriptsDir, "t-e2e", envIso);
    check("consume: no grant issued → infra=false, consumed=null (block)", noGrant.infra === false && noGrant.consumed === null);

    // 5c. budget-guard.sh --fable で grant 発行
    const issue = spawnSync("bash", [budgetGuard, "--fable", "t-e2e", "--mission=e2e"], {
      encoding: "utf-8",
      env: { ...process.env, ...envIso },
    });
    check("consume: budget-guard --fable issued grant (exit 0)", issue.status === 0, issue.stderr || "");

    // 5d. 消費成功 → consumed に grant 名
    const ok = consumeFableGrant(scriptsDir, "t-e2e", envIso);
    check("consume: valid grant consumed", ok.infra === false && !!ok.consumed && ok.consumed!.endsWith("-t-e2e"));

    // 5e. 2 度目の消費は失敗(1 grant = 1 スポーン)
    const again = consumeFableGrant(scriptsDir, "t-e2e", envIso);
    check("consume: grant is single-use (second consume → null block)", again.infra === false && again.consumed === null);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
} else {
  console.log("skip: e2e consume (budget-guard.sh not found at expected path)");
}

console.log(`\nfable-gate: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
