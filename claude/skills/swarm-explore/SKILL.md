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
allowed-tools: [Read, Write, Grep, Glob, Bash, Agent, Workflow, Skill]
user-invocable: true
disable-model-invocation: false
---

# swarm-explore — Haiku 100 体分散探索

## 手順

1. **シャーディング** — 探索対象を列挙して N 分割する（コンテキストに全リストを展開しない）:

   ```bash
   ~/.claude/skills/swarm-explore/scripts/shard-targets.sh <repo-root> <shard数> <go|rust|docker|all>
   ```

   出力は JSON（シャードごとの `{dirs, weight}`。`weight` はそのシャードに含まれる対象ファイル数で、
   effort 静的ルーティングの基準になる）。シャード数の目安: パッケージ 300 超なら 50–100、それ以下なら 10–30。

2. **Workflow で Haiku 群をスポーン** — 必ず `model: 'haiku'`。**`effort` はモデルと独立にルーティングする**:
   シャードの `weight`（対象ファイル数）が閾値超なら要約すべき情報量が多く低 effort では欠落しやすいと
   見て `effort: 'medium'` から開始し、それ以外は `effort: 'low'`（コストメリットは小さいシャードで維持
   される）。さらに秘書が集約時に「findings が曖昧・矛盾・不自然に少ない」と判定したシャード
   （`low_quality_shards`）だけ、`effort` を 1 段階昇格して差分再探索し秘書がマージする
   （SWARM.md §3 の「再探索は差分入力で範囲を絞る」の具体化。全シャード再探索は行わない）。
   各エージェントは読み取り専用で、構造化 JSON のみを返す:

   ```js
   export const meta = {
     name: "swarm-explore",
     description: "Haiku fan-out exploration + Sonnet secretary aggregation",
     phases: [
       { title: "Explore" },
       { title: "Re-explore" },
       { title: "Aggregate" },
     ],
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
   const SECRETARY_OUT = {
     type: "object",
     required: ["report", "low_quality_shards"],
     properties: {
       report: { type: "string" },
       low_quality_shards: { type: "array", items: { type: "integer" } },
     },
   };
   // シャード当たり対象ファイル数の閾値。超えたら初回から effort:medium で探索する(暫定値、
   // shard-targets.sh のシャード数目安から逆算した平均規模のやや上に設定。運用実績で調整可)。
   const WEIGHT_THRESHOLD = 15;
   const effortFor = (weight) => (weight > WEIGHT_THRESHOLD ? "medium" : "low");
   const promote = (effort) =>
     effort === "low" ? "medium" : effort === "medium" ? "high" : effort;
   const exploreShard = (s, i, effort) =>
     agent(
       `読み取り専用で調査せよ。対象ディレクトリ: ${JSON.stringify(s.dirs)}\n質問: ${args.question}\n` +
         `編集禁止。事実のみを findings として返す。推測には severity=info を付ける。`,
       { label: `explore:${i}`, model: "haiku", effort, schema: FINDING },
     );

   phase("Explore");
   const shards = args.shards; // shard-targets.sh の出力: [{dirs, weight}, ...]
   const raw = await parallel(
     shards.map((s, i) => () => exploreShard(s, i, effortFor(s.weight))),
   );

   phase("Aggregate");
   const secretary = await agent(
     `あなたは秘書エージェント (swarm-secretary/SKILL.md の契約に従う)。以下の生レポート群に対し` +
       `「重複排除」「構造化」「依存関係に基づく優先順位づけ」のみを行え。新規調査・解釈の追加は禁止。` +
       `ノイズ (severity=info で裏取りのないもの) は除外。\n` +
       `各 finding に MAST 分類を付与せよ: 仕様・役割の不備なら design、複数エージェント間の前提のズレなら ` +
       `misalignment、テスト・検証の欠落なら verification。分類不能な事実報告は空欄でよい` +
       `（この分類が下流の swarm-loop CHECKPOINT・swarm-implement の判定ルーティングに使われる）。\n` +
       `加えて、各シャード(_shard 番号)の findings の具体性・密度を評価し、曖昧・矛盾・件数が` +
       `不自然に少ない等品質が低いと判断したシャード番号を low_quality_shards に列挙せよ` +
       `（新規調査はせず既存 findings の評価のみ。無ければ空配列でよい）。\n` +
       `report には以下の Markdown 形式に厳密に従った本文のみを格納すること（Priority Queue の各行に mast 列を含める）:\n` +
       `# Secretary Report: <ミッション名>\n\n## Stats\n- input findings: N / after dedup: M / dropped as noise: K\n\n` +
       `## Priority Queue（依存上流 → 下流、severity 降順）\n\n` +
       `| # | file:line | severity | mast | summary | depends_on | sources |\n|---|---|---|---|---|---|---|\n\n` +
       `## Root Causes（複数 findings を説明する共通原因）\n- ...\n\n` +
       `## Unverified（判断保留 — 人間または Checker の裏取りが必要）\n- ...\n\n` +
       `対象生レポート（各要素の _shard がシャード番号）:\n` +
       JSON.stringify(raw.filter(Boolean).map((r, i) => ({ ...r, _shard: i }))),
     { label: "secretary", model: "sonnet", schema: SECRETARY_OUT },
   );

   let report = secretary.report;
   const retryTargets = secretary.low_quality_shards.filter((i) => shards[i]);
   if (retryTargets.length > 0) {
     phase("Re-explore");
     log(
       `品質不足と判定されたシャード ${retryTargets.length} 件を effort 昇格の上で再探索`,
     );
     const retried = await parallel(
       retryTargets.map(
         (i) => () =>
           exploreShard(shards[i], i, promote(effortFor(shards[i].weight))),
       ),
     );
     phase("Aggregate");
     report = await agent(
       `以下は既存の Secretary Report(Markdown) と、品質不足のため effort を昇格して再探索した` +
         `追加の生レポートである。追加レポートの内容を既存レポートへ統合せよ` +
         `（重複排除・優先順位づけのルールは変えない）。新規調査は禁止。更新後の Markdown 全文のみを返せ。\n` +
         `既存レポート:\n${report}\n\n追加生レポート:\n${JSON.stringify(retried.filter(Boolean))}`,
       { label: "secretary-merge", model: "sonnet" },
     );
   }

   return {
     report,
     shard_count: shards.length,
     dropped: raw.filter((r) => !r).length,
     reexplored_shards: retryTargets.length,
   };
   ```

3. **予算ガード** — `budget.total` が設定されている場合は `while`/`map` の前に `budget.remaining()` を確認。探索途中で予算が尽きたら `log()` で欠損シャードを明示する（silent truncation 禁止）。再探索(Re-explore)フェーズも同じ budget を消費するため、`retryTargets` を切り出す前に `budget.remaining()` を確認し、不足時は再探索をスキップして `low_quality_shards` を `report` の `## Unverified` 相当として明示する。

4. **報告** — 秘書レポートのみを人間・上位層へ提示する。生ログは提示しない。実装に進む場合は `swarm-implement` に秘書レポートを渡す。

## 禁止事項

- Haiku エージェントへの Edit/Write 権限付与
- 生ログの直接転送（トークン浪費・ノイズ混入）
- 同一ミッション内での無計画な再探索（差分入力で範囲を絞ること）。秘書判定による
  `low_quality_shards` の再探索は対象シャード限定・1 回のみの例外であり、この禁止事項には当たらない
- 秘書判定に依らない一律の effort 引き上げ（`WEIGHT_THRESHOLD` 経由の静的ルーティングと
  `low_quality_shards` 経由の限定昇格以外で全シャードの effort を底上げしない — コストメリットを失うため）

## Memory Protocol（Skill 自己メンテナンス）

開始前に `~/.claude/skill-memory/swarm-explore/MEMORY.md` が存在すれば読み、対象リポジトリ・ドメイン別に
有効だった `WEIGHT_THRESHOLD` の実測値や、`low_quality_shards` が頻発するシャード種別（言語・ディレクトリ）
の傾向を踏まえて `shard-targets.sh` の呼び出し方・effort ルーティングの判断材料にする。存在しなければ
気にせず進めてよい。

完了時、今回のミッション固有の詳細ではなく今後の探索一般に通用する知見（閾値の妥当な調整値、特定
リポジトリでの Haiku 誤検知の傾向等）が得られた場合のみ、`~/.claude/skill-memory/swarm-explore/`
（無ければ作成）の `MEMORY.md` に簡潔に追記する。既存内容と重複するものは追記しない。一般化可能な
学びが無ければ何も書かずに終える。
