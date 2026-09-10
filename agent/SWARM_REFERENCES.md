# SWARM_REFERENCES — 参考文献（旧 SWARM.md §8 由来）

`SWARM.md` 本体からトークン占有量削減のため分離した参考文献セクション。`SWARM.md` 本文中の
「SWARM_REFERENCES.md 参照」は本ファイルの該当箇所を指す。

**確定（adversarial 3 票中 2 票以上で確認）:**

- MAST: Multi-Agent System Failure Taxonomy — 14 失敗モード・3 カテゴリ（system design / inter-agent
  misalignment / task verification）。arXiv:2503.13657, OpenReview fAjbYBmonr。
- ChatDev 等 SOTA オープンソース MAS の正答率は最低 25%、7 システム横断で失敗率 41–86.7%（1600+ 実行トレース）。
- 役割仕様・トポロジー改善で ChatDev は 25.0%→40.6% まで改善するが実運用水準には未達（+15.6pt、部分的改善に留まる）。
- 検証層の強化のみでは失敗は解消しない（仕様・設計・エージェント間通信も原因）。
- LLM-as-judge（o1 few-shot）は人間注釈との一致度 accuracy 94% / Cohen's κ 0.77 で失敗モードを検出可能。
- Multi-agent debate はラウンドを重ねるほど judge バイアスを増幅・持続させ、meta-judge（単一集約）はより頑健。
- Self-Preference Bias はモデルの生成能力と相関しない（強いモデル＝公平な judge ではない）。
- BEI/CIG: LLM 検証者間の behavioral entanglement（行動的もつれ）を統計的に定量化するメトリクス（18 モデル・
  6 ベンダー系列で実験、COLM 2026 採択）。もつれの強さ（CIG）は judge の over-endorsement bias と有意に相関する
  （GPT-4o-mini judge で Spearman ρ=0.64, p<0.001; Llama3 系 judge で ρ=0.71, p<0.01）。もつれを考慮した
  再重み付けにより単純多数決比で最大 4.5pt（84.7%→89.6%）の精度向上。arXiv:2604.07650。
- Nine Judges Two Effective Votes: 9 体 7 ファミリーの frontier LLM judge パネルは実効的に約 2 票分の独立情報
  しかない（Kish 実効サンプルサイズ n_eff≈2.0–2.5）。真に独立な投票との比較で 8–22pt の精度差が生じ、ボトル
  ネックは judge 間の相関でありパネル拡大では解決しない。arXiv:2605.29800。**注意**: 同論文由来の「最良単体
  judge がパネル全体と同等以上」という一般化 claim は独立検証で 0-3 棄却済み — この知見を根拠に「パネルは
  無意味」という結論へ飛躍しないこと。
- GroundEval: 決定論的スコアリングを LLM-as-Judge の明示的代替として位置づける手法。2 つの frontier LLM
  judge（Kimi-K2.6, ChatGPT-5.5）が根拠アーティファクトを一度も取得していないもっともらしいエージェント応答
  を 0.85–0.90 と評価した一方、trace 分析ベースの GroundEval スコアは 0.000 を検出。arXiv:2606.22737。
- Multi-agent debate の flip 率は自発的不安定性・迎合的同調・推論駆動説得の 3 メカニズムに反実仮想条件で分離
  可能。MMLU-Pro では自己反省のみ（ピア影響なし）でも 37% が回答を変え、厳密な意味での同調は 29%、モデル
  横断 57–77% が correct→wrong という有害な方向に偏っていた。arXiv:2606.00820。
- debate 中の sycophancy（ピア意見の無批判採用）は self-bias（自説固執）より圧倒的に多い（20 組中 18 組で
  sycophancy 優位、ACL2026 Main 採択）。arXiv:2510.07517。対策の response anonymization（身元マーカー除去）
  提案自体は 2-1 split（別の低信頼度論文が stylometric 指紋による匿名化の不完全性を指摘）であり確定扱いしない。
- D1: 27 本の failure/taxonomy/audit 論文の統合により post-MAST の 6 クラスタ失敗分類（tool-level /
  planning / long-horizon / multi-agent coordination / adversarial-safety / measurement-validity）が
  提案されている。MAST の 3 分類・14 モードを multi-agent coordination クラスタとして包摂する形。
  vote 3-0。arXiv:2607.05775。

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
  検証は未完了の単一一次ソースであり、`SWARM.md` §2 の「Checker は単一の Opus による一発判定・討論禁止」
  という既存設計を変更するには至らない（複数 Checker 化は §3 のリソース制約とのトレードオフが未評価のため、
  現時点では参考文献に留め採用は見送る）。見送りの理由は Nine Judges Two Effective Votes（arXiv:2605.29800、
  confidence=high 3-0、本節「確定」参照）によってより具体化される: 複数 judge/Checker パネルは相関により
  実効投票数が名目数より大幅に少なくなり（n_eff≈2.0–2.5）、単純な多数決やパネル拡大では改善しない。
  複数 Checker 化を将来検討する場合は、単純多数決ではなく judge 間相関を考慮した再重み付け（BEI/CIG、
  arXiv:2604.07650）が前提条件となる。
- Entropy Principle（arXiv:2606.08162）: LLM エージェントシステムのエントロピー（出力一貫性・タスク精度・
  セッション間一貫性の崩れ）は相互作用ラウンド数に対し指数的に増大する（S(t) = S0 * e^(alpha*t)）。
  40,000 件超の統制実験・100,000 件超の本番エージェント相互作用から 22 の内在的失敗寄与要因
  （6 ライフサイクル層）を導出し、対策として決定論的ガバナンス（PIG Engine / ADE プロトコル）を提案。
  `SWARM.md` §2 の「決定論的ツール（golangci-lint / hadolint / gofmt / make test）を第一権威とし、Opus
  Checker の LLM 判定は補助的 heuristic として扱う」という既存スタンスを独立に補強する一次ソース（adversarial
  検証は未完了）。既存方針を変更する必要はなく、根拠の追加としてのみ扱う。
- Anthropic 公式: “Multi-agent research system”, “Effective context engineering for AI agents”,
  “Building agents with the Claude Agent SDK”, “Subagents in Claude Code”（vendor 一次情報、
  組織トポロジー・コンテキスト管理・subagent 設計の実務知見として `SWARM.md` §1–§5 の設計判断に反映済み）。
- 4 段階検証権威階層（confidence=medium）: 形式的検証者（証明）＞実行フィードバック（テスト）＞学習型
  判定器（報酬モデル・LLM-as-judge）＞内在的シグナル（確信度・尤度）という階層で、実証された自己改善の
  強さがこの序列に沿う傾向がある（著者自身が定性的パターンと明記し、測定された法則ではないと限定）。
  arXiv:2607.07663。同じ論文由来の他の claim（mirror loop、SkillsBench+16.2pt）は独立検証で 0-3 棄却済み
  であり、本項目のみを confidence=medium として切り出して扱う（他の claim は不採用）。既存の「決定論的
  ツールを第一権威とする」`SWARM.md` §2 方針への追加根拠として扱う。
- 金融 MAS の創発的バイアス増幅（confidence=medium、金融ドメイン限定・サンプル 20 構成×2 データセットと
  やや小規模）: 多エージェント意思決定システムでシステム全体のバイアスが構成 LLM 単体比最大 10 倍まで増幅
  する事例。全構成員が低バイアスでもシステム全体が高バイアスを示すことがあり、バイアスが個々のエージェント
  に単純還元されない創発的失敗モード。arXiv:2512.16433。この知見と、本節「確定」の identity 駆動 sycophancy
  （arXiv:2510.07517、debate 中の sycophancy が self-bias より優位という知見）は、いずれも既存の並行レビュー
  設計（Checker と code-reviewer / vald-reviewer / security-audit を互いの出力を見せずに独立実行する設計 —
  結果的に response anonymization 相当が既に実現されている）および判定集約が単純多数決ではなく AND 集約
  （Checker 合格 かつ 決定論的検証パス かつ 該当レビュアー合格）である既存設計が、debate 型の相互汚染や
  創発的バイアス増幅に対して既に理にかなっていることの裏づけとして扱う。新たな必須事項・禁止事項の追加は
  行わない。

**2026-07-31 追加分（投票プロセスがセッション/利用上限により中断、source/quote は取得済み）:**

- 汎用長文脈 LLM は trajectory 障害の帰属・デバッグに弱く、専用 attribution モデルへの移行が業界動向という
  報告がある（TRAIL/TraceElephant 研究）。post-MAST の failure-attribution 研究はエコシステム化したが
  統一分類は未確立とされる。arXiv:2605.14892。
- self-evolving 系（ADAS/AFlow/MaAS）で generator=evaluator 同一だと sycophancy 化しやすく、reward
  hacking の実例（欺瞞的通信・共謀）も報告されているとの実証データがある。arXiv:2605.14892。
- LLM-judge の step-level failure attribution は Who&When ベンチマークで精度 14% のみという報告がある。
  Causal Agent Replay（CAR、do-operation による介入的原因特定）という決定論的代替手法が提案されている。
  arXiv:2606.08275。
- 自己改変の素朴 greedy 採択は決定論的評価で 30–42%・確率的評価で 72–100% の誤採択を起こすという実証
  データがある。PACE（sequential hypothesis testing e-process）が false-commit 確率を α 以下に抑制する
  との報告がある。arXiv:2606.08106。
- MOSS: 本番 harness 自己書き換えで単一進化サイクルにより 4task 平均 0.2526→0.6100 という報告がある。
  自己改変適用は人間の明示コマンド必須でゲートされる（`swarm-evolve` の人間承認原則の裏付け）。reward
  hacking 対策は明示されていない。arXiv:2605.22794。
- HarnessFix: trace-grounded 診断による harness 修復が 4 ベンチマークで 6.3–18.4pt 改善したという報告が
  ある。outcome-only の自己改善手法は根拠なき広範な変更を生みやすいとされる。7 層 harness 欠陥分類が
  提案されている。arXiv:2606.06324。

**2026-08-01 追加分（swarm-meta ミッション claude-orchestration-audit の deep-research、26 ソース fetch・
25 claim 検証・17 確認/8 反証）:**

- コンテキスト管理は 2026-08 時点で最も強く裏付けられたテーマ（4 独立系・confidence=high）: Anthropic の
  長時間実行エージェント運用ガイダンスは「セッションはゼロメモリで始まり compaction だけでは不十分、
  git 履歴・進捗ファイル等の永続的外部アーティファクトが必須」と明記する。これは本基盤の `@fix_plan.md`/
  軌跡ログ設計と一致する（新規採用ではなく既存設計の裏付け）。Anthropic の context-management API は
  compaction（`compact_20260112`）・tool-result clearing（`clear_tool_uses_20250919`）を server-side
  primitive として提供。CompactionRL（Zhipu/Tsinghua）は compaction を RL 目的関数へ組み込み学習可能に
  し本番 GLM-5.2 で使用、Self-GC（Xiaohongshu）は自己統治的 context pruning agent が本番で 10–15%
  （peak ~20%）の input token 削減を報告（ただし account email 頭文字による非ランダム分割であり著者
  自身が monitoring evidence と限定、厳密な A/B ではない）。arXiv:2607.05378, arXiv:2607.00692。
- Claude Code の「Dynamic Workflows」機能（=本基盤で使用中の Workflow ツール）が Anthropic 公式に
  説明されている: 単一セッションで数十〜数百 subagent を fan-out（上限 1000/run・同時 16）、組み込み
  検証パターンは「独立 angle からの攻撃 + 敵対的反証で収束」。confidence=medium（2-1 vote）。`SWARM.md`
  §0 参照。
- MAS-ProVe（6 MAS×5 verifier×2 粒度の横断評価、arXiv:2602.03053）: process-level verification は
  一貫して性能改善せず高分散。既存の「検証層強化のみでは失敗解消しない」（本節「確定」参照）を補強。
  confidence=medium（単一 preprint、2026-02、独立再現なし）。
- verifier のスコアリング設計そのものが有効な改善軸: discrete judge score を continuous score（logit
  期待値）に変えると検証精度が向上（Terminal-Bench: SNR 0.775→0.799、精度 73.1%→77.5%）。
  arXiv:2607.05391。confidence=medium（単一一次資料・著者自己評価）。既存の Checker 設計（PASS/FAIL
  discrete、討論禁止）を変更する根拠としては現時点で不十分、参考記録に留める。
- Phantom Guardrails（arXiv:2607.13083）: naive add-only self-improving harness で LLM proposer が
  ルール形状の入力パターンから存在しない guardrail を捏造する（ルール形状入力で 15/60 vs featureless
  入力で 0/60）。add-only 受理ループ下でこの捏造が持続・再発する。「prune 可能な受理ゲートが必要」
  という結論。`swarm-evolve` の人間承認必須原則（`SWARM.md` §5）を補強する新エビデンス。confidence=medium
  （単一 preprint、独立再現なし）。
- Anthropic 公式 2026-06 ブログは hooks を決定論的強制の意図された配置場所として明示するが、GitHub
  RFC issue（anthropics/claude-code#45427）は実運用で hooks が「necessary but insufficient」
  （サイレント失敗・subagent 経由バイパス・モデルによる書き換えの可能性）と指摘する。confidence=medium
  （3-0 vote）。`SWARM.md` §2 参照。

**swarm-meta 設計根拠（旧 swarm-meta/SKILL.md §1 由来、一次ソースのみ・adversarial 検証未完了）:**

- per-mission のアーキテクチャ選択は固定最適化構成に勝る（MaAS vs ADAS/AFlow: GAIA で +18% vs +2〜3%、
  ADAS は vanilla を下回る事例あり。arXiv:2502.04180）。タスク特性からのトポロジー予測は 260 構成の
  87% で成立する（arXiv:2512.08296）。
- meta-harness の実像はオフライン探索＋実行可能評価であり、探索は有界（ADAS は 30 反復/ドメイン）・
  sandbox＋人間検査つき（ADAS/AFlow, arXiv:2603.22386/2408.08435）。
- DGM は reward hacking を実際に起こした（検証マーカー除去・テスト実行偽装, arXiv:2505.22954）。METR
  の報告（成功実行の 16%+ がチートで失格・LLM モニタは jailbreak 可能）は決定論的検証第一権威の根拠を
  補強する。
- Three Laws（Endure（安全）> Excel（性能保持）> Evolve（最適化）、辞書式優先, arXiv:2507.21046 系）。
- DyTopo（arXiv:2602.06039、単一 preprint・adversarial 検証未完了、最強ベースライン比 +6.2）はラウンド
  毎に意味マッチでトポロジを再選択する設計を提案するが、実行中のハーネス切替は避けるべきという既存の
  安定性優先設計を上書きする根拠としては不十分。
- LLM 生成コンテキストファイルは -3%/+20% cost（Gloaguen et al.）。

**swarm-graph 設計根拠（旧 swarm-graph/SKILL.md §1 由来、一次ソースのみ・adversarial 検証未完了）:**

- Loop 型の逐次実行は暗黙依存・回復意味論の無際限性・可変実行履歴という構造的弱点を持つとの提案がある
  が実証はされていない（arXiv:2604.11378）。グラフ化の価値はモデル出力品質そのものではなく
  inspect/repair/pause/resume/govern といった運用面にあり、採用は条件付きとすべきとされる
  （arXiv:2607.19297）。一方で反証事例として、手続き型対話では in-context 自己オーケストレーションが
  LangGraph 相当の明示グラフ構成に 15/15 で勝つ結果も報告されている（arXiv:2604.27891）。
- 逐次的な性質のタスクへマルチエージェント構成を強制すると最大 -70% の性能劣化が報告されており
  （arXiv:2512.08296）、動的グラフ化は明示的な予算ガード・検証・停止基準の負担を増やす
  （arXiv:2603.22386）。
- 決定論的シミュレータによる評価（OrchBench, arXiv:2607.25656、単一 preprint・adversarial 検証未完了）
  は、エージェント数を増やすことよりタスク関連情報の保持がミッション品質への寄与が大きく、並列化の
  効果は調整失敗の蓄積で減殺されると報告する。
- 静的トポロジー固定（cascading error に脆弱）と無制約な動的トポロジー変更（trajectory divergence・
  メモリ肥大）の両極を避け、確信度監視等の基準に基づく制約付き動的再構成が実証的に優位という報告もある
  （DynaGraph, arXiv:2605.29511、単一 preprint・adversarial 検証未完了。StrategyQA/MATH/FinQA で全 8B
  ベースライン超え）。対象ドメイン（単発 QA 系）は swarm-graph の対象（ソフトウェア実装タスク）と異なる
  ため閾値の直接転用はしないが、GRAPH-FIT ゲートによる事前適合判定＋構造変更が必要な場合のみ有界
  replan（≤2 回）を許可するという制約付き動的性を独立に支持する根拠として扱う。
- 見送り（2026-08-12 記録、機構変更なし）: 2026-08-11 に撤回した「局所動的展開」提案（replan 予算を
  消費しない軽量分岐、根拠不十分により却下）と同種の方向性を、ベンチマーク評価付きで支持する新しい
  一次資料が見つかった（H-RePlan, arXiv:2606.20487 — device-local strategy recovery と
  orchestrator-level global replanning の分離）。対象ドメイン（マルチデバイスシステム）が swarm-graph
  の対象（ソフトウェア実装タスク）と異なるため再提案は見送る。再検討する場合は本文の数値的根拠を
  精読し、ソフトウェア実装タスクへの転用可能性を個別に検証すること。

**swarm-architect 設計根拠（一次ソースのみ・adversarial 検証未完了）:**

- 設計時の構造検証として、証拠・品質、決定・ガバナンス、メッセージ整合性、不服申立の 4 カテゴリ
  12 ルールを提案する報告がある（arXiv:2606.21565、単一 preprint）。`swarm-architect`
  の実装計画セクションに DAG 整合性チェック（型互換性・precondition 充足の 2 項目。循環検出は
  `swarm-graph` の `graph-compile.sh` が既に決定論的に担保するため対象外）を追加する根拠として、
  この報告の「決定・ガバナンス」カテゴリの精神（本 skill では依存関係の事前検証へ転用）を採用した。
- Agent Dependency Graph による静的解析で agent 間のツール呼び出し経路をリスク検出する手法が
  報告されている（AgentFlow, arXiv:2607.01640、単一 preprint）。`swarm-architect` の DAG 整合性
  チェックとは対象（AgentFlow は既存の協調エージェントシステム実装に対する静的解析）が異なり
  直接転用ではないが、「依存関係を実行前に機械的に検証する」という設計思想の傍証として扱う。

**`settings.json` 運用設定の採否根拠:**

- `subagentPromptCacheTtl: "1h"` — 公式ドキュメント（`code.claude.com/docs/en/prompt-caching`
  「Which TTL each request gets」）によると、subagent/Workflow 等「メイン会話以外」のリクエストは
  Claude サブスクリプション（プラン内利用）でも API キー/従量課金でも既定 5 分 TTL しか得られない
  （メイン会話専用の 1 時間既定とは別枠）。本設定はこの既定 5 分を明示的に 1 時間へ延長する。
  subagent 呼び出しが多い swarm-* ワークフローでは 5 分の既定 TTL 内にキャッシュが失効しやすく、
  fan-out 再利用のキャッシュヒット率低下・再計算コストの増加が起きうるため延長した。トレードオフ:
  1 時間キャッシュの書き込みは API 課金ではより高いレートで課金される。**優先順位に注意**: 同ページ
  「Choose the TTL yourself」記載の適用順は `FORCE_PROMPT_CACHING_5M`（最優先、両バケット強制5分）＞
  `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL` 環境変数 ＞ 本設定 ＞ `ENABLE_PROMPT_CACHING_1H` ＞
  バケット既定値 — いずれかの環境変数が設定されていると本設定は無効化される（2026-08-26時点、本環境の
  `env`では両変数とも未設定を確認済み）。単発・短時間で完了する subagent 呼び出し（本ミッションが実測
  した 32〜56 シャードの Haiku 並列 fan-out 等）が主なワークロードでは逆にコスト増となりうるため、
  採否は実際のキャッシュヒット率（`cache_read_input_tokens`/`cache_creation_input_tokens`）を計測して
  から見直すこと（現時点では計測前の先行適用）。
- `permissions.allow` から `Bash(jq *)` / `Bash(/bin/bash *)` / `Bash(/bin/sh *)` を削除した —
  公式ドキュメント（`code.claude.com/docs/en/permissions`「Extend permissions with hooks」）に
  「Hook decisions don't bypass permission rules」「A blocking hook also takes precedence over
  allow rules」と明記されている。逆に言えば、hookが明示的にblock（exit 2）しない限り、
  `permissions.allow` の無条件エントリは `PreToolUse`/`PermissionRequest` hook の判断（allowでも
  passthroughでも）とは**独立に**評価され、単純な(chain無しの)コマンドはこのエントリだけで
  承認されうる。`permission-request.sh`（本ミッションで11ラウンドの敵対的レビューを経て構築した
  `.credentials.json` 等センシティブパスへのアクセス検知機構）がどれだけ精緻にpassthrough判定
  しても、`Bash(jq *)` が残っている限り単純な `jq -r '...' ~/.claude/.credentials.json`
  はこのネイティブルールだけで無審査承認され、hookの判定は完全に迂回される。`/bin/bash *`/
  `/bin/sh *` は`-c`引数で任意コマンドを実行できるため実害はさらに広く、hookベースの
  allowlist機構全体（`permission-request.sh`の文字whitelist・sensitive-path検知を含む）を
  丸ごと無効化しうる。jqの自動承認は`permission-request.sh`側の`jq -r?\b`パターン（パスの
  実体解決込み）に一本化されるため機能的な後退は無く、`/bin/bash`/`/bin/sh`の直接起動は今後
  常に通常の確認フローを経る（意図的な変更 — 直接シェル起動は任意コマンド実行と等価なため）。

- `claude/settings.local.json`（`~/.claude/settings.local.json` へ symlink）に残る `Bash(jq *)` は
  上記削除の反例にならない — `code.claude.com/docs/en/settings`（"Settings files and who they
  affect" 表、および "In order, highest precedence first" 節）を直接 WebFetch で確認したところ、
  Claude Code が読む設定ファイルは User (`~/.claude/settings.json`)・Shared project
  (`.claude/settings.json`)・Project local (`.claude/settings.local.json`、**プロジェクト直下限定**)・
  Managed の4種のみで、ホームディレクトリ直下の `~/.claude/settings.local.json` という第5の階層は
  存在しない（`settings.local.json` の Scope は常に "Project only"、`code.claude.com/docs/en/
claude-directory` の File Reference 表でも同様）。つまりこの symlink は Claude Code の設定
  マージ処理から一切読まれない死んだ経路であり、収録されている約90件の permission rule
  （`jq`含む）は本ミッションの脅威モデル上は無害（無効）— ただし利用者が「グローバルに有効」と
  誤認している可能性がある実害の無い別種の不具合として最終報告で別途言及する（本ミッションの
  スコープ外のため `Makefile.d/install.mk` 自体は変更しない）
- `Bash(cmake *)`/`Bash(make *)`/`Bash(gmake *)`/`Bash(ninja *)` は `Bash(jq *)` 等と同じ
  「hookはpermissions.allowを狭められない」という構造的性質を共有するが、`jq`/`bash`/`sh` と違い
  汎用コマンドインタプリタではなく（`sh -c "<任意コマンド>"`に自明に還元できない）、日常のビルド
  作業に必須のため削除は不採用。`Bash(python3 *)`等と同列の「意図的な広い許可」として
  `claude/CLAUDE.md`の Security 節に追記し、リスクを暗黙のままにしないことを優先した

新しい根拠が反証された場合、または追加の Deep Research で確度が上がった場合は本節と該当セクションを更新すること。

**外部レポート（2026-07-13 提出、人間による二次資料）由来で採用した項目 / 見送った項目:**

採用: Fixer パターン（`SWARM.md` §5、`debugger` サブエージェントによる汚染されていないコンテキストでの
根本原因再診断）、domain タグによる Maker のタスクルーティング（`swarm-loop` PLAN フェーズ）、テスト
アサーション整合性の明文化（§6「データの完全性」）、継続監視への `loop` skill 併用（§0）、Skill 自体の
メタループ改善（§5）、Test Maker によるテスト先行記述（`swarm-implement` step 0、MAST (i)(ii) 対策）、
Checker と並行する `code-reviewer` / `vald-reviewer` / `security-audit` サブエージェント起動（グローバル
CLAUDE.md の既存方針を swarm-implement に配線）、コア設計変更のプロアクティブな architect ゲート
（`swarm-loop` PLAN、事後対応の `blocked(design)` を補完）、Plan-Action-Observe-Verify の Observe を
独立ステップとして明示し既存の `verify` skill を配線（静的検証だけでは新規失敗モードを捉えられないという
本節の知見への対処）。これらは実在する Claude Code の機構（Agent tool の subagent_type、既存 `loop`/
`verify` skill、SKILL.md 編集）のみで実現できる。

見送り（2026-08-11更新・公式ドキュメントで仕様確認済み・理由は既存設計との構造的衝突）:
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`によるマルチセッション協調（Agent Teams）は、公式ドキュメント
（`code.claude.com/docs/en/agent-teams`、confirmed。本環境での実動作自体は未検証）により仕様が
確認された: **one team per session**（1セッション1チーム限定）・**no nested teams**（teammateは
自身のteammateを持てない）・in-processでのセッション再開非対応（`/resume`後は再スポーンが必要）・
トークンはteammate数に対して線形増加。このうち "no nested teams" は `swarm-implement` の
ネスト`/swarm-loop`（depth 1、Fixerが提案しswarm-implement本体が起動する設計）と直接衝突し、
"one team per session" はミッション横断の状態共有（`@fix_plan.md`によるセッション断からの再開が
核心要件）を不可能にする。トークンの線形増加も§3のリソース制約と衝突する。以上3点により
本基盤の既存設計との**構造的な衝突**が確認されたため採用を見送る（旧理由「実在・動作が未検証」は
解消済みだが、判明した仕様内容自体が不採用の直接的根拠になった）。一方、
「Investigate with competing hypotheses」（複数teammateが敵対的に仮説を反証し合うパターン）は
`swarm-implement`のFixerパターンや`swarm-graph`のREPLAN診断の設計参考として記録する価値がある。
エージェント間のタスク共有・状態管理は引き続き既存の実在ツール（TaskCreate / TaskList / TaskUpdate、
`@fix_plan.md`）で代替する。Mailbox機構は`~/.claude/teams/{team-name}/inboxes/{agent-name}.json`
（タスク一覧の永続化は別途`~/.claude/tasks/{team-name}/`）である。
再検討のトリガー: (1) no nested teams制約の撤廃、(2) one team per session制約の撤廃、
(3) Mission規模の複数セッション横断要件自体が変わる、のいずれかが発生した時点。

**現状の食い違い（2026-07-13 skill-effectiveness-audit で判明）**: `claude/settings.json` の
`env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` は実際には `"1"`（有効）に設定済みである。上記「見送り」は
方針判断であり、settings.json の設定値そのものを変更するものではない。この食い違いは人間の判断により
現状維持（設定値はそのまま・`SWARM.md` 本文もそのまま）とした。挙動観察（Agent tool 経由のサブエージェント
から `idle_notification` 形式のメッセージが届く等）が本環境変数と関係する可能性があるが未検証であり、
上記の再検討トリガーとは独立に記録するに留める。

**採用: cross-session messaging（2026-08-12・`swarm-relay` 新設で確認済み）**: `ListAgents`/
`SendMessage` による独立した別セッション間のメッセージング（`code.claude.com/docs/en/
cross-session-messaging`、v2.1.224+・macOS/Linux 限定、confirmed。本環境での実動作自体は未検証）は、
上記 Agent Teams が抱える 3 つの構造的制約（one-team-per-session・no-nested-teams・トークン線形増加）
のいずれにも当たらない別機能である。対象は「それぞれ自律的に起動・進行する独立したセッション」間の
軽量なメッセージ受け渡しのみであり、1 セッション内でのチーム編成やそのネスト制約を一切継承しない。
plain text のみを運ぶ制約（structured な agent-team プロトコルメッセージはチーム内に留まる、公式
"Limitations" 節）を踏まえ、独自のワイヤーフォーマットではなくメッセージ本文の先頭行の文字列規約として
プロトコルを定義した（詳細は `swarm-relay/SKILL.md` §2）。受信側の安全モデル（メッセージは他セッション
からの入力であり人間の承認ではない、公式仕様 "a message from another session never counts as your
consent"）を土台に、SWARM.md §2 の決定論的ツールを第一権威とする原則を cross-session 受信メッセージにも
適用する（構造化フィールドの内容を無条件に信用して状態遷移しない）。既知の残存制約: 非対応環境
（native Windows・Amazon Bedrock・Claude Platform on AWS・Google Cloud の Agent Platform・
Microsoft Foundry）では no-op に劣化する設計とした。worktree 内で動作する同一 repo の他セッションは
cwd の等価一致判定では検知できない（`swarm-relay/SKILL.md` §4.1 既知の限界。再検討トリガー:
`ListAgents` の listing に worktree/main の階層関係が追加された場合）。

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
複雑度ガードにそれぞれ統合済み。後方互換のためのリダイレクトとして残していた `dig` skill 自体も
2026-08 に削除した（`/swarm-loop` が唯一のエントリポイント）。

**マルチエージェント協調の失敗パターン（2026-08-18 追加、Anthropic 公式一次ソース直接検証）:**

出典: Anthropic Frontier Red Team, "Patterns and problems in emerging multiagent systems"
（2026-08-13、`https://www.anthropic.com/research/multiagent-systems`）。要約ツール経由ではなく
本文 HTML を直接取得し内容を検証済み。中核テーゼ: 「agent は他の agent を明確な入出力を持つ
道具呼び出しとして扱う限り機能するが、対等で長期的な独自の目標を持つ peer として扱おうとすると
協調が破綻する」。

- **同調性(低分散)による系統的失敗**: 同一 context・同一 scaffolding・同一 model の agent は
  非常に似た行動を取り、孤立した誤りが系統的失敗に転じる。実験例: 30 agent 中 18 個が独立に
  同一 git branch 名を生成、複数 agent が独立に同一タイトルの文章を提出、資源管理タスクでは
  全 agent が独立に同一の高頻度ポーリングを開始し 240 万リクエスト中 117 件のみ受理。
  `swarm-secretary` の重複排除における sources 件数の扱いの根拠。
- **turf war（目標衝突からのエスカレーション）**: 開始時は互いの存在に気づいていなかった非互換
  タスクが、依存関係が事後に判明した時点で相互妨害・エスカレーションへ発展した実験報告
  （自己複製的スクリプト・アカウント無効化等）。`swarm-loop` Phase 3 の並列ディスパッチ前
  独立性事前チェックの根拠。
- **CEO 階層・役割指定プロンプトの効果は限定的**: ゲーム制作実験で「baseline」「役割指定」
  「CEO 階層」の 3 プロンプトを比較したが有意差はなく、協調成否を分けたのは土台モデルの世代
  （最新モデルのみが高 PR マージ率と高コード共有を両立）だった。`SWARM.md` §2 の「決定論的検証を
  Checker 判定より優先する」原則の追加裏付け（プロンプト構造の工夫よりモデル能力とアービトレーション
  機構が支配的）。
- **認識論的トレードオフ**: 虚偽検出（懐疑を強める）と「隠れたプロファイル」課題（少数派の私的
  情報を信頼する）は同一ダイヤルの表裏であり、どちらかを直す調整は他方を悪化させる。人間社会は
  これを条件付き信頼の制度（市場・評判・法廷・査読）で解決しており、agent にはその等価物がない。
- confidence: 単一の一次資料（Anthropic 公式、adversarial 投票プロセス未実施）。実験デザインは
  開示されているが独立再現はない。

**2026-09 追加知見 (Antigravity Teamwork-Preview & SKILL.stats 実装根拠):**

- **arXiv:2605.12978 (Memory Drift in Continual LLM Agent Systems)**:
  LLM が反復的に更新・上書きするメモリファイルは、回数を重ねるごとに初期の確定事実 (ground truth) から統計的ドリフトを起こす。`memory-guard.sh` による 200 行 / 25KB 制約、および `.edit-log.jsonl` による更新頻度トラッキングの理論的根拠。
- **arXiv:2607.13083 (Phantom Guardrails & Rule Accumulation Decay)**:
  失敗のたびにプロンプトやルールを無制限に追加し続けると、コンテキスト汚染と推論遅延を引き起こす（Phantom Guardrails 現象）。50 回以上未発火のルールを統計的に検出・剪定する `swarm-evolve` の prune trigger 設計の根拠。
- **Antigravity Teamwork-Preview Architecture**:
  5 部構成ハンドオフ (`handoff.md`)、フォルダ排他所有規約 (`.agents/<subagent_id>/`)、二重トラック並行実行（実装トラック + E2E 検証トラック）、および結果非開示 (Outcome Non-Disclosure) によるバイアス遮断プロトコルの実証設計。
