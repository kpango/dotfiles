---
name: swarm-implement
description: >-
  実装・検証層の Maker/Checker 分離ループ。トリガー: 「実装して」「修正して」「このレポートを実装に落として」
  「秘書レポートの Priority Queue を消化して」など、vdaas/vald または kpango/dotfiles でのコード変更タスク全般。
  境界条件: アーキテクチャレベルの意思決定が未確定なら先に人間へ /swarm-architect の招集を要請する。
  マージ・デプロイ・破壊的変更は本 skill では行わず swarm-release-gate へ引き継ぐ。
  並列実装 (2 タスク以上同時) は worktree 隔離必須。1 タスクの修正ループは最大 5 試行（3 試行目・Permanent
  エラー・失敗シグネチャ 2 回連続一致のいずれか早い方で Fixer へ切替）で、超過時は @fix_plan.md に状況を
  書き出して停止し人間へ報告する。
allowed-tools:
  [
    Read,
    Edit,
    Write,
    Bash,
    Grep,
    Glob,
    Agent,
    Workflow,
    Skill,
    SendMessage,
    TaskCreate,
    TaskUpdate,
    TaskList,
  ]
user-invocable: true
disable-model-invocation: false
---

# swarm-implement — Maker/Checker 分離実装ループ

開始前に `~/.claude/SWARM.md` を Read する（CLAUDE.md の常時 import ではなく本 skill が個別に
読み込む設計。統治規約・verifier 独立性原則・MAST 分類等、本 skill 全体の前提はそこにある）。

設計根拠（verifier 独立性の限界・討論禁止・3 試行目ソフトチェックポイント等）は `SWARM.md` §2・§3
および `SWARM_REFERENCES.md` を参照。本 skill のループは Plan（PLAN フェーズ）→ Action（Maker）→
Observe（実挙動の観察）→ Verify（Checker・並行レビュー・決定論的検証）のサイクルであり、静的検証
だけでなく実際に動かして観察する Observe を独立ステップとして持つ。

## 前提（開始前に必ず実施）

1. 軌跡ログ（`swarm-implement/scripts/agents-log-lib.sh` が返すパス）と `@fix_plan.md` を読む —
   同一エラーへの同一対処の繰り返しを防ぐ。
   同一根本原因の学びが 2 回目に登場していたら、それが機械化チェック（hook/lint/test）に昇格済みか確認する
   （SWARM.md §5）。未昇格なら、実装より先にその機械化を行う。
2. タスクが 2 件以上並列なら、タスクごとに worktree を割り当てる:

   ```bash
   ~/.claude/skills/swarm-implement/scripts/worktree-alloc.sh <task-slug>   # 出力 = worktree パス
   ```

3. タスクごとに一意な task-id（例: `vald-fix-agent-ngt-20260713`）を決める。
4. この試行ループ内で起動する `Agent` tool呼び出し（Test Maker / Maker / 並行レビュー / Fixer、いずれも
   同一 task-id）の prompt に `[parallel-task:<task-id>]` マーカーを含める（`swarm-parallel-gate.sh`
   フックが SWARM.md §1「最大 3 並列」を機械強制するための束縛。同一 task-id の再スポーンはスロット
   1 個分のまま継続扱いになる）。4 タスク目以降が `PARALLEL_LIMIT_EXCEEDED` で拒否された場合は、
   他タスクの完了（下記「完了処理」の `~/.claude/skills/swarm-implement/scripts/parallel-gate.sh
--release`）を待つ。**Checker は `Workflow` tool で起動するため本マーカー・当該hookの対象外**
   （`swarm-parallel-gate.sh`/`swarm-fable-gate.sh`はいずれも`PreToolUse:Task|Agent`にのみ配線され
   `Workflow`呼び出しは検査しない — `claude/settings.json`のmatcher実測で確認済み。実害の有無・
   既知の残課題は SWARM.md §1「並列数上限の機械強制」参照、ここでは再掲しない）。

## 複雑度ガード（実行方式の決定）

Maker を起動する前に、まずタスクをこの表で分類する。**trivial なタスクに Maker/Checker のフル分離を
起動しない**（オーバーヘッドがメリットを上回る。`swarm-loop` の Quick モードは基本的にここが trivial/simple）:

| 複雑度     | 判定基準                                                              | 実行方式                                                                                     | TDAD     | Maker/Checker effort       |
| ---------- | --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- | -------- | -------------------------- |
| `trivial`  | 1 ファイル・15 行以下・新規ロジックなし（設定変更・定数・リネーム等） | オーケストレーター（呼び出し元）が直接編集し、Stop/PostToolUse hook の検証のみで完了         | 不要     | —（Maker/Checker起動なし） |
| `simple`   | 30 行以下・1 関数変更・既存パターン踏襲                               | Maker(sonnet) 単体 + 軽量 Checker（1 回判定、並行レビューは省略可）                          | 任意     | medium                     |
| `standard` | 複数ファイル or 新規ロジック導入                                      | フル Maker/Checker 分離（本セクション以下の手順どおり）                                      | **必須** | high                       |
| `complex`  | 複数システム or 新規抽象化 or アルゴリズム設計                        | フル Maker/Checker 分離＋着手前に実装計画のみ書かせて承認を得る（下記 complex 計画レビュー） | **必須** | xhigh                      |

`effort` はモデルと独立にルーティングする軸である（SWARM.md §1「Swarm 層は effort もモデルと独立に
ルーティングする」の原則を Maker/Checker 層にも適用する）。`simple` での過剰な thinking token 消費を
抑え、`complex`（verifier 失敗コストが最も高い局面）で `xhigh` を明示的に使う。Agent 呼び出し時に
`effort` を省略するとセッション既定に委ねられ、この使い分けが効かない点に注意する。

実行中に当初判定より複雑度が高いと判明した場合（例: `simple` で着手したが複数ファイル変更や新規ロジック
導入が必要と分かった）は、判定は昇格のみとし（`swarm-loop` Phase -1 の SCALE 判定と同じ原則。安全側に倒す）、
その時点で当該複雑度に必要な手順（Test Maker の追加起動・並行レビューの追加等、未実施のもの）へ直ちに
切り替えてから試行を継続する。降格（複雑度を下げる）は行わない。

`complex` の計画承認は、Fable スポット計画レビュー（SWARM.md §1 スポット判断層・トリガー 3）を第一候補と
する: `budget-guard.sh --fable <task-id> --mission=<slug>` が許可すれば `swarm-architect` スポット診断
モードで実装計画をレビューさせる。`FABLE_BUDGET_EXCEEDED` の場合は従来どおり人間（Interactive）または
Checker(opus)（Mission）の承認にフォールバックする。

`standard`/`complex` では以下の **TDAD Iron Law** を適用する: 本番コードを書く前に失敗するテストを書く。
テストなしに本番コードを書いたら削除して最初からやり直す。例外なし。RED → Verify RED → GREEN →
Verify GREEN → REFACTOR → Coverage 80%+ の順を踏む（下記 Step 0 の Test Maker が RED を担当）。
タスク記述は `task-template.md`（本ディレクトリ）を参照する。RED/GREEN/REFACTOR 各段階での git
checkpoint コマンド例・言語別カバレッジ計測コマンド・共通 Output Schema を定義済み。

## ループ（1 試行 = 以下の 1 周、最大 5 試行・3 試行目でソフトチェックポイント）

各試行の頭で予算を消費する:

```bash
~/.claude/skills/swarm-implement/scripts/budget-guard.sh <task-id>
# 第2引数は省略し fable-budget.conf の BUDGET_TASK_MAX_DEFAULT(既定5)に委ねる(単一ソース原則、SWARM.md §3)
# exit 1 (BUDGET_EXCEEDED) なら即停止 → @fix_plan.md に軌跡を書き出して人間へ報告
```

0. **Test Maker（`standard`/`complex` は必須、`simple` は任意、`trivial` はスキップ）** — Code Maker より先に
   独立スポーンして**テストケースだけ**を table-driven（golang-testing / rust-testing / python-testing skill
   準拠）で先行記述させる（実装させない・TDAD の RED を担当）。これにより秘書レポートの仕様の曖昧さを
   実装前に顕在化させる（MAST (i)(ii) 対策）。テストで機械判定不能なタスク（定型的な設定変更・ドキュメント
   更新等）は複雑度に関わらずスキップしてよい。
1. **Maker (`model: High` / `model: sonnet`)** — Agent で独立スポーン。入力は秘書レポートの該当項目＋仕様（＋ Test Maker が
   いれば先行テスト）のみ。
   - vald: 既存 make ターゲット経由でのみビルド・生成（Vald Law 遵守。hooks が強制）。
   - dotfiles: `.hadolint.yaml` の ignored ルールを尊重。インストールは make ターゲット経由。
   - 出力: 変更 diff の要約・**自己評価と自信度（high/medium/low）**・実行した検証コマンドの**生の標準出力**。
     「テストが通りました」等の prose のみの申告は evidence として無効（fail-plausible 対策。SWARM.md §6）。
   - **禁止**: テストが失敗するからといってアサーション・許容誤差・スキップ指定を弱める/削除することでグリーン化
     すること。それは failure を隠蔽しただけで解決していない（データの完全性。SWARM.md §6）。テスト自体の修正が
     必要な場合は「なぜテストの期待値が誤っていたか」を Checker に説明できる根拠を添える。**残課題**: 本禁止事項
     を検出する hook/lint は現状無く、Checker の diff レビューという人間的判断のみに依存している（機械化は
     未着手・SWARM.md §5 の 3 段階モデルにはまだ到達していない）。
   - `standard`/`complex` タスクでは新規コードのカバレッジ 80%+ を目安にする（TDAD の REFACTOR 完了条件）。
   - **Checker起動前のsilent-stall検査**: Maker起動直前に記録した worktree の HEAD
     （`git -C <worktree> rev-parse HEAD`）と比較し、Checker起動時点で HEAD が変化済み、または
     `git -C <worktree> status --porcelain` が非空のいずれかを満たすことを確認する（TDAD Iron Law は
     各段階で commit するため、単純な `git diff --stat` の空判定は正しく完遂したタスクを誤検知する。
     HEAD比較+作業ツリー差分のOR判定であればcommit有無に関わらず実際の変更を検出できる）。両方が偽
     （HEAD不変かつ作業ツリークリーン）の場合、Makerが実際には何も変更しなかった可能性が高く
     （spawned信号のみの停滞という既知のパターン）、
     Checkerへ空の差分を渡さず、まず `SendMessage` でMakerへ実行結果を再要求する（再スポーンしない、
     完了済みエージェントはresumeされ文脈を保てる。同種の停滞対応は本SKILL.md「idle_notificationのみの
     停滞への対応」既述と同型）。再要求でも変化がないままなら Permanent エラーとして扱い Fixerへ
     即座に切り替える。
2. **Checker (`model: XHigh` / `model: opus`)** — Maker とは**独立コンテキスト**で `Workflow` tool起動（下記「判定の
   schema強制」参照。`Agent` toolには`schema`パラメータが無いため）。入力は「仕様＋ `git diff`」
   のみ（Maker の自己評価・自信度・言い分は渡さない）。**帰結非開示**: 現在の試行回数・残予算・
   Fixer切替までの近さ・ESCALATE接近度も伝えない（stakes signalingで判定が甘くなり、かつCoT検査でも
   検出不能との報告がある — arXiv:2604.15224, confirmed, ΔV=-9.8pp）。
   - プロンプトは反証指向:「この diff が仕様を満たさないケース・壊すケースを探せ。不確かなら不合格とせよ」。
   - **討論させない**: Checker の判定は 1 回で確定させる。不合格なら理由を返し、Maker への再指示は次試行として
     ループを回す（Checker コンテキスト内で Maker と往復させない — debate はバイアスを増幅させる、SWARM.md §2）。
   - 判定は必ず MAST 3 分類のどれに当たるかを添えさせる: system design issue / inter-agent misalignment /
     task verification failure。分類が (i)(ii) なら `swarm-secretary` の仕様構造化や `swarm-architect` 招集の
     要否を CHECKPOINT に伝える（Checker を強化するだけでは直らないカテゴリのため）。
   - 合格判定は Checker のみが出せる。Maker の「完了しました」は判定材料にしない。
   - **判定のschema強制（Checkerのみ）**: `Agent` tool自体の定義に`schema`パラメータは含まれない
     （Claude Codeホスト側のツール仕様であり、SKILL.md記述では変更不可）。Checkerは`Workflow` tool（1
     `agent()`呼び出しのみの単発スクリプト）で起動し、
     `schema: CHECKER_VERDICT`を指定する（このスクリプト例は`Workflow` tool自身の実行契約に従う
     疑似コードであり、`export const meta`はホスト側がリテラルとして抽出し、残りの本体は非同期実行
     コンテキストで評価される — 単独の`.js`ファイルとしてそのままparseすることは意図しない。同型の例は
     `swarm-explore/SKILL.md`のWorkflowスクリプト参照）:

     ```js
     export const meta = {
       name: "swarm-implement-checker",
       description:
         "Checker 判定を CHECKER_VERDICT schema で強制する単発 Workflow",
       phases: [{ title: "Verify" }],
     };
     const CHECKER_VERDICT = {
       type: "object",
       required: ["verdict", "mast_category", "reason"],
       properties: {
         verdict: { enum: ["PASS", "FAIL"] },
         mast_category: {
           enum: [
             "system-design-issue",
             "inter-agent-misalignment",
             "task-verification-failure",
           ],
         },
         reason: { type: "string" },
       },
     };
     phase("Verify");
     const result = await agent(
       `仕様: ${args.spec}\ndiff:\n${args.diff}\n` +
         "この diff が仕様を満たさないケース・壊すケースを探せ。不確かなら不合格とせよ。" +
         "討論はしない、この1回で確定させる。",
       {
         label: "checker",
         model: "XHigh",
         effort: args.effort,
         schema: CHECKER_VERDICT,
       },
     );
     return result;
     ```

     `args.spec`/`args.diff`/`args.effort`は呼び出し元（オーケストレーター）が`Workflow`起動時に渡す
     （`swarm-explore/SKILL.md`の`args.question`/`args.shards`と同型の house style）。`args.effort`には
     複雑度ガード表の Maker/Checker effort 列（`simple`=medium/`standard`=high/`complex`=xhigh）の値を
     渡し、「model と`effort`は独立にルーティングする」原則（上記複雑度ガード節）を Checker でも維持する。
     `mast_category`は既存の MAST 3 分類（system design issue / inter-agent misalignment / task
     verification failure）の呼称をハイフン区切りの enum 値へ slug 化した上で機械的に強制するもの
     （分類の意味自体・呼称の対応関係は変更しない）。StructuredOutputツール呼び出しの検証はツール
     呼び出し層で行われるため、判定行の欠落・prose のみの申告という失敗モードが構造的に発生しない
     （旧来のプロンプト指示のみでは省略が再発していた問題の解消。SWARM.md §6の prose 無効原則を機械
     強制へ格上げしたもの）。取得した `result.verdict` をそのまま `task-<task-id>-checker-verdict` へ
     書く（下記「矛盾検出の機械化」参照、書き込み先・形式は不変）。

   - **並行レビューの判定行強制は変更しない**: 下記「並行レビュー」（`code-reviewer`/`vald-reviewer`/
     `security-audit`）は引き続き `Agent` toolで起動し、プロンプトには「最終行に
     `REVIEW: APPROVE|REQUEST_CHANGES` を必ず明示せよ」を含める既存方式のまま（本ミッションのスコープは
     Checkerのみ、`@fix_plan.md` Out of Scope参照）。判定行を含まない報告は**判定として無効**（prose
     無効原則、SWARM.md §6）であり、`SendMessage` で当該エージェントに判定行を再要求する（完了済み
     エージェントも resume されトランスクリプト文脈を保ったまま回答できる。再スポーンしない）。
   - **`idle_notification` のみの停滞への対応（判定行省略とは別の停滞パターン、Checker以外が対象）**:
     Maker・Test Maker・plan-checker・並行レビューいずれの名前付き Agent 呼び出し（`name` 指定、
     `subagent_type: "fork"` 以外）でも、完了後に報告本文が一切届かず `idle_notification` のみが返る
     ことがある（判定行が欠落しているのではなく報告そのものが届かない点で上記「判定のschema強制」とは
     別の停滞）。この場合も再スポーンせず、まず `SendMessage` で当該エージェントへ報告本文を直接
     再要求する（完了済みエージェントは resume され文脈を保ったまま回答できる）。同型の停滞は名前付き
     Agent 全般に反復する傾向があり、催促で解消する場合が大半だが、繰り返し催促しても本文が得られない
     場合は無限に待たず `TaskStop` して当該調査・判定を呼び出し元が直接実行する代替手段に切り替える。
     **Checkerは本節の対象外**: `Workflow`タスク内部で起動される`agent()`呼び出しは、`ListAgents`/
     `SendMessage`の対象になる個別の名前付きAgentとしては公開されない（ドキュメント上確認できる範囲
     ではWorkflowタスク自体のみがアドレス可能な単位であり、host仕様の明示的な否定記述ではなく現状の
     資料から読み取れる限りでの推測である点は留意する）。したがってCheckerの Workflow タスクが完了
     通知を返さず停滞した場合は、resumeではなく`TaskStop`の上で同一スクリプトを再実行する（schema強制
     により判定行省略自体は構造的な原因からは発生しない。ただしタイムアウト・API過負荷以外の要因
     〈Workflowスクリプト自体のランタイムエラー・host側オーケストレーション異常等〉を排除する検証は
     行っていない）。
   - **並行レビュー**: グローバル CLAUDE.md の方針に従い、Checker と並行して独立スポーンする（Checker の代替
     ではなく追加のレンズ）:
     - 非自明な変更全般 → `code-reviewer` サブエージェント（品質・保守性・言語別の落とし穴）。
     - vald 配下の変更 → `vald-reviewer` サブエージェント（Vald Law・config 同期・K8s リソース規約）。
     - domain タグが認証・シークレット処理・ネットワーク境界（gateway 等）に触れる → `security-audit`
       サブエージェント。Checker とは独立に「不合格」を出せる（cross-family ではないが視点の異なる
       heuristic として、intra-family verifier の限界を補完する。SWARM.md §2）。

3. **決定論的検証（最終権威）**:
   - vald: `make test/pkg` 等の既存ターゲット、dotfiles: JSON/hadolint/zsh -n。
   - **hook の結果と Checker 判定が食い違う場合は hook を優先**する。Checker が「合格」でも hook が失敗を
     報告したら不合格として扱い、Checker には矛盾点を再提示して再判定させる（Checkerは名前付きAgentとして
     resumeできない、上記「Checkerは本節の対象外」参照。矛盾点を追加した仕様＋diffで`agent()`を新規に
     呼び直す一発判定とする。討論禁止の原則とは矛盾しない — 前回の判定内容を引用させず独立した1回判定
     として扱う）。**再判定でも矛盾が
     解消しない**場合は Fable スポット診断（SWARM.md §1 トリガー 4。起動前に `budget-guard.sh --fable`
     必須）で「なぜ食い違うか」の原因のみを診断させ、その診断書を添えて Checker に最終再判定させる —
     スポット診断は裁定・判定の上書きをしない（hook 第一権威は不変）。
   - **矛盾検出の機械化**: 上記の食い違い判定を目視だけに頼らず、hook 結果と Checker 判定を
     `/tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/task-<task-id>-hook-result` /
     `task-<task-id>-checker-verdict`（各 `PASS`/`FAIL` の 1 行）に書いてから
     `~/.claude/skills/swarm-implement/scripts/verify-consistency.sh <task-id>` を呼ぶ。
     `CONTRADICTION` の場合は exit 1 で検出済み（上記の再判定フローへ）、`CONSISTENT` なら判定集約へ
     進んでよい（判定そのものは上書きしない、検出のみ）。
4. **Observe（実行面のあるタスクのみ）**: 静的な lint/test は既知の回帰は防ぐが新規の失敗モードは検知しない
   （`SWARM_REFERENCES.md`）。プロダクトコードのように実際に動かせる変更では、`verify` skill で変更後の挙動を
   実際に動かして観察してから完了処理へ進む。テスト・ドキュメントのみの変更で駆動できる実行面がない場合は
   スキップしてよい。
5. **不合格時のエラー分類（リトライ前に判定、旧 dig の Circuit Breaker 由来の原則）**:
   - **Transient**（ネットワーク・レート制限・タイムアウト）→ 通常の次試行として扱ってよい。
   - **Permanent**（存在しないシンボル・型不一致・構文エラー・同一失敗シグネチャの繰り返し）→ 単純な
     リトライで直る見込みが薄いため、試行回数に関わらず**即座に Fixer を起動**する（下記）。
   - 失敗シグネチャ（エラー種別＋失敗箇所）を試行間で比較し、**2 回連続で一致したら**（3 試行目を待たず）
     即 Fixer に切り替える（無進捗の早期検知）。
6. **判定集約**: Checker・並行レビュー（該当する場合）合格 **かつ** 決定論的検証パス **かつ**（該当する場合）
   Observe で異常なし → 完了処理へ。いずれか不合格 → 上記分類に従い次試行または Fixer へ。

### Fixer 呼び出し（ソフトチェックポイント）

トリガー: **3 試行消費**、または **Permanent エラー**、または **失敗シグネチャの 2 回連続一致**のいずれか
（早い方を優先する。3 試行を待たずに無進捗を検知したら即座に切り替える）。
**ネスト共有予算が逼迫している場合の早期切替（pilot）**: ネストされた `/swarm-loop` でミッション共有
予算（`_mission-total-<root-slug>`）の残数が少ない（目安: 残り試行数がタスク単体の残試行数を下回る）
場合は、2 試行目終了時点でも早期に Fixer へ切り替えてよい（残 budget を事後測定の受動的コストでなく
能動的な切替シグナルとして扱う）。`budget-guard.sh` の出力形式が本条件の機械判定に十分か（残数の
取得手段）は未確認であり、導入前に実現可能性を確認すること。
同じ Maker コンテキストで試行を
継続すると、失敗履歴の蓄積で思考が固定化する（「理解負債」）。これを断ち切るため、**新規の `debugger`
サブエージェント（Agent tool, `subagent_type: "debugger"`, `model: "High"` (または `"sonnet"`) を明示）を Fixer として
起動する**（`debugger` の frontmatter は `model: inherit` のため、明示を怠ると Fable/Max セッションでは暗黙に
Fable/Max を消費しスポット判断層の回数制限を迂回してしまう — SWARM.md §1 ルーティング規則。`swarm-fable-gate.sh`
hook は未指定時に警告を出すのみでブロックはしない — 強制力は無いため明示は呼び出し側の責任のままである）:

- Fixer への入力は「現在のコード（diff ではなく最終状態）＋直近のエラー出力」のみ。過去の試行履歴・Maker の
  弁明・これまでの対処一覧は渡さない（クリーンな Fixer コンテキストで根本原因を再特定させるため）。
- Fixer には強制内省テンプレートで根本原因を出力させる:
  `What failed?` / `Root assumption that was wrong?` / `Specific fix (not "try harder")?` /
  `Repeating the same mistake as a prior attempt?`
- **修復プリミティブの型付け（GraSP局所修復対応、pilot）**: 上記強制内省テンプレートの `Specific fix` に加え、
  Fixer は根本原因を下記 5 種の局所修復プリミティブ（GraSP = "Graph-Structured Skill Compositions for
  LLM Agents", arXiv:2604.17870 §2.4）のいずれか 1 つに分類
  させる（複数該当する場合は最も操作範囲が狭いものを選ぶ — 安全側に倒す）:
  - `Rebind`（スキル選択自体は正しいが引数・束縛が誤り）
  - `InsertPrereq`（前提条件が欠落している）
  - `Substitute`（スキル選択自体が誤り、インターフェースは維持したまま置換）
  - `Rewire`（近傍の依存関係・呼び出し順序の繋ぎ替え）
  - `Bypass`（現在の状態が既にダウンストリーム要件を満たしており当該ステップ自体が不要。**Bypass のみ
    生の検証出力〈テスト結果・lint 出力〉を根拠として明示必須** — 誤分類で実失敗を「変更不要」と
    指示するリスクへの対処。決定論的検証・Checker・既存テストの削除弱化禁止は変わらず残るため偽グリーン
    には至らないが、予算空費を早期に検出するための追加条件）
    いずれにも当てはまらない（根本原因が個別ノードの操作では説明できず、アーキテクチャ・仕様そのものの
    不備）場合は、下記 MAST 分類の `system design issue` ルートを優先的に検討するシグナルとして扱う
    （本タグは Fixer 自身の自己申告であり、Checker の MAST 3 分類の代替にはならず、既存の MAST 判定・
    hook 第一権威・討論禁止のいずれも上書きしない）。
    **既知の限界（pilot・未検証）**: 元論文の 5 分類はエージェント行動グラフ（ALFWorld 等のツール呼び出し
    系列）向けの定義であり、本 skill が扱うコード diff への適用はグラフ構造の相同性を仮定した拡張である
    （検証済みではない）。「1 ホップ」というスコープ上限は原論文の既定（2 ホップ）と異なる本 skill 側の
    裁量値であり、論文に帰属させない。効果測定（修正スコープの縮小・Fixer 後の収束率向上の有無）は
    軌跡ログで別途行う。hook/script による機械強制のない prose 規範であり、SWARM.md §2「未機械化ギャップ」の
    1 つとして扱う。
    **出自の明記**: 本タグ付けは複数ミッションで繰り返された訂正パターンからの抽出ではなく、外部研究
    （2026-08-26 Deep Research、swarm-meta 経由）を根拠とする pilot 導入であり、通常の `swarm-evolve` の
    Checker 受理基準（証拠内 2 回以上の反復パターンのみ）とは別枠であることを明示する。
- Fixer の結論（根本原因の再診断）を新しい仮説として次の Maker 入力に反映する。次試行の Maker 起動プロンプト
  には、上記プリミティブ分類に応じた修正スコープの目安（`Rebind`/`Substitute` は当該関数・当該呼び出し
  箇所のみ、`InsertPrereq`/`Rewire` は直接依存先 1 ホップまで、`Bypass` はコード変更なしで当該ステップの
  要否を再検証）を明記する。Maker がこの目安を超える変更が必要と判断した場合は、その旨と理由を自己
  評価に含めさせる（スコープ逸脱の隠蔽は許さない。SWARM.md §6 のデータ完全性原則と同型）。
- **固定テストへの過適合対策**: Fixerが新しい仮説を提示した後、Checkerへの最終再判定の前に、
  Test Maker へ Fixer の根本原因仮説（上記強制内省テンプレートの出力）を入力として渡し、
  「その仮説が対象とする具体的なエッジケース・入力値を狙って壊せるか」を狙う追加テストケースを1件
  書かせる（既存テストと同じ仕様を検証するが入力値・エッジケースを変えた isomorphic なテスト。
  Checkerと同じ反証指向 — 「これを壊せるケースを探せ」— で書かせ、既存テストと同程度の難易度で
  通るだけの無意味な変種にしない）。既存テストに加えてこれも実行し、既存テストの削除・弱化は
  引き続き禁止する（「データの完全性」原則は不変）。追加テストが既存テストと矛盾する結果を返した場合は
  Permanentエラーとして扱いFixerへ差し戻す（3試行目以降、同一の固定テスト集合だけに通る局所解への
  収束を検出する目的。TDAD Iron Law・判定集約契約はいずれも変更しない）。
- **Fixer 失敗後の Fable 最終診断（SWARM.md §1 トリガー 1）**: Fixer 自身も根本原因を特定できない
  （診断が「不明」または検証可能な仮説の域を出ない）場合、ESCALATE / BUDGET_EXCEEDED として人間へ報告する
  **直前に** Fable スポット診断を 1 回だけ挟んでよい:
  1. `budget-guard.sh --fable <task-id> --mission=<slug>` を通す（exit 1 なら即 ESCALATE、Fable は使わない）。
  2. `swarm-architect` スポット診断モードを起動（prompt に `[fable-spot:<task-id>]` を含める —
     hook が grant を task 束縛で照合する）。入力は「現在のコード＋直近のエラー生出力＋仕様」のみ
     （Fixer と同じクリーンコンテキスト原則）。
  3. 診断書の「実装介入の要否」が「必要」の場合（このルートは高難易度ゲートを常に満たす）、次試行の Maker を
     `model: 'Max'`（または `'fable'`）で起動してよい（**Fable Maker**）。同一スポット消費の継続であり mission 枠は追加消費
     しない: `budget-guard.sh --fable-maker <task-id>` で継続 grant を発行し（base spot の消費実績を機械的に
     検証、無ければ `FABLE_MAKER_NO_BASE` で拒否・継続も 1 回のみ）、起動 prompt に
     `[fable-spot:<task-id>-maker]` を含める。Fable Maker の成果物にも判定集約（Checker(XHigh / opus)・
     並行レビュー・決定論的検証）を例外なく適用する — Fable/Max の自己申告では完了させない。
  4. スポット診断でも解けなければ従来どおり ESCALATE（診断書を `@fix_plan.md` の軌跡に添付し、人間の
     `/swarm-architect` フル設計モード招集の判断材料にする）。
- それでも収束しない場合、Fixer の再診断結果を MAST 分類で振り分ける:
  - **system design issue**（仕様・アーキテクチャそのものの不備）→ 設計判断が絡むため `/swarm-architect`
    招集を `swarm-loop` に要請する。
  - **inter-agent misalignment / 誤スコープ**（実は独立した複数タスクへの分解が必要だった）→ 下記
    「ネストされた /swarm-loop への分解提案」を検討する。
  - 同じ対処を漫然と繰り返さない（budget-guard の残り試行を空費しない）。

#### ネストされた /swarm-loop への分解提案

- Fixer は上記の inter-agent misalignment / 誤スコープの場合に限り、ネストされた `/swarm-loop`
  （**Interactive scale 限定、Mission scale 禁止**）の起動を*提案*できる。Fixer 自身はネストを起動しない —
  判断材料の提示のみ。実際に起動するかどうかは、Fixer を呼び出した側（この試行ループを回している
  swarm-implement 本体 — コードを書く Maker ではない）が決定する。
- ネスト起動の条件:
  1. **深さはちょうど 1 段まで**。親の `@fix_plan.md` から現在の depth を読み取り +1 して渡す:

     ```bash
     parent_depth=$(sed -n 's/^- depth: //p' "$(git rev-parse --show-toplevel)/@fix_plan.md")
     ~/.claude/skills/swarm-loop/scripts/mission-init.sh <slug> "<goal>" interactive "" "$((${parent_depth:-0} + 1))"
     ```

     （親が depth 省略 = 0 ならネスト先は 1。孫ネスト（depth ≥ 2）は `mission-init.sh` 自体が `REFUSE`
     して `exit 1` にする — ここでの `interactive` 固定・`""`(self-improve-targets 不使用) 指定を省略すると
     `scale` が既定の `mission` になってしまうため必須。）

  2. **予算はツリー全体で共有する**: `budget-guard.sh <task-id> <max> --mission=<root-slug> --mission-max=20`
     （root-slug は最上位ミッション＝depth 0 のミッションの slug）。**この共有プール
     （`_mission-total-<root-slug>`、通常モードの試行カウンタ用）は、`complex` 計画承認（上記）で使う
     Fable スポット予算プール（`_fable-mission-total-<slug>`、`budget-guard.sh --fable --mission=<slug>`
     で消費）とは完全に独立したカウンタである** — 同じ `--mission=<slug>` を渡しても合算されない
     （実装は `budget-guard.sh` 参照）。2 プールを統合すべきかは本 skill のスコープ外の残課題とし、
     要否は GATE で人間判断を仰ぐ。
  3. **ネスト先は必ず既存の隔離済み worktree 内**（`worktree-alloc.sh` で確保済み）で起動する。

- ネスト先は人間不在のため Phase 5 GATE に到達できない。内部タスクが `blocked(design)`/`blocked(spec)`/
  `blocked(budget)` のいずれかに至った時点で `ESCALATE` し、その結果を呼び出し元（swarm-implement 本体）へ
  構造化して返す。「完了しました」という自己申告をそのまま呼び出し元が信用しない（SWARM.md §6 と同じ原則を
  ネスト境界にも適用）。
- ネスト先での `/swarm-architect` 招集は禁止（人間不在のため無意味）。`blocked(design)` に至った場合は
  そのままネスト全体を `ESCALATE` させ、最終的に親を経由して人間へエスカレーションする。

## 完了処理

1. 軌跡ログに 1 行追記: `日付 | タスク | 試行回数 | 結果 | 学び`。同一根本原因が過去に一度出現していた
   場合は、この完了処理で学びを prose のまま残さず機械化チェックへ昇格させる（SWARM.md §5）。
2. worktree を使った場合は回収（ブランチは保持）:

   ```bash
   ~/.claude/skills/swarm-implement/scripts/worktree-release.sh <worktree-path>
   ```

3. `~/.claude/skills/swarm-implement/scripts/parallel-gate.sh --release <task-id>` でスロットを
   解放する（`swarm-parallel-gate.sh` フックの
   スロットは TTL で自動失効するが、明示解放しないと他タスクを不要に長く待たせる）。
4. マージが必要なら人間に `/swarm-release-gate` の招集を要請して終了（自分でマージしない）。

## 予算超過時のフォールバック（必須）

`@fix_plan.md` に以下を書いてから停止する: 残タスク・全試行のエラー要約（生ログ含む）・試した対処・次に試すべき仮説。
`~/.claude/skills/swarm-implement/scripts/parallel-gate.sh --release <task-id>` でスロットを解放してから
Stop する（swarm-stop-verify.sh が
5 回失敗時はエスカレーションとして通す）。

## Memory Protocol（Skill 自己メンテナンス、軌跡ログとは別軸）

軌跡ログ/`@fix_plan.md`（前提節参照）は**プロジェクト単位**のミッション軌跡。これとは別に
`~/.claude/skill-memory/swarm-implement/MEMORY.md` には**本 skill 自体の運用パターン**（Fixer 発火条件の
傾向、複雑度ガードの判定基準が実際には合わなかった事例、Checker の不合格観点の偏り等）を蓄積する —
開始前に存在すれば読み、完了処理の一部として本 skill の運用一般に通用する知見のみ追記する
（プロジェクト固有の学びは引き続き軌跡ログへ）。一般化可能な学びが無ければ何も書かずに終える。
