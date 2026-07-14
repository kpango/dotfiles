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
    Skill,
    TaskCreate,
    TaskUpdate,
    TaskList,
  ]
user-invocable: true
disable-model-invocation: false
---

# swarm-implement — Maker/Checker 分離実装ループ

設計根拠は `SWARM.md` §2・§3・§8 の Deep Research 結果を参照。要点: (1) Maker (Sonnet) と Checker (Opus) は
同一ベンダー系列であり verifier 独立性には理論的限界がある → **決定論的ツール（lint/test）を第一権威**とし
Checker は補助 heuristic として扱う。(2) Checker は Maker と討論しない — 仕様＋diff のみを見て単発判定する。
(3) 5 試行のうち回復の大半は 3 試行目までに集中するというデータがある → 3 試行目で仮説そのものを疑う。
(4) ループは Plan（PLAN フェーズ）→ Action（Maker）→ Observe（実挙動の観察）→ Verify（Checker・並行レビュー・
決定論的検証）のサイクルであり、静的検証だけでなく実際に動かして観察する Observe を独立ステップとして持つ。

## 前提（開始前に必ず実施）

1. プロジェクトルートの `AGENTS.md` と `@fix_plan.md` を読む — 同一エラーへの同一対処の繰り返しを防ぐ。
   同一根本原因の学びが 2 回目に登場していたら、それが機械化チェック（hook/lint/test）に昇格済みか確認する
   （SWARM.md §5）。未昇格なら、実装より先にその機械化を行う。
2. タスクが 2 件以上並列なら、タスクごとに worktree を割り当てる:

   ```bash
   ~/.claude/skills/swarm-implement/scripts/worktree-alloc.sh <task-slug>   # 出力 = worktree パス
   ```

3. タスクごとに一意な task-id（例: `vald-fix-agent-ngt-20260713`）を決める。

## 複雑度ガード（実行方式の決定、旧 dig 統合）

Maker を起動する前に、まずタスクをこの表で分類する。**trivial なタスクに Maker/Checker のフル分離を
起動しない**（オーバーヘッドがメリットを上回る。`swarm-loop` の Quick モードは基本的にここが trivial/simple）:

| 複雑度     | 判定基準                                                              | 実行方式                                                                             | TDAD     |
| ---------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | -------- |
| `trivial`  | 1 ファイル・15 行以下・新規ロジックなし（設定変更・定数・リネーム等） | オーケストレーター（呼び出し元）が直接編集し、Stop/PostToolUse hook の検証のみで完了 | 不要     |
| `simple`   | 30 行以下・1 関数変更・既存パターン踏襲                               | Maker(sonnet) 単体 + 軽量 Checker（1 回判定、並行レビューは省略可）                  | 任意     |
| `standard` | 複数ファイル or 新規ロジック導入                                      | フル Maker/Checker 分離（本セクション以下の手順どおり）                              | **必須** |
| `complex`  | 複数システム or 新規抽象化 or アルゴリズム設計                        | フル Maker/Checker 分離＋着手前に実装計画のみ書かせて人間/Checker の承認を得る       | **必須** |

`standard`/`complex` では以下の **TDAD Iron Law** を適用する: 本番コードを書く前に失敗するテストを書く。
テストなしに本番コードを書いたら削除して最初からやり直す。例外なし。RED → Verify RED → GREEN →
Verify GREEN → REFACTOR → Coverage 80%+ の順を踏む（下記 Step 0 の Test Maker が RED を担当）。
タスク記述は `task-template.md`（本ディレクトリ）を参照する。RED/GREEN/REFACTOR 各段階での git
checkpoint コマンド例・言語別カバレッジ計測コマンド・共通 Output Schema を定義済み。

## ループ（1 試行 = 以下の 1 周、最大 5 試行・3 試行目でソフトチェックポイント）

各試行の頭で予算を消費する:

```bash
~/.claude/skills/swarm-implement/scripts/budget-guard.sh <task-id> 5
# exit 1 (BUDGET_EXCEEDED) なら即停止 → @fix_plan.md に軌跡を書き出して人間へ報告
```

0. **Test Maker（`standard`/`complex` は必須、`simple` は任意、`trivial` はスキップ）** — Code Maker より先に
   独立スポーンして**テストケースだけ**を table-driven（golang-testing / rust-testing / python-testing skill
   準拠）で先行記述させる（実装させない・TDAD の RED を担当）。これにより秘書レポートの仕様の曖昧さを
   実装前に顕在化させる（MAST (i)(ii) 対策）。テストで機械判定不能なタスク（定型的な設定変更・ドキュメント
   更新等）は複雑度に関わらずスキップしてよい。
1. **Maker (`model: sonnet`)** — Agent で独立スポーン。入力は秘書レポートの該当項目＋仕様（＋ Test Maker が
   いれば先行テスト）のみ。
   - vald: 既存 make ターゲット経由でのみビルド・生成（Vald Law 遵守。hooks が強制）。
   - dotfiles: `.hadolint.yaml` の ignored ルールを尊重。インストールは make ターゲット経由。
   - 出力: 変更 diff の要約・**自己評価と自信度（high/medium/low）**・実行した検証コマンドの**生の標準出力**。
     「テストが通りました」等の prose のみの申告は evidence として無効（fail-plausible 対策。SWARM.md §6）。
   - **禁止**: テストが失敗するからといってアサーション・許容誤差・スキップ指定を弱める/削除することでグリーン化
     すること。それは failure を隠蔽しただけで解決していない（データの完全性。SWARM.md §6）。テスト自体の修正が
     必要な場合は「なぜテストの期待値が誤っていたか」を Checker に説明できる根拠を添える。
   - `standard`/`complex` タスクでは新規コードのカバレッジ 80%+ を目安にする（TDAD の REFACTOR 完了条件）。
2. **Checker (`model: opus`)** — Maker とは**独立コンテキスト**で Agent スポーン。入力は「仕様＋ `git diff`」
   のみ（Maker の自己評価・自信度・言い分は渡さない）。
   - プロンプトは反証指向:「この diff が仕様を満たさないケース・壊すケースを探せ。不確かなら不合格とせよ」。
   - **討論させない**: Checker の判定は 1 回で確定させる。不合格なら理由を返し、Maker への再指示は次試行として
     ループを回す（Checker コンテキスト内で Maker と往復させない — debate はバイアスを増幅させる、SWARM.md §2）。
   - 判定は必ず MAST 3 分類のどれに当たるかを添えさせる: system design issue / inter-agent misalignment /
     task verification failure。分類が (i)(ii) なら `swarm-secretary` の仕様構造化や `swarm-architect` 招集の
     要否を CHECKPOINT に伝える（Checker を強化するだけでは直らないカテゴリのため）。
   - 合格判定は Checker のみが出せる。Maker の「完了しました」は判定材料にしない。
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
     報告したら不合格として扱い、Checker には矛盾点を再提示して再判定させる。
4. **Observe（実行面のあるタスクのみ）**: 静的な lint/test は既知の回帰は防ぐが新規の失敗モードは検知しない
   （SWARM.md §8）。プロダクトコードのように実際に動かせる変更では、`verify` skill で変更後の挙動を
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
（早い方を優先する。3 試行を待たずに無進捗を検知したら即座に切り替える）。同じ Maker コンテキストで試行を
継続すると、失敗履歴の蓄積で思考が固定化する（「理解負債」）。これを断ち切るため、**新規の `debugger`
サブエージェント（Agent tool, `subagent_type: "debugger"`）を Fixer として起動する**:

- Fixer への入力は「現在のコード（diff ではなく最終状態）＋直近のエラー出力」のみ。過去の試行履歴・Maker の
  弁明・これまでの対処一覧は渡さない（クリーンな Fixer コンテキストで根本原因を再特定させるため）。
- Fixer には強制内省テンプレートで根本原因を出力させる:
  `What failed?` / `Root assumption that was wrong?` / `Specific fix (not "try harder")?` /
  `Repeating the same mistake as a prior attempt?`
- Fixer の結論（根本原因の再診断）を新しい仮説として次の Maker 入力に反映する。
- それでも収束しない場合:
  - 設計判断が絡む可能性があれば `/swarm-architect` 招集を `swarm-loop` に要請する。
  - 同じ対処を漫然と繰り返さない（budget-guard の残り試行を空費しない）。

## 完了処理

1. `AGENTS.md` に軌跡を 1 行追記: `日付 | タスク | 試行回数 | 結果 | 学び`。同一根本原因が過去に一度出現していた
   場合は、この完了処理で学びを prose のまま残さず機械化チェックへ昇格させる（SWARM.md §5）。
2. worktree を使った場合は回収（ブランチは保持）:

   ```bash
   ~/.claude/skills/swarm-implement/scripts/worktree-release.sh <worktree-path>
   ```

3. マージが必要なら人間に `/swarm-release-gate` の招集を要請して終了（自分でマージしない）。

## 予算超過時のフォールバック（必須）

`@fix_plan.md` に以下を書いてから停止する: 残タスク・全試行のエラー要約（生ログ含む）・試した対処・次に試すべき仮説。
その後 Stop する（swarm-stop-verify.sh が 5 回失敗時はエスカレーションとして通す）。
