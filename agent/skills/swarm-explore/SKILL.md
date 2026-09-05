---
name: swarm-explore
description: >-
  Swarm 層 (Low tier / Haiku) による大規模分散探索。トリガー: 「全域調査」「swarm 探索」「コードベース全体を調べて」
  「golangci-lint のエラーを一括解析」「大量のログを解析」「関連論文・文献を調べて」など、
  単一コンテキストに収まらない横断探索・大量ログ解析・広域サーベイが必要なとき。
  境界条件: 単一ファイルの読解、既知箇所のピンポイント調査、数ファイル程度の修正には使わない
  (通常の Read/Grep/graphify で足りる)。本 skill は読み取り専用フェーズであり、コード編集は一切行わない。
  結果は必ず swarm-secretary で集約してから報告する (探索群の生ログを直接上位へ流さない)。
  対象は主に vdaas/vald と kpango/dotfiles。大規模探索は 1 ミッション原則 1 回。
allowed-tools: [Read, Write, Grep, Glob, Bash, Agent, Workflow, Skill]
user-invocable: true
disable-model-invocation: false
---

# swarm-explore — Swarm層 (Low tier / Haiku 100 体) 分散探索

開始前に `~/.claude/SWARM.md` を Read する（CLAUDE.md の常時 import ではなく本 skill が個別に
読み込む設計。統治規約・verifier 独立性原則・MAST 分類等、本 skill 全体の前提はそこにある）。

## 手順

1. **シャーディング** — 探索対象を列挙して N 分割する（コンテキストに全リストを展開しない）:

   ```bash
   ~/.claude/skills/swarm-explore/scripts/shard-targets.sh <repo-root> <shard数> <go|rust|docker|all>
   ```

   出力は JSON（シャードごとの `{dirs, weight}`。`weight` はそのシャードに含まれる対象ファイル数で、
   effort 静的ルーティングの基準になる）。シャード数の目安: パッケージ 300 超なら 50–100、それ以下なら 10–30。

2. **Workflow で Low tier (Haiku / Flash-Lite / GPT-4o-mini) 群をスポーン** — 必ず `model: 'Low'`（Claude Code環境では `model: 'haiku'` でも可）。**`effort` はモデルと独立にルーティングする**
   （閾値・昇格ロジックの詳細はコード内 `WEIGHT_THRESHOLD` 定義付近のコメント参照）。
   各エージェントは読み取り専用で、構造化 JSON のみを返す:

   ```js
   export const meta = {
     name: "swarm-explore",
     description: "Haiku fan-out exploration + Sonnet secretary aggregation",
     phases: [
       { title: "Explore" },
       { title: "Re-explore" },
       { title: "Aggregate" },
       { title: "Refute" },
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
       // 同調性対策(SWARM_REFERENCES.md参照): secretary の責務6で抽出された、複数shardが
       // 一致したが証拠が薄い finding の反証候補。無ければ省略可(required に含めない)。
       verify_candidates: {
         type: "array",
         items: {
           type: "object",
           required: ["file", "summary"],
           properties: {
             file: { type: "string" },
             line: { type: "integer" },
             summary: { type: "string" },
           },
         },
       },
     },
   };
   const VERDICT = {
     type: "object",
     required: ["confirmed", "reason"],
     properties: {
       confirmed: { type: "boolean" },
       reason: { type: "string" },
     },
   };
   // シャード当たり対象ファイル数の閾値。超えたら初回から effort:medium で探索する(暫定値、
   // shard-targets.sh のシャード数目安から逆算した平均規模のやや上に設定。運用実績で調整可)。
   // 閾値以下は effort:low を維持しコストメリットを保つ。さらに秘書が集約時に「findings が曖昧・
   // 矛盾・不自然に少ない」と判定したシャード(low_quality_shards)だけ 1 段階昇格して差分再探索する
   // (SWARM.md §3「再探索は差分入力で範囲を絞る」の具体化。全シャード再探索は行わない)。
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
   const failedShards = raw
     .map((r, i) => (r ? null : i))
     .filter((i) => i !== null);
   if (failedShards.length > 0) {
     log(`探索失敗のため除外したシャード index: ${failedShards.join(", ")}`);
   }
   // _shard は元の shards インデックスをそのまま保持する(filter 後に再採番すると
   // low_quality_shards / retryTargets の shards[i] 参照とずれるため禁止)。
   const tagged = raw
     .map((r, i) => (r ? { ...r, _shard: i } : null))
     .filter(Boolean);

   phase("Aggregate");
   const secretaryPrompt = (items) =>
     `あなたは秘書エージェント。swarm-secretary/SKILL.md の契約（責務・出力フォーマット・禁止事項）に` +
     `厳密に従い、以下の生レポート群を処理せよ（MAST 分類・low_quality_shards 判定を含む）。\n` +
     `対象生レポート（各要素の _shard がシャード番号）:\n` +
     JSON.stringify(items);
   // shard数が閾値を超える場合、再探索フェーズと同じincremental mergeパターンで初回Aggregateも
   // 分割実行する(1回の秘書呼び出しに数百~数千件のJSON findingsが載る"lost in the middle"リスクを
   // 下げつつtoken消費を分散する。arXiv:2604.11753(2026-04、単一preprint・adversarial検証未確認)の
   // AggAgent: ツールベースの選択的検査による段階的集約はK=8で全文要約ベースに対し集約オーバーヘッドを
   // 41%から5.7%に削減したと報告)。
   const AGG_CHUNK = 25;
   let secretary;
   if (tagged.length <= AGG_CHUNK) {
     secretary = await agent(secretaryPrompt(tagged), {
       label: "secretary",
       model: "sonnet",
       schema: SECRETARY_OUT,
     });
   } else {
     const chunks = [];
     for (let i = 0; i < tagged.length; i += AGG_CHUNK)
       chunks.push(tagged.slice(i, i + AGG_CHUNK));
     const merged = await agent(secretaryPrompt(chunks[0]), {
       label: "secretary:0",
       model: "sonnet",
       schema: SECRETARY_OUT,
     });
     for (let i = 1; i < chunks.length; i++) {
       const partial = await agent(secretaryPrompt(chunks[i]), {
         label: `secretary:${i}`,
         model: "sonnet",
         schema: SECRETARY_OUT,
       });
       merged.report = await agent(
         `以下は既存の Secretary Report(Markdown) と追加shardの秘書レポートである。統合せよ` +
           `（swarm-secretary/SKILL.md の契約(重複排除・優先順位づけ)は変えない）。新規調査は禁止。\n` +
           `既存:\n${merged.report}\n\n追加:\n${partial.report}`,
         { label: `secretary-merge:${i}`, model: "sonnet" },
       );
       merged.low_quality_shards = merged.low_quality_shards.concat(
         partial.low_quality_shards,
       );
       merged.verify_candidates = (merged.verify_candidates || []).concat(
         partial.verify_candidates || [],
       );
     }
     secretary = merged;
   }

   let report = secretary.report;
   const retryTargets = secretary.low_quality_shards.filter((i) => shards[i]);
   const canReexplore =
     retryTargets.length > 0 && (!budget.total || budget.remaining() > 0);
   if (canReexplore) {
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
     // secretary-merge は schema 指定なしの 1 pass 自由形式マージ。low_quality_shards の再評価は
     // 行わない設計(再評価が必要なら swarm-explore を再度呼び出すこと)。
     report = await agent(
       `以下は既存の Secretary Report(Markdown) と、品質不足のため effort を昇格して再探索した` +
         `追加の生レポートである。追加レポートの内容を既存レポートへ統合せよ` +
         `（swarm-secretary/SKILL.md の契約(重複排除・優先順位づけ)は変えない）。新規調査は禁止。` +
         `更新後の Markdown 全文のみを返せ。\n` +
         `既存レポート:\n${report}\n\n追加生レポート:\n${JSON.stringify(retried.filter(Boolean))}`,
       { label: "secretary-merge", model: "sonnet" },
     );
   } else if (retryTargets.length > 0) {
     log(
       `budget 不足のため再探索をスキップ。low_quality_shards ${retryTargets.join(", ")} は report の Unverified 扱い`,
     );
   }

   // 同調性対策(SWARM_REFERENCES.md参照): secretary が抽出した検証候補(証拠が薄いのに複数shardが
   // 一致した finding)を、元の指摘文を伏せた反証プロンプトで独立に再検証する。全shard再探索ではなく
   // 該当 finding 単体の反証なのでコストは有界(上位3件まで)。
   const toVerify = (secretary.verify_candidates || []).slice(0, 3);
   if (toVerify.length > 0 && (!budget.total || budget.remaining() > 0)) {
     phase("Refute");
     const verdicts = await parallel(
       toVerify.map(
         (c) => () =>
           agent(
             `以下の指摘を独立に検証せよ。指摘の出所や結論は伏せてある(先入観バイアス回避のため)。\n` +
               `対象: ${c.file}${c.line ? ":" + c.line : ""}\n` +
               `まず該当箇所を実際に読み、指摘の趣旨「${c.summary}」が事実として成立するか反証を試みよ。\n` +
               `編集禁止。confirmed(事実として成立するなら true)と reason のみを返せ。`,
             { label: `refute:${c.file}`, model: "haiku", schema: VERDICT },
           ),
       ),
     );
     report +=
       "\n\n## Refutation（同調性対策・自動反証）\n\n" +
       verdicts
         .map((v, i) =>
           v
             ? `- ${toVerify[i].file}: confirmed=${v.confirmed} — ${v.reason}`
             : `- ${toVerify[i].file}: 検証失敗（エージェント異常終了）`,
         )
         .join("\n");
   } else if ((secretary.verify_candidates || []).length > 3) {
     log(
       `verify_candidates ${secretary.verify_candidates.length} 件中上位 3 件のみ反証。残りは Priority Queue の caveat 表示のまま`,
     );
   }

   return {
     report,
     shard_count: shards.length,
     dropped: failedShards.length,
     reexplored_shards: canReexplore ? retryTargets.length : 0,
     refuted: toVerify.length,
   };
   ```

3. **予算ガード** — `budget.total` が設定されている場合は `while`/`map` の前に `budget.remaining()` を確認。探索途中で予算が尽きたら `log()` で欠損シャードを明示する（silent truncation 禁止、上記コード例の `failedShards` 参照）。再探索(Re-explore)フェーズも同じ budget を消費するため、`retryTargets` を切り出す前に `budget.remaining()` を確認し（上記コード例の `canReexplore`）、不足時は再探索をスキップして `low_quality_shards` を `report` の `## Unverified` 相当として明示する。反証(Refute)フェーズも同じ budget を共有し、`verify_candidates` は上位 3 件のみを対象とする（上記コード例の `toVerify`）。予算不足または 3 件超過のいずれでも `log()` で明示し、超過分は Priority Queue の caveat 表示のまま据え置く。

4. **報告** — 秘書レポートのみを人間・上位層へ提示する。生ログは提示しない。実装に進む場合は `swarm-implement` に秘書レポートを渡す。

## 既知の限界（2026-08-26 実測・WebSearch可用性）

Web/SNS文献調査（`WebSearch`を使うシャード）を並列fan-outすると、シャードの一部がWebSearch呼び出し
不能（空またはツール未使用の推論のみのfindings）に劣化する事例が実測された（56シャード中、シャード
#20 以降の 36 件・64%）。原因は `~/.claude/.credentials.json` に `claudeAiOauth` キーがある場合
（Claude.ai OAuthサブスクリプション認証、`ANTHROPIC_API_KEY` 等のAPIキー認証ではない）に起きる
WebSearch内部呼び出しの429エラーと一致する挙動であり、同一症状を報告した issue
（GitHub `anthropics/claude-code#27074`、2026-03-16 に `completed` でクローズ済み）と症状は一致するが、
修正後の再発か別原因かは未特定（公式ドキュメントに明記された挙動ではないため確度は中程度に留める。
Haiku シャード自身が自己申告する「WebSearch予算200/200枯渇」等の具体的な原因説明は未検証・裏付けなしの
ため信用しない — 実際に observed される事実は「WebSearch呼び出しが失敗する」ことのみ）。

- **判定**: `~/.claude/.credentials.json`（Claude Code 自身の生 OAuth トークンストア）へは
  agent が直接コマンドを実行しない。この節の対処は認証方式の自己診断を前提とせず、後述の
  「実測ベースの上限目安」だけで判断する。認証方式の切り分けがどうしても必要な場合は人間に確認を
  依頼すること（agent 自身が `.credentials.json` を対象に Bash を実行する運用は、コマンド改変・
  グロブ展開等で技術的な防御をすり抜けやすく、繰り返しレビューで安全な実行手順を維持できないと
  判断した）。
- **対処**: 実測では 32 シャード規模で 220 件のソース収集に成功した一方、56 シャード規模ではシャード
  #20（21体目）以降で劣化が始まった。「シャード数の単一閾値」は成功実績（32）と劣化開始点（#20）の
  両方と矛盾するため未確定 — 現時点では成功実績のある **32 シャード程度を上限目安**とし、それを超える
  規模が必要な場合は `WebSearch` 中心のシャードを増やすより既知URL（過去の秘書レポート・公式ドキュメント
  の既知パス）への `WebFetch` を中心にした設計へ切り替える方が安定すると考えられる（ただし実測したのは
  Workflow によるシャード fan-out ではなく、単一セッションでの直接 `WebFetch` 再調査であり、
  `WebFetch` 中心の**シャード設計**自体の収集量はまだ測定していない。シャード化した場合の安定性は
  未検証のまま推奨している点に留意）。

## Workflow規模監視の注意（WebSearch可用性とは別のメカニズム）

`Workflow` ツール自体にも `workflowSizeGuideline`（既定 `medium` = 15 agent未満が目安、50 agent未満は
`large`。本環境の `settings.json` は本キー未設定のため既定 `medium` が有効 — 出典:
`code.claude.com/docs/en/settings-reference`）が存在する。`skipWorkflowUsageWarning: true`
の環境でこの目安超過時のUI警告が非表示になるという挙動は、公式ドキュメント該当ページに明記が
見当たらず**未確認**（2026-08-26時点）。大規模fan-outを設計する際は`/workflows`のUI警告に頼らず、
タスク完了通知に実測で含まれる `subagent_tokens` を直接確認して規模を把握すること
（出典: 2026-08-26のタスク完了通知の実測）。

## 禁止事項

- Haiku エージェントへの Edit/Write 権限付与
- 生ログの直接転送（トークン浪費・ノイズ混入）
- 同一ミッション内での無計画な再探索（差分入力で範囲を絞ること）。秘書判定による
  `low_quality_shards` の再探索は対象シャード限定・1 回のみの例外であり、この禁止事項には当たらない
- 秘書判定に依らない一律の effort 引き上げ（`WEIGHT_THRESHOLD` 経由の静的ルーティングと
  `low_quality_shards` 経由の限定昇格以外で全シャードの effort を底上げしない — コストメリットを失うため）

## Memory Protocol（Skill 自己メンテナンス）

開始前に `~/.claude/skill-memory/swarm-explore/MEMORY.md` があれば読み、`WEIGHT_THRESHOLD` の実測値や
`low_quality_shards` が頻発するシャード種別の傾向を `shard-targets.sh` 呼び出し・effort ルーティングの
判断材料にする（無ければ気にせず進める）。

完了時、今回のミッション固有の詳細ではなく今後の探索一般に通用する知見（閾値の妥当な調整値、特定
リポジトリでの Haiku 誤検知の傾向等）が得られた場合のみ、`~/.claude/skill-memory/swarm-explore/`
（無ければ作成）の `MEMORY.md` に簡潔に追記する。既存内容と重複するものは追記しない。一般化可能な
学びが無ければ何も書かずに終える。
