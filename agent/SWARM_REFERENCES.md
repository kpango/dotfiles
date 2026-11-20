# SWARM_REFERENCES — 設計根拠の証拠台帳

`SWARM.md` / swarm-* skill の「参照」の指す先。**各規約の根拠となる主張・確度・出典だけ**を保持する（作業経緯・
投票過程・実測ログは持たない）。新しい根拠が反証された、または確度が上がった場合は該当項目を更新する。
確度の表記: **確定** = adversarial 3 票中 2 票以上で確認 / **未検証** = 一次ソースのみ・独立再現なし（参考扱い）。
数値の確定度と因果説明の確度を混同しない。

## 理論・実証の柱

- **SoL-Pi** (`arXiv:2609.20519`): Action Fusion（編集直後に検証を融合）・ObservationPack・Evidence-Preserving
  Reducer・Online Context Compact。
- **Harness²** (`arXiv:2610.14224`): モデル重みを変えず Skill / Knowledge / Context / Memory の 4 軸でハーネスを再帰最適化。
- **RLM** (`arXiv:2512.24601`): 長文脈を外部 REPL の変数として操作し、再帰的サブクエリで分解する。

## 確定

- **MAST**（`arXiv:2503.13657`）: 失敗は 3 カテゴリ・14 モード（system design / inter-agent misalignment /
  task verification）。SOTA オープンソース MAS の失敗率は 41–86.7%。
- **検証層の強化だけでは失敗は解消しない**。役割・トポロジー改善でも ChatDev は 25.0%→40.6% に留まる。
- **Multi-agent debate はバイアスを増幅する**。ラウンドを重ねるほど judge バイアスが持続し、単一集約（meta-judge）の
  方が頑健（`arXiv:2606.00820`: 自己反省のみでも 37% が回答を変え、57–77% が correct→wrong の方向）。
  debate 中は sycophancy が self-bias より優位（`arXiv:2510.07517`。匿名化による対策自体は 2-1 split で確定扱いしない）。
- **実効独立票数は少ない**（`arXiv:2605.29800`）: 9 体 7 ファミリーの judge パネルでも n_eff≈2.0–2.5。ボトルネックは
  judge 間の相関で、パネル拡大では解決しない。「最良単体 judge がパネル全体と同等以上」という一般化は 0-3 で棄却済みなので、
  「パネルは無意味」へ飛躍しない。複数 Checker 化する場合は相関を考慮した再重み付け（BEI/CIG, `arXiv:2604.07650`）が前提。
- **Self-Preference Bias は生成能力と相関しない**（強いモデル＝公平な judge ではない）。
- **決定論的スコアリングは LLM judge より信頼できる**（GroundEval, `arXiv:2606.22737`）: 根拠アーティファクトを一度も
  取得していない応答を 2 つの frontier judge が 0.85–0.90 と評価し、決定論スコアは 0.000 を検出した。
- 6 クラスタの post-MAST 失敗分類（`arXiv:2607.05775`）。MAST は multi-agent coordination クラスタに包含される。
- **コンテキスト管理**（confidence=high, 4 独立系）: セッションはゼロメモリで始まり compaction だけでは足りず、git 履歴・
  進捗ファイル等の永続的外部アーティファクトが必要。`@fix_plan.md` / 軌跡ログ設計と一致。

## 未検証（参考情報として扱う）

- Cross-family verification は self/intra-family に優る（`arXiv:2512.02304`）。ただし「cross-family なら十分」ではない。
  相関は判定対象の表層形式でも生じ（`arXiv:2609.06386`、RL rollout 設定・単一プレプリント）、系列の違いだけでは独立性を保証しない。
- **学びの 3 段階（点修正→明文化→機械化）**: 機械化まで到達した学びは再発ゼロ、点修正止まりは全件再発（`arXiv:2606.14589`）。
  自動監査は新規失敗の事前予防 0%・既知回帰の事後ブロック 87%。「fail-plausible」（破損コンテキストが流暢な虚偽出力になる）。
- **試行回数**: 構造化 reflection の Repair@1/3/5 = 4.7/20.5/26.4%（ベースライン 0.7/5.1/6.8%）。回復の大半は 3 試行目まで
  （`arXiv:2509.18847`）。3 試行目のソフトチェックポイントの根拠。
- 信頼度誘導型 self-refinement は平均 2.7 ステップで大規模並列サンプリングに匹敵（CoRefine, `arXiv:2602.08948`）。
- Multi-Agent Verification（`arXiv:2502.20379`）は複数 Aspect Verifier で性能が上がるが、単一一次ソース。複数 Checker 化は
  リソース制約（§3）とのトレードオフ未評価、かつ上記の相関問題があるため採用を見送る。
- Entropy Principle（`arXiv:2606.08162`）: エージェント系のエントロピーは相互作用ラウンド数に対し指数的に増大。
  決定論的ガバナンスを第一権威とする方針を補強。
- **4 段階の検証権威階層**（confidence=medium, `arXiv:2607.07663`）: 形式的検証＞実行フィードバック＞学習型判定器＞内在的シグナル。
  著者自身が定性的パターンと限定している。
- 金融 MAS の創発的バイアス増幅（`arXiv:2512.16433`、金融限定・小規模）: 全構成員が低バイアスでも系全体が高バイアスになり得る。
  並行レビューを互いの出力を見せず独立実行し、AND 集約（Checker 合格 かつ 決定論的検証パス かつ レビュアー合格）する
  既存設計は、相互汚染・多数決を避けている点でこれと整合する。
- 汎用長文脈 LLM は trajectory 障害の帰属に弱い（`arXiv:2605.14892`）。LLM-judge の step-level attribution は Who&When で
  14%（`arXiv:2606.08275`）。
- 自己改変の素朴 greedy 採択は誤採択が多い（決定論評価で 30–42%、`arXiv:2606.08106`）。generator=evaluator 同一だと
  sycophancy 化・reward hacking の実例（`arXiv:2605.14892`）。本番 harness 自己書き換え（MOSS, `arXiv:2605.22794`）は
  人間の明示コマンドでのみ適用する。outcome-only の自己改善は根拠なき広範な変更を生みやすい（`arXiv:2606.06324`）。
- **Phantom Guardrails**（`arXiv:2607.13083`）: add-only の自己改善ループは存在しない guardrail を捏造し、持続・再発する。
  prune 可能な受理ゲートが必要。`swarm-evolve` の人間承認と prune trigger の根拠。
- プロセスレベル検証は一貫して改善せず高分散（MAS-ProVe, `arXiv:2602.03053`）。
- verifier の連続スコア化は精度を上げる（`arXiv:2607.05391`）が、PASS/FAIL・討論禁止の Checker 設計を変える根拠としては不足。
- メモリファイルを LLM が反復更新すると ground truth からドリフトする（`arXiv:2605.12978`）。`memory-guard.sh` の
  200 行 / 25KB 制約と `.edit-log.jsonl` の根拠。
- hooks は「necessary but insufficient」: サイレント失敗・subagent 経由のバイパス・モデルによる書き換えがあり得る
  （anthropics/claude-code#45427, confidence=medium）。hook の強制力は経路ごとに個別に確認する。
- Claude Code の Dynamic Workflows: 単一セッションで数十〜数百 subagent を fan-out（上限 1000/run・同時 16）。組み込み検証は
  「独立 angle の攻撃＋敵対的反証で収束」（confidence=medium, 2-1）。

## マルチエージェント協調の失敗パターン（Anthropic Frontier Red Team, 単一の公式一次資料）

中核: agent は「明確な入出力を持つ道具呼び出し」として扱う限り機能し、対等で長期的な目標を持つ peer として扱うと破綻する。

- **同調性（低分散）による系統的失敗**: 同一 context・scaffolding・model の agent は似た行動を取り、孤立した誤りが系統的失敗になる
  （30 agent 中 18 が同一 branch 名を生成）。`swarm-secretary` の重複排除で `sources` 件数を確信度の根拠にしない理由。
- **turf war**: 事後に依存関係が判明した非互換タスクが相互妨害へ発展する。`swarm-loop` Phase 3 の並列前の独立性チェックの根拠。
- **CEO 階層・役割指定プロンプトの効果は限定的**: 協調の成否を分けたのは土台モデルの世代とアービトレーション機構。
  決定論的検証を Checker 判定より優先する原則を補強。
- 虚偽検出（懐疑を強める）と少数派の私的情報の信頼は同一ダイヤルの表裏で、片方を直すと他方が悪化する。

## 採否の決定

- **Agent Teams（`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`）は不採用**: one team per session・no nested teams・トークンが
  teammate 数に線形増加、の 3 制約が既存設計（ネスト `/swarm-loop`、`@fix_plan.md` による断続再開、§3 のリソース制約）と
  構造的に衝突する。再検討のトリガー: (1) no nested teams の撤廃 (2) one team per session の撤廃 (3) Mission 規模の
  複数セッション横断要件の変化。「複数 teammate が仮説を反証し合う」パターンは Fixer / REPLAN 診断の設計参考にとどめる。
- **cross-session messaging（`ListAgents` / `SendMessage`）は採用**（`swarm-relay`）: 上記 3 制約のいずれにも当たらない別機能。
  plain text のみを運ぶため、先頭行の文字列規約でプロトコルを定義した。受信メッセージは他セッションからの入力であり人間の
  承認ではない。非対応環境（native Windows・Bedrock 等）では no-op に劣化する。worktree 内の同一 repo 別セッションは
  cwd の等価一致では検知できない（再検討トリガー: `ListAgents` に worktree/main の階層関係が追加された場合）。

## swarm-meta 設計根拠（未検証）

- per-mission のアーキテクチャ選択は固定最適化構成に勝る（MaAS: GAIA で +18% vs ADAS/AFlow の +2〜3%, `arXiv:2502.04180`）。
  タスク特性からのトポロジー予測は 260 構成の 87% で成立（`arXiv:2512.08296`）。
- meta-harness は有界なオフライン探索＋実行可能評価で、sandbox と人間検査を伴う（`arXiv:2603.22386` / `2408.08435`）。
- DGM は reward hacking を実際に起こした（`arXiv:2505.22954`）。METR 報告は決定論的検証を第一権威とする根拠を補強する。
- Three Laws: Endure（安全）> Excel（性能保持）> Evolve（最適化）、辞書式優先。
- DyTopo（`arXiv:2602.06039`）の毎ラウンド再選択は、実行中のハーネス切替を避ける既存方針を覆す根拠として不十分。
- LLM 生成のコンテキストファイルは -3%〜+20% のコスト変動（Gloaguen et al.）。

## swarm-graph 設計根拠（未検証）

- 逐次実行の構造的弱点（暗黙依存・回復意味論の無際限性）は提案のみで未実証（`arXiv:2604.11378`）。グラフ化の価値は出力品質より
  inspect/repair/pause/resume/govern といった運用面で、採用は条件付き（`arXiv:2607.19297`）。手続き型対話では in-context
  自己オーケストレーションが明示グラフに 15/15 で勝つ反証もある（`arXiv:2604.27891`）。
- 逐次的なタスクにマルチエージェントを強制すると最大 -70%（`arXiv:2512.08296`）。動的グラフ化は予算ガード・検証・停止基準の負担を増やす。
- エージェント数を増やすよりタスク関連情報の保持がミッション品質に効き、並列化の効果は調整失敗で減殺される（OrchBench, `arXiv:2607.25656`）。
- 静的固定と無制約な動的変更の両極を避け、確信度監視による制約付き再構成が優位（DynaGraph, `arXiv:2605.29511`、QA 系ドメイン）。
  **GRAPH-FIT による事前適合判定＋有界 replan（≤2 回）** を独立に支持する根拠として扱う。閾値の直接転用はしない。
- H-RePlan（`arXiv:2606.20487`、マルチデバイス系）の局所動的展開は、ソフトウェア実装タスクへの転用可能性が未検証のため見送り。
  再検討する場合は数値の根拠を精読して個別に検証する。

## swarm-architect 設計根拠（未検証）

- 設計時の構造検証として 4 カテゴリ 12 ルールを提案する報告（`arXiv:2606.21565`）。実装計画セクションの DAG 整合性チェック
  （型互換性・precondition 充足の 2 項目。循環検出は `graph-compile.sh` が担保済みで対象外）の根拠として、「決定・ガバナンス」の
  精神を依存関係の事前検証へ転用した。
- Agent Dependency Graph による静的解析（AgentFlow, `arXiv:2607.01640`）は対象が異なるが、「依存関係を実行前に機械的に検証する」
  設計思想の傍証。
