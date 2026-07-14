---
name: swarm-explore
description: >-
  Swarm 層 (Haiku) による大規模分散探索。トリガー: 「全域調査」「swarm 探索」「コードベース全体を調べて」
  「golangci-lint のエラーを一括解析」「大量のログを解析」「関連論文・文献を調べて」など、
  単一コンテキストに収まらない横断探索・大量ログ解析・広域サーベイが必要なとき。
  境界条件: 単一ファイルの読解、既知箇所のピンポイント調査、数ファイル程度の修正には使わない
  (通常の Read/Grep/graphify で足りる)。本 skill は読み取り専用フェーズであり、コード編集は一切行わない。
  結果は必ず swarm-secretary で集約してから報告する (Haiku の生ログを直接上位へ流さない)。
  対象は主に vdaas/vald と kpango/dotfiles。Haiku 100 体探索は 1 ミッション原則 1 回。
allowed-tools: [Read, Grep, Glob, Bash, Agent, Workflow, Skill]
user-invocable: true
disable-model-invocation: false
---

# swarm-explore — Haiku 100 体分散探索

## 手順

1. **シャーディング** — 探索対象を列挙して N 分割する（コンテキストに全リストを展開しない）:

   ```bash
   ~/.claude/skills/swarm-explore/scripts/shard-targets.sh <repo-root> <shard数> <go|rust|docker|all>
   ```

   出力は JSON（シャードごとのディレクトリ配列）。シャード数の目安: パッケージ 300 超なら 50–100、それ以下なら 10–30。

2. **Workflow で Haiku 群をスポーン** — 必ず `model: 'haiku'`、`effort: 'low'`。各エージェントは読み取り専用で、構造化 JSON のみを返す:

   ```js
   export const meta = {
     name: "swarm-explore",
     description: "Haiku fan-out exploration + Sonnet secretary aggregation",
     phases: [{ title: "Explore" }, { title: "Aggregate" }],
   };
   const FINDING = {
     type: "object",
     required: ["findings"],
     properties: {
       findings: {
         type: "array",
         items: {
           type: "object",
           required: ["file", "summary", "severity"],
           properties: {
             file: { type: "string" },
             line: { type: "integer" },
             summary: { type: "string" },
             severity: { enum: ["critical", "high", "medium", "low", "info"] },
             depends_on: { type: "array", items: { type: "string" } },
           },
         },
       },
     },
   };
   phase("Explore");
   const shards = args.shards; // shard-targets.sh の出力
   const raw = await parallel(
     shards.map(
       (s, i) => () =>
         agent(
           `読み取り専用で調査せよ。対象ディレクトリ: ${JSON.stringify(s)}\n質問: ${args.question}\n` +
             `編集禁止。事実のみを findings として返す。推測には severity=info を付ける。`,
           {
             label: `explore:${i}`,
             model: "haiku",
             effort: "low",
             schema: FINDING,
           },
         ),
     ),
   );
   phase("Aggregate");
   const secretary = await agent(
     `あなたは秘書エージェント (swarm-secretary/SKILL.md の契約に従う)。以下の生レポート群に対し` +
       `「重複排除」「構造化」「依存関係に基づく優先順位づけ」のみを行え。新規調査・解釈の追加は禁止。` +
       `ノイズ (severity=info で裏取りのないもの) は除外。\n` +
       `各 finding に MAST 分類を付与せよ: 仕様・役割の不備なら design、複数エージェント間の前提のズレなら ` +
       `misalignment、テスト・検証の欠落なら verification。分類不能な事実報告は空欄でよい` +
       `（この分類が下流の swarm-loop CHECKPOINT・swarm-implement の判定ルーティングに使われる）。\n` +
       `出力は以下の Markdown 形式に厳密に従うこと（Priority Queue の各行に mast 列を含める）:\n` +
       `# Secretary Report: <ミッション名>\n\n## Stats\n- input findings: N / after dedup: M / dropped as noise: K\n\n` +
       `## Priority Queue（依存上流 → 下流、severity 降順）\n\n` +
       `| # | file:line | severity | mast | summary | depends_on | sources |\n|---|---|---|---|---|---|---|\n\n` +
       `## Root Causes（複数 findings を説明する共通原因）\n- ...\n\n` +
       `## Unverified（判断保留 — 人間または Checker の裏取りが必要）\n- ...\n\n` +
       `対象生レポート:\n` +
       JSON.stringify(raw.filter(Boolean)),
     { label: "secretary", model: "sonnet" },
   );
   return {
     report: secretary,
     shard_count: shards.length,
     dropped: raw.filter((r) => !r).length,
   };
   ```

3. **予算ガード** — `budget.total` が設定されている場合は `while`/`map` の前に `budget.remaining()` を確認。探索途中で予算が尽きたら `log()` で欠損シャードを明示する（silent truncation 禁止）。

4. **報告** — 秘書レポートのみを人間・上位層へ提示する。生ログは提示しない。実装に進む場合は `swarm-implement` に秘書レポートを渡す。

## 禁止事項

- Haiku エージェントへの Edit/Write 権限付与
- 生ログの直接転送（トークン浪費・ノイズ混入）
- 同一ミッション内での無計画な再探索（差分入力で範囲を絞ること）
