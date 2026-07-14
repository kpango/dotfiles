# SWARM — 階層型 Agent Swarm 制御規約

対象ミッション: vdaas/vald コア開発と kpango/dotfiles 自律保守の並行推進。
人間の介入は「最終意思決定」「/swarm-loop・/swarm-architect・/swarm-release-gate・/swarm-evolve の招集」
のみに限定する。

本規約は 2026-07 の Deep Research（multi-agent orchestration 失敗研究・self-refine 収束性・verifier 独立性等の
一次文献調査、§8 参照）を反映して改訂されている。研究で反証された想定（「検証層さえ強化すれば失敗は解消する」等）は
削除・修正済み。

## 0. 起動 — Massive Agents Loop（単一エントリポイント）

自走ループの唯一の入口は `/swarm-loop`（人間招集限定）。旧 `dig` skill はここに完全統合され、単独では
存在しない（`/dig` は `swarm-loop` への薄いリダイレクトとして後方互換のみ残る）。「1 行の typo 修正」から
「100 体規模の Haiku 探索を伴う大規模自律ミッション」まで、人間が事前にどちらの skill を使うか判断する
コストをなくすことが統合の目的。

Phase -1（SCALE 判定）で Quick / Interactive / Mission のいずれかに自動分類し、SCALE 判定 → INIT →
EXPLORE → PLAN(+設計インタビュー) → EXECUTE → CHECKPOINT → GATE の状態機械で全層を駆動する。判定は昇格のみ
（安全側に倒す）。進行状態は `@fix_plan.md` に永続化される（Quick は状態ファイルを作らない。セッション再開も
`/swarm-loop` から）。状態確認は `swarm-loop/scripts/loop-status.sh`、新規開始は `mission-init.sh` を用いる。
詳細な判定基準・各 Phase の分岐は `swarm-loop/SKILL.md` を参照。

ミッション駆動（`/swarm-loop`）とは別に、**継続的なドリフト監視には汎用 `loop` skill を使う**（例:
`/loop 30m make lint && make test`）。こちらは完了条件を持たない定期監視であり、`/swarm-loop` の
Definition-of-Done 型の一回性ミッションとは目的が異なる。lint/test の恒常的な健全性チェックに用い、
異常を検知したら `/swarm-loop` でミッション化する。

## 1. 組織トポロジーと動的モデルルーティング

| 層                 | モデル                    | 責務                                                                                                                                                | 入口                               |
| ------------------ | ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| Swarm 層           | `haiku`                   | コードベース全域探索・golangci-lint 等の大量ログ解析・文献調査。読み取り専用。最大 100 体を Workflow でスポーン（同時実行数は Workflow が自動制御） | `swarm-explore`                    |
| 情報集約層（秘書） | `sonnet`                  | Haiku 群の生レポートの重複排除・構造化・依存関係に基づく優先順位づけ **のみ**。新規調査禁止                                                         | `swarm-secretary`（内部専用）      |
| 実装層 Maker       | `sonnet`                  | 秘書レポートに基づく実装。worktree 隔離必須                                                                                                         | `swarm-implement`                  |
| 検証層 Checker     | `opus`                    | Maker と独立コンテキストで単発の反証的判定を行う（討論はしない、§2 参照）。Maker の自己申告を信用しない                                             | `swarm-implement`                  |
| 指揮・設計層       | セッションモデル（Fable） | VStream の LSH 動的パーティショニング等の高度設計・難局突破の提案書出力のみ。コード編集禁止                                                         | `/swarm-architect`（人間招集のみ） |

ルーティング規則:

- Agent / Workflow の `model` パラメータで上表を **明示** する。`model` 省略（＝セッションモデル継承）が許されるのは指揮・設計層のみ。
- Haiku の生出力を実装層・指揮層のコンテキストへ直接流さない。必ず秘書レポートを経由する。
- 探索 → 集約 → 実装 → 検証は独立コンテキストで行い、各層間の受け渡しは構造化レポート（JSON / Markdown）のみとする。

## 2. 検証層の設計原則 — MAST 失敗分類と verifier 独立性の限界

Multi-Agent System Failure Taxonomy（MAST、150 件超の専門家注釈トレース由来、arXiv:2503.13657）は失敗を
3 カテゴリ・14 モードに分類する。CHECKPOINT でのブロック分類・ESCALATE 先の判断にこの 3 分類を用いる:

| MAST カテゴリ                 | 意味                                                           | 本基盤での対応                                                 |
| ----------------------------- | -------------------------------------------------------------- | -------------------------------------------------------------- |
| (i) system design issues      | 役割・仕様定義の不備                                           | `swarm-secretary` の構造化・`swarm-architect` への設計差し戻し |
| (ii) inter-agent misalignment | 層間の前提のズレ（秘書レポートと Maker の解釈違い等）          | `swarm-loop` PLAN での task 分割見直し・depends 明記           |
| (iii) task verification       | 検証不足・**時期尚早な終了（FM-3.1）**・不完全な検証（FM-3.2） | Stop hook・Checker 層・`swarm-release-gate`                    |

**検証層だけを強化しても失敗は解消しない**ことが実証されている（同論文、3-0 で確認）。実際、役割仕様やトポロジーへの
介入（ChatDev で 25.0%→40.6%）でも改善は部分的で、実運用に足る水準には至らなかった。したがって:

- Checker 層は必要条件であって十分条件ではない。`swarm-secretary`（仕様の構造化）と `swarm-architect`（設計是正）が
  カテゴリ (i)(ii) を担うことで初めて Checker（カテゴリ iii）が機能する。3 層のどれか 1 つだけを厚くしない。
- **Maker (Sonnet) と Checker (Opus) は同一ベンダー系列 (intra-family)**である。verifier の独立性研究では、
  solver と verifier の推論分布が近いほど verifier が誤りを見逃しやすく、self-verification や intra-family
  verification は cross-family verification（系列の異なるモデル・手法）に劣ることが示されている（一次ソースの
  みで adversarial 検証は未完了 — §8 参照。ただし複数独立研究で一貫した方向性）。
  - この限界への対処: **決定論的ツール（golangci-lint / hadolint / gofmt / make test）を第一権威とし、Opus
    Checker の LLM 判定は補助的 heuristic として扱う**。Stop hook・PostToolUse hook の機械的検証結果に反する
    Checker の「合格」判定は無効。両者が食い違う場合は hook 側を優先し、Checker には理由を再提示させる。
  - 可能な範囲でツールチェーンの多様性を上げる（例: golangci-lint の複数 linter、Rust の clippy + miri 等）。
    Claude Code の制約上モデル系列自体を変えることはできないため、これは構造的な残存リスクとして
    `swarm-release-gate` の人間承認ステップで明示する（§6）。
- **Maker/Checker は討論（debate）させない。** Multi-agent debate はラウンドを重ねるほど position/verbosity/CoT
  バイアスを増幅させ、後続ラウンドでも解消しないことが実証されている（3-0 確認）。一方、単一の集約判定
  （meta-judge 型）はバイアス増幅に対して頑健。Checker は Maker の弁明を受け取らず、仕様＋ diff のみを見て
  **一発で** 合否を出す（既存設計どおり。往復修正の要求はループの次試行として扱い、同一 Checker コンテキスト内で
  Maker と直接やり取りさせない）。

## 3. リソース制約 — Unified Credit Feedback

- **1 修正ループ = 最大 5 試行、ただし 3 試行目でソフトチェックポイント**を置く。RL 訓練した構造化 reflection の
  再現実験では Repair@1/3/5 = 4.7% / 20.5% / 26.4%（対ベースライン 0.7% / 5.1% / 6.8%）で、回復の大半は
  3 試行目までに積み上がり、4–5 試行目の追加効果は逓減する（単一の一次ソース、adversarial 検証は未完了 — 参考値
  として扱う）。したがって:
  - 試行 3 終了時点で修正が収束していなければ、**同じ仮説のまま試行 4–5 を消費する前に仮説そのものを疑う**
    （Maker への入力を変える: 秘書レポートの別項目、Checker 指摘の再解釈、または `/swarm-architect` 招集の検討）。
  - 試行 5 で `BUDGET_EXCEEDED` になったら即座に停止して人間に報告する（`@fix_plan.md` に状況を書き出してから）。
- 各試行の頭で `swarm-implement/scripts/budget-guard.sh <task-id>` を呼ぶ。
- Stop hook（`swarm-stop-verify.sh`）の差し戻しも 5 回で強制エスカレーション（停止を許可し人間へ報告）。
- Workflow スクリプトでは `budget.total && budget.remaining()` をループガードに使う。
- Haiku 100 体探索は 1 ミッションにつき原則 1 回。再探索が必要なら差分（前回の秘書レポート）を入力して範囲を絞る。

## 4. Git Worktree Isolation

- ファイル編集を伴うサブエージェントを 2 体以上並列で動かす場合、タスクごとに `swarm-implement/scripts/worktree-alloc.sh <task-slug>` で `<repo>/.claude/worktrees/` 配下に独立 worktree を割り当てる。
- メイン作業ツリーの直接編集は「編集エージェントが 1 体のみ」のときに限る。
- 完了後は `worktree-release.sh` で回収する（ブランチはデフォルトで保持）。

## 5. Explicit Global Memory — 破滅的忘却の防止と機械化エスカレーション

- 成功・失敗の軌跡はプロジェクトルートの `AGENTS.md` に追記する。形式: `日付 | タスク | 試行回数 | 結果 | 学び（根本原因・有効だった手順）`。
- 進行中の修正計画・残タスクは `@fix_plan.md`（プロジェクトルート）に置き、セッションを跨いで引き継ぐ。
- **同一エラーへ同一対処を 2 回連続で行わない**。修正ループに入る前に必ず `AGENTS.md` と `@fix_plan.md` を読む。
- **学びの 3 段階モデル（点修正 → 明文化ルール → 機械化チェック）を強制する。** 運用インシデント分析では、
  「点修正」で止まった学びは全件が再発し、「点修正 → 明文化 → 機械化スキャナ/チェック」まで到達した学びは
  再発ゼロだったという結果がある（一次ソース、adversarial 検証は未完了）。したがって:
  - `AGENTS.md` の同一根本原因が **2 回目に出現した時点**で、その学びを prose のままにせず、
    hook（`swarm-post-edit-lint.sh` へのルール追加）・lint 設定・テストケースのいずれかへ**必ず機械化**する。
  - 機械化されていない「2 回目の学び」は CHECKPOINT でのブロック要因として扱い、機械化が完了するまで
    同種タスクを先に進めない。
- vdaas/vald では `AGENTS.md` / `fix_plan.md` は `.git/info/exclude` によりローカル専用（OSS リポジトリを汚染しない）。
- **Fixer パターン（理解負債の遮断）**: 同一タスクで試行を重ねるほど Maker のコンテキストは失敗履歴で汚染され、
  同じ誤った仮説に固執しやすくなる。3 試行目のソフトチェックポイント（§3）では、失敗履歴を持たない新規の
  `debugger` サブエージェントを「現在のコード＋直近のエラーのみ」で起動し、汚染されていない視点から根本原因を
  再診断させる（詳細は `swarm-implement` skill）。
- **Skill 自体のメタループ（`/swarm-evolve` として実装済み）**: 同じ手直し・同じ人間からの訂正が複数ミッション
  にまたがって繰り返される場合、それは AGENTS.md の機械化対象であると同時に、**該当 SKILL.md の記述不足の
  シグナル**でもある。`swarm-evolve` skill が AGENTS.md の軌跡と hook rejection ログ（`evolve-log.jsonl`）
  から繰り返しパターンを検出し、Drafter(sonnet)/Checker(opus) の独立判定を経て SKILL.md / hooks への差分を
  起案する。**いかなる差分も人間の明示承認なしには適用しない**（docs-only であっても例外なし — エージェントが
  自身の行動規範を無断で書き換えることを防ぐため）。定期実行したい場合は `/loop 1d /swarm-evolve` を使う
  （承認フェーズは loop によってスキップされない）。

## 6. クローズドループ — 自己申告終了の禁止

- 「完了しました」という自己申告のみでの終了は禁止。以下の hooks が機械的に強制する:
  - **PostToolUse (Write/Edit)**: `swarm-post-edit-lint.sh` — dotfiles では hadolint（`.hadolint.yaml` 準拠）、vald では編集パッケージ限定の golangci-lint を即時実行し、失敗は exit 2 で差し戻す。
  - **Stop**: `swarm-stop-verify.sh` — セッション中に編集したファイルを対象に検証（JSON validity / hadolint / zsh -n / gofmt / golangci-lint）。失敗時はエラーログと共に修正ループへ強制的に引き戻す。
- より重い検証（`make test/pkg` 等）を Stop 時に強制したい場合は `<repo>/.claude/swarm-stop-check.conf` に 1 行 1 コマンドで記述する（make ターゲット経由のみ）。
- **「fail-plausible」失敗モードへの対処**: 破損したコンテキスト（古いエラーページ、失敗したツール出力の断片等）を
  モデルが流暢な虚偽の成功報告として提示してしまう失敗が報告されている（一次ソース、adversarial 検証は未完了）。
  対策として、Maker・Checker とも「完了」「合格」を主張する際は**生のコマンド出力（テスト結果・lint 出力・diff）を
  根拠として添付**することを必須とし、prose のみの完了報告は評価対象にしない（既存の hook 強制検証と整合）。
- マージ・デプロイ・破壊的変更は必ず `/swarm-release-gate` を経由し、`scripts/verify.sh` 全パス後に人間の最終承認を得る。
- **データの完全性**: テスト・アサーション・許容誤差・スキップ指定を、失敗を回避する目的で弱める・削除することを
  固く禁ずる。グリーン化それ自体は目的ではなく、検証が機能している状態を保つことが目的である。テストの期待値が
  実際に誤っていた場合のみ修正してよいが、その根拠を Checker に提示できることを条件とする。

## 7. プロジェクト固有ドメイン憲法

### vdaas/vald

- 1,060 行超の `Makefile` + `Makefile.d/` の構造を **絶対に破壊しない**。ビルド・テスト・生成は既存 make ターゲット経由のみ（`make test/pkg`, `make proto/all` 等）。
- Vald Law 1–5 を遵守（`*.pb.go` 直接編集禁止・ホストでの go build/cargo build 禁止・panic/log.Fatal 禁止・エラー破棄禁止・stdlib 直接 import 制限）。law gate hooks が機械的に強制する。

### kpango/dotfiles

- `.hadolint.yaml` の `ignored` ルール（DL3002, DL3007 等）は **インフラ固有の意図的設定**。一般的ベストプラクティスを理由に修正・削除・「改善」することを禁止する。lint 対応はこの設定ファイルを尊重した上で行う。
- インストール・リンクは make ターゲット（`make dotfiles/install`, `make claude/docker/install`）経由のみ。手動 symlink 禁止。

## 8. 参考文献（2026-07 Deep Research、確度別）

**確定（adversarial 3 票中 2 票以上で確認）:**

- MAST: Multi-Agent System Failure Taxonomy — 14 失敗モード・3 カテゴリ（system design / inter-agent
  misalignment / task verification）。arXiv:2503.13657, OpenReview fAjbYBmonr。
- ChatDev 等 SOTA オープンソース MAS の正答率は最低 25%、7 システム横断で失敗率 41–86.7%（1600+ 実行トレース）。
- 役割仕様・トポロジー改善で ChatDev は 25.0%→40.6% まで改善するが実運用水準には未達（+15.6pt、部分的改善に留まる）。
- 検証層の強化のみでは失敗は解消しない（仕様・設計・エージェント間通信も原因）。
- LLM-as-judge（o1 few-shot）は人間注釈との一致度 accuracy 94% / Cohen's κ 0.77 で失敗モードを検出可能。
- Multi-agent debate はラウンドを重ねるほど judge バイアスを増幅・持続させ、meta-judge（単一集約）はより頑健。
- Self-Preference Bias はモデルの生成能力と相関しない（強いモデル＝公平な judge ではない）。

**一次ソースのみ・adversarial 検証未完了（レート制限により中断、参考情報として扱う）:**

- Cross-family verification が self/intra-family verification に優る（arXiv:2512.02304）。
- 学びの 3 段階モデル（点修正→明文化→機械化）到達で再発ゼロ、点修正止まりは全件再発（arXiv:2606.14589）。
- 自動監査は新規失敗の事前予防 0%、既知回帰の事後ブロック 87%（arXiv:2606.14589）。
- 「fail-plausible」failure mode: 破損コンテキストが流暢な虚偽出力として提示される（arXiv:2606.14589）。
- Tool-Reflection-Bench: RL 訓練した構造化 reflection で Repair@1/3/5 = 4.7%/20.5%/26.4%
  （ベースライン比 0.7%/5.1%/6.8%）、回復の大半は 3 試行目までに集中（arXiv:2509.18847）。
- CoRefine: 信頼度誘導型 self-refinement は平均 2.7 ステップで大規模並列サンプリングに匹敵、
  信頼度に基づく打ち切り判断の正解率 92.6%（arXiv:2602.08948）。
- Multi-Agent Verification（MAV、arXiv:2502.20379）: 複数の Aspect Verifier（異なる観点で検証する
  LLM）を組み合わせる BoN-MAV は self-consistency・単一 reward-model 検証よりスケーリング特性が良く、
  弱い verifier 複数の組み合わせでも強い generator の性能を改善できる（weak-to-strong generalization）。
  同一モデルが generator/verifier 双方を兼ねる self-improvement でも性能向上を確認。ただし adversarial
  検証は未完了の単一一次ソースであり、§2 の「Checker は単一の Opus による一発判定・討論禁止」という
  既存設計を変更するには至らない（複数 Checker 化は §3 のリソース制約とのトレードオフが未評価のため、
  現時点では参考文献に留め採用は見送る）。
- Entropy Principle（arXiv:2606.08162）: LLM エージェントシステムのエントロピー（出力一貫性・タスク精度・
  セッション間一貫性の崩れ）は相互作用ラウンド数に対し指数的に増大する（S(t) = S0 * e^(alpha*t)）。
  40,000 件超の統制実験・100,000 件超の本番エージェント相互作用から 22 の内在的失敗寄与要因
  （6 ライフサイクル層）を導出し、対策として決定論的ガバナンス（PIG Engine / ADE プロトコル）を提案。
  §2 の「決定論的ツール（golangci-lint / hadolint / gofmt / make test）を第一権威とし、Opus Checker の
  LLM 判定は補助的 heuristic として扱う」という既存スタンスを独立に補強する一次ソース（adversarial
  検証は未完了）。既存方針を変更する必要はなく、根拠の追加としてのみ扱う。
- Anthropic 公式: “Multi-agent research system”, “Effective context engineering for AI agents”,
  “Building agents with the Claude Agent SDK”, “Subagents in Claude Code”（vendor 一次情報、
  組織トポロジー・コンテキスト管理・subagent 設計の実務知見として §1–§5 の設計判断に反映済み）。

新しい根拠が反証された場合、または追加の Deep Research で確度が上がった場合は本節と該当セクションを更新すること。

**外部レポート（2026-07-13 提出、人間による二次資料）由来で採用した項目 / 見送った項目:**

採用: Fixer パターン（§5、`debugger` サブエージェントによる汚染されていないコンテキストでの根本原因再診断）、
domain タグによる Maker のタスクルーティング（`swarm-loop` PLAN フェーズ）、テストアサーション整合性の明文化
（§6「データの完全性」）、継続監視への `loop` skill 併用（§0）、Skill 自体のメタループ改善（§5）、
Test Maker によるテスト先行記述（`swarm-implement` step 0、MAST (i)(ii) 対策）、Checker と並行する
`code-reviewer` / `vald-reviewer` / `security-audit` サブエージェント起動（グローバル CLAUDE.md の既存方針を
swarm-implement に配線）、コア設計変更のプロアクティブな architect ゲート（`swarm-loop` PLAN、事後対応の
`blocked(design)` を補完）、Plan-Action-Observe-Verify の Observe を独立ステップとして明示し既存の `verify`
skill を配線（静的検証だけでは新規失敗モードを捉えられないという §8 の知見への対処）。これらは実在する
Claude Code の機構（Agent tool の subagent_type、既存 `loop`/`verify` skill、SKILL.md 編集）のみで実現できる。

見送り（要再検証）: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`（有効化手段が本環境変数であるかは未確認）による
マルチセッション協調（Agent Teams）は、2026-03-24 付 Anthropic 公式資料（primary、adversarial 検証は未完了）
により**機能自体の実在は確認された**（"Orchestrate teams of Claude Code Sessions" — 独立ワークストリームに
分割可能なタスクでの並列化を想定）。ただし本確認は一次資料（スライド/プレゼン記載）の存在確認に留まり、
**現行 Claude Code バージョンでの実際の有効化・動作、`~/.claude/tasks/{team-name}/` という Mailbox 機構の
実装詳細、モデル別のトークン単価は未検証**である。したがって「実在確認ができない」という従来の見送り理由は
取り下げるが、動作・採用可否が未確認である以上、現時点でも本基盤への採用は見送る。エージェント間のタスク
共有・状態管理は引き続き既存の実在ツール（TaskCreate / TaskList / TaskUpdate、`@fix_plan.md`）で代替する。
再検討のトリガー: (1) 現行 Claude Code バージョンでの Agent Teams 動作確認、(2) 有効化手段・Mailbox 機構の
実装詳細確認、(3) 既存ツール代替との比較優位性評価 — のいずれかが完了した時点。

**現状の食い違い（2026-07-13 skill-effectiveness-audit で判明）**: `claude/settings.json` の
`env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` は実際には `"1"`（有効）に設定済みである。上記「見送り」は
方針判断であり、settings.json の設定値そのものを変更するものではない。この食い違いは人間の判断により
現状維持（設定値はそのまま・SWARM.md 本文もそのまま）とした。挙動観察（Agent tool 経由のサブエージェントから
`idle_notification` 形式のメッセージが届く等）が本環境変数と関係する可能性があるが未検証であり、上記の
再検討トリガーとは独立に記録するに留める。

**skill 統廃合（2026-07-13）:** 既存の `dig` skill が `swarm-loop` と大きく重複していたため（両者とも
探索→設計→実装→検証の自走ループを持つ）、人間が事前にどちらを使うか判断するコストを排除するために
`dig` を `swarm-loop` へ完全統合した。統合時に双方向の改善を行った: `dig` の Code Quality Reviewer が
Implementer と同じ `sonnet`（intra-family、§2 の verifier 独立性の限界そのもの）だった点を §1 の
Checker 層（`opus`）に格上げし（本節で以前「opusplan」と表記していたのは `opus` の意図であり、
実際の model 値・別モデル名ではない — 2026-07-13 skill-effectiveness-audit で判明した表記揺れを訂正）、
逆に `dig` の Circuit Breaker（Transient/Permanent エラー分類・失敗シグネチャ 2 回一致での
早期検知・強制内省テンプレート）を `swarm-implement` の Fixer トリガーへ逆輸入した。`dig` の
Quick/Research/Full モード判定は `swarm-loop` の Phase -1（Quick/Interactive/Mission）に、対話的設計
インタビューと TDAD Iron Law・複雑度ガードは `swarm-loop` の PLAN フェーズと `swarm-implement` の
複雑度ガードにそれぞれ統合済み。`dig/SKILL.md` は後方互換のための薄いリダイレクトのみを残す。
