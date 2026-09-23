# **次世代AIエージェント開発環境の統合仕様書：System-1意思決定層、自己進化ハーネス、コンテキスト仮想化によるアーキテクチャ刷新**

自律型AIエージェントの開発環境における最大のボトルネックは、単一のフロンティア大規模言語モデル（LLM）に対して推論、コード生成、ツール実行判定、エラー監視のすべてを逐次プロンプトで委ねるモノリシック設計にある。この旧来の構成は、API課金の指数関数的増大、毎ターン数秒から数十秒に及ぶ応答遅延、そして長大ログの再送に伴うコンテキストウィンドウの劣化（Context Rot）を必然的に引き起こす1。この構造的欠陥を打破するため、最新のエージェント工学は「言語生成（System-2）」「ミリ秒単位の離散判定（System-1）」「自己進化型実行基盤（Harness）」「構文木・ナレッジグラフ連動のメモリ仮想化（Memory/Graph）」の4層に明確に分離する多層アーキテクチャへと移行している1。

開発環境の改善において中核となる技術的跳躍は3点に集約される。第1に、TypeSafe AIが提供する「Jev」に代表されるSystem-1モデルの導入により、条件分岐、モデルルーティング、安全承認を70〜500ミリ秒、入力100万トークンあたり0.042ドルという極小コストで確定的に処理することである1。第2に、NVIDIAの自己進化ハーネス研究「SoL-Pi」が実証した4大効率化機構（Action Fusion、Online Context Compact、ObservationPack、Evidence-Preserving Reducer）を取り入れ、タスク遂行能力を落とさずにトークントラフィックを44.7%〜49.0%削減し、API費用を約3分の1に抑え込むことである3。第3に、「Graft」や「codebase-memory-mcp」によるコードベースの抽象構文木（AST）グラフ化と、「context-mode」によるツール出力のサンドボックス化を組み合わせ、探索トークンを最大99%排除することである4。

本仕様書は、これら最新のオープンソースリポジトリ群、ハーネス論文、スキルスタックを漏れなく整理し、自身のAIコーディング環境および自律エージェント運用基盤を最高効率へと再構築するための決定打となる技術情報ソースを提供する。

## **高速意思決定層（System-1）の確立：TypeSafe Jevによる分岐と生成の分離**

従来のLLMに「次にどのツールを呼ぶべきか」「このコマンドを実行してよいか」を判断させるアプローチは、文章生成の計算機構に構造化判断を無理やり出力させ、それをパーサーで検証するという不整合を抱えていた1。元OpenAIでInstructGPTやRLHFの開発に携わったDiogo Almeidaが創業したTypeSafe AIが公開した「Jev」は、テキスト生成機能を完全に排除し、状態と質問から直接「型付きの離散値」と「キャリブレーションされた確率」のみを出力するSystem-1モデルである2。

フロンティアモデルのエンドツーエンド応答が3〜329秒を要するのに対し、Jevは70〜500ミリ秒で完了し、出力トークン課金が存在しない1。モデル学習には結果との一致度を最大化するRLCD（Reinforcement Learning for Calibrated Decisions）が用いられており、返される確信度（Confidence）や確率は業務ロジックのハードなしきい値として直接使用可能である2。

&nbsp;

| 判定プリミティブ型 | 入力パラメータ                                                         | 出力データ仕様                                          | 主な適用領域                                                                |
| :----------------- | :--------------------------------------------------------------------- | :------------------------------------------------------ | :-------------------------------------------------------------------------- |
| Choice             | state（状況テキスト/JSON/配列） \+ 最大255個の排他的選択肢（criteria） | 選択された値、各選択肢の確率分布、確信度（confidence）1 | タスクのインテント分類、モデルルーティング、ツール選択1                     |
| Score              | state \+ 2〜10段階の評価基準（criteria）                               | 段階スコア値、確率分布、確信度（confidence）1           | コードレビューの品質採点、セキュリティリスク重大度評価、リードスコアリング1 |
| Noul               | state \+ 単一の検証命題（instructions）                                | 命題が真である確率（0.0〜1.0のYes確率）1                | ガードレール審査、脱獄検知、完了判定、ループ脱出判定1                       |

### **Jevを統合するための10大アーキテクチャ原則**

Jevをエージェントシステムに組み込む際は、以下の10原則に沿ってフローを再設計する1。

> 1. **機能分離の徹底**: LLMは創造・生成（Create）を担い、Agentは環境に対する操作（Act）を行い、Jevは次の遷移の意思決定（Decide）に特化する1。
> 2. **分岐の3プリミティブ化**: エージェント内のあらゆる条件分岐ノードを Choice、Score、Noul のいずれかに純粋化する1。
> 3. **ホットスワップ設計**: 初期構築はOpenAI、Anthropic、xAIなどのプロンプトで検証し、グラフ構造を変更することなく判定ノードのみをJevに置換する。
> 4. **共有状態と並列実行**: 同一の state に対して複数の questions を束ね、単一のリクエストで独立かつ並列に評価させる1。
> 5. **投機的ファンアウト（バッチ判定）**: 逐次的に判断を問い合わせるのではなく、可能性のある判定項目を1回のリクエストで同時バッチ評価する。13問の一括評価で12.2倍安価、10.0倍高速化する2。
> 6. **有界な分岐点への配置**: サブエージェントの委譲、使用モデルの切り替え、ツール呼出、ブラウザ上のDOM操作、人間へのエスカレーションの各境界に配置する。
> 7. **ループ全体の評価**: 単一のAPIコールのベンチマークではなく、エージェントがゴールに達するまでの総ターン数、累積レイテンシ、トータルコストで評価する。
> 8. **Rank Wide, Read Narrow**: 広範な候補ノードやログをJevで一気にスクリーニング（Shortlist）し、選定された最小限のコンテキストにのみフロンティアモデルの計算資源を集中させる。
> 9. **反復ステートマシンの適用**: 「State（状態集約） → Questions（判定発行） → Action（操作実行） → Verify（事後検証）」の標準ループをシステム全体で再利用する。
> 10. **計算・記述・不可逆実行の排除**: 数値計算は確定的なコードに、文章やコードの生成はLLMに任せ、Jev自身には直接的な破壊的コマンドの実行権限を与えない1。

### **Jevエコシステム・派生プロジェクト一覧**

コミュニティによって構築された、実務に即時投入可能なJev関連リポジトリの全容を以下にまとめる。

&nbsp;

| プロジェクト           | リポジトリURL / 提供元                                                                                        | アーキテクチャと機能概要                                                                                                                                              |
| :--------------------- | :------------------------------------------------------------------------------------------------------------ | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| jev-ultrafast          | [browser-use/jev-ultrafast](https://github.com/browser-use/jev-ultrafast?utm_source=gemini)                   | Browser Useと統合した超高速Web操作エージェント。DOM要素のクリックや操作の選択をJevが担い、文字入力のみ小型モデルを呼ぶ。Google Flightsのフライト検索を7.1秒で完遂11。 |
| typesafe-mcp           | [itsmostafa/typesafe-mcp](https://github.com/itsmostafa/typesafe-mcp?utm_source=gemini)                       | Claude Code、Claude Desktop、CodexにJevの判定機能を直結する公式MCPサーバー。Choice/Score/Noulをツールとして公開。                                                     |
| jev-mcp                | [jkudish/jev-mcp](https://github.com/jkudish/jev-mcp?utm_source=gemini)                                       | ファクトチェック、プロンプトインジェクション検知、意味的ソーティングをパッケージ化した実用ツール特化型MCPサーバー。                                                   |
| SemDecide              | [sharziki/semdecide](https://github.com/sharziki/semdecide?utm_source=gemini)                                 | JevをUnix CLIコマンド化。シェルスクリプト、CI/CDパイプライン、データ処理ワークフロー内でセマンティックガードレールや分類を直接実行可能。                              |
| Jev Codex Router       | [0xNatoshi/jev-codex-router](https://github.com/0xNatoshi/jev-codex-router?utm_source=gemini)                 | コーディングタスクの各ターンの難易度をJevが先行判定。簡易タスクは廉価モデルへ、高難度タスクは強力モデルへ動的ルーティング。237ターンの検証でコストを約60%削減。       |
| Winnow                 | [GhalebDweikat/winnow](https://github.com/GhalebDweikat/winnow?utm_source=gemini)                             | Claude Code向けのコンテキストガベージコレクター。Read、Bash、Grepなどの巨大な出力からタスクに直結する重要情報のみをJevが抽出してコンテキストに挿入。                  |
| Jev Review             | [devagrawal09/jev-review](https://github.com/devagrawal09/jev-review?utm_source=gemini)                       | コードレビューの一次スクリーニング。正確性、セキュリティ、信頼性、互換性、テストリスクを高速判定し、重大リスクのみを重量級モデルへ引き渡す。                          |
| Blink                  | [ellipsis-dev/blink](https://github.com/ellipsis-dev/blink?utm_source=gemini)                                 | コードベース内の意味論的パス探索（Pathfinding）。ディレクトリ階層ごとに該当課題と関連性の高いファイルやフォルダをJevが判定し、探索ウォーカーを重点配分。              |
| neo4jev                | [jexp/neo4jev](https://github.com/jexp/neo4jev?utm_source=gemini)                                             | ナレッジグラフ探索。Jevが各候補エッジの遷移妥当性確率を算出し、ビームサーチを用いて最短かつ高精度な探索経路を特定。                                                   |
| jev-desktop            | [lahfir/agent-desktop](https://github.com/lahfir/agent-desktop?utm_source=gemini)                             | デスクトップGUI自動化。OSのアクセシビリティツリーを解析し、どのUIコントロールをどう操作すべきかをJevが判定してローカルエグゼキュータに指示。                          |
| TypeSafe AI Playground | [markjaquith/typesafe-ai-playground](https://github.com/markjaquith/typesafe-ai-playground?utm_source=gemini) | Rust製CLI環境。個人健康情報（PHI）検知、コメント品質評価、トーン分析、業界分類などのテンプレートを内包。                                                              |
| Prism                  | [irfndi/prism-liquidity-agent](https://github.com/irfndi/prism-liquidity-agent?utm_source=gemini)             | クオンツ・DeFi流動性解析エージェント。プール内のToxic Flow、市場圧力、平均回帰傾向、流動性分布をJevで判定するアドバイザリー基盤。                                     |
| 1v1 Jev                | [emrickgarrett/OneVOneJev](https://github.com/emrickgarrett/OneVOneJev?utm_source=gemini)                     | 9Hzの超低遅延ループでFPSゲームの移動、照準（ADS）、射撃、ジャンプをJevがミリ秒単位で判断・操作するリアルタイム実証実験。                                              |
| TypeSafe on Neon       | [andrelandgraf/typesafe-on-neon](https://github.com/andrelandgraf/typesafe-on-neon?utm_source=gemini)         | Neonサーバレス環境向けのモデルルーター。リクエストの性質をJevで事前判定し、Grok 4.6やGPT-6 Astraなどの実行モデルへ最適配分。                                          |

## **ハーネス自律最適化：NVIDIA SoL-Pi論文に見る実行時オーバーヘッドの排除**

エージェントの総性能は「Model（知能）+ Harness（実行制御機構）」で決定される12。知能の高いモデルを採用しても、ハーネスの設計が稚拙であれば、中間待機ターン、無駄なファイル再送、コンテキストの肥大化によって膨大なコストと時間が浪費される3。NVIDIAの研究チームが公開した論文『SoL-Pi: Recursively Scaling Auto-Research Loops for Efficient Agent Harness』（arXiv:2609.20519）は、ハーネス層に対して自律研究（Auto-Research）ループを再帰的に適用し、152個の仮説から選抜・淘汰を繰り返して特定した4つの高効率メカニズムを提示している3。

51件の長時間複雑タスクからなる「EdgeBench」において、SoL-PiはGPT-5.6 SolおよびOpus 5上で基準タスク解決スコアの94%を維持しつつ、記録されたトークントラフィックを44.7%〜49.0%削減し、API課金を約3分の1削減した3。金額換算では、CodexやClaude Codeの標準ハーネス比で1時間あたり8.75ドル〜13.50ドル、Piのベースラインハーネス比でも4.36ドル〜5.71ドルのコスト削減を達成している3。

&nbsp;

| メカニズム名                    | 介入レイヤー       | 動作原理とシステム設計                                                                                                                                                                                             | 削減されるオーバーヘッド                                                                                                                  |
| :------------------------------ | :----------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------- |
| **Action Fusion**               | ツール実行制御     | ファイル編集（edit/write）とそれに続く動作検証コマンド（test/build）を単一のツールリクエストに融合。ハーネスがローカルで両者を連続実行し、1つの観測結果として返却6。                                               | 編集完了後の「結果待機 → コマンド発行」という不要な中間モデル往復ターンを完全排除（全ターンの12.3%を占める冗長遷移を解消）6。             |
| **Online Context Compact**      | コンテキスト圧縮   | サブタスク（Plan Step）の完了境界でのみ圧縮を評価。残存タスク量と過去の消費速度から将来のリクエスト数を予測し、プロンプトキャッシュ書き換えコストを節約量が上回る場合のみ圧縮を発火3。                             | 頻繁すぎる圧縮によるプロンプトキャッシュ無効化（API料金スパイク）を防ぎ、経済的損益分岐点を満たすタイミングでのみ最適圧縮6。              |
| **ObservationPack**             | 観測値ハンドリング | 10 KiBを超えるツール出力をローカルに退避。直後の2リクエストまでは全文をコンテキストに渡すが、3リクエスト目以降は固定ポインタ（Stable Handle）と先頭・末尾の抜粋に置換。必要な場合はページ単位でオンデマンド取得6。 | 1度参照されたきり使われない数千行のコマンド出力が、以降の全ターンでコンテキストへ無駄に再送され続ける現象を遮断6。                        |
| **Evidence-Preserving Reducer** | 委任・ログ要約     | 4 KiB以上のビルド/テストログを廉価な小型モデルに渡し、必要証拠のみを抽出した要約受領書（Receipt）を作成。決定論的検証器が引用行の原文完全一致を照合し、不一致や資格情報検出時は原本へ即座にフォールバック3。       | フロンティアモデルが高額なトークンを投じて長大なスタックトレースを精読するコストを排除しつつ、要約モデルのハルシネーションを完全に防止3。 |

SoL-Piの設計思想における特筆すべき点は、Piフレームワークのコアコードに一切のパッチを当てず、公開拡張APIのみを用いて構築されていることである3。すべての機能はオプトイン形式であり、元データはローカルに保持されるため、障害発生時も即座に安全側の挙動へフォールバックする耐障害性を備えている3。

## **コンテキスト肥大化の克服：コードベース・ナレッジグラフとメモリ仮想化**

エージェントがファイルツリーを把握するために ls や grep を繰り返す探索パターンは、トークン消費の大部分を占め、本来の推論能力を圧迫する7。最新のコードベース管理スタックは、静的構文解析（AST）によってコードの依存グラフを事前に構築し、エージェントが求めるシンボルと文脈のみをオンデマンドで注入するアプローチを確立している7。

&nbsp;

| ツール / リポジトリ                                                                                                                   | 提供元 / 特徴                    | 技術的アプローチと仕組み                                                                                                                                                            | 定量効果・性能指標                                                                                                      |
| :------------------------------------------------------------------------------------------------------------------------------------ | :------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------- |
| **Graft** [NanoNets/Graft](https://github.com/NanoNets/Graft?utm_source=gemini) (trailhq/Graft)8                                      | NanoNets / trailhq TypeScript製8 | tree-sitterにより21言語のコードベースを解析し、サブシステムや概念単位でリンクされたMarkdownグラフ（graft/）をローカルキャッシュとして生成。Claude Code等のフックにネイティブ結合8。 | ツール呼び出し46%減、非キャッシュ入力トークン42%減、セッション所要時間60%短縮（15.8秒 vs 39.8秒）18。                   |
| **codebase-memory-mcp** [DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp?utm_source=gemini) \[cite: 7\] | DeusData 158言語対応7            | tree-sitterを用いて関数、クラス、コールチェーン、HTTPルートを永続ナレッジグラフ化。14のMCPツールを通じてエージェントに必要な構造情報のみをミリ秒で返却7。                           | 5つの典型的な構造クエリにおいて、通常探索（約412,000トークン）に対し3,400トークンで完了（99%以上の削減）7。             |
| **context-mode** [mksglu/context-mode](https://github.com/mksglu/context-mode?utm_source=gemini) \[cite: 4\]                          | mksglu 17プラットフォーム対応4   | ツール出力をコンテキスト外のサンドボックスで捕捉。セッション履歴をSQLite+FTS5に格納しBM25検索でオンデマンド復元。コードを直接実行させて集計結果のみを出力させる原則を強制4。        | ツール出力データサイズを315 KBから5.4 KBへ圧縮（98%削減）。47回のファイル読込（700 KB）を1回のJS実行（3.6 KB）に置換4。 |
| **PageIndex** [VectifyAI/PageIndex](https://github.com/VectifyAI/PageIndex?utm_source=gemini)                                         | VectifyAI                        | ツリー構造ベースのRAG。文書の階層的論理構造を維持したままインデックス化し、エージェントが長大なドキュメントの文脈を論理的に追跡できるように支援。                                   | 長大な仕様書や設計書に対する文脈喪失とハルシネーションの防止。                                                          |
| **Letta** [letta-ai/letta](https://github.com/letta-ai/letta?utm_source=gemini)                                                       | Letta (旧MemGPT)                 | インコンテキストの短期記憶、外部DBの長期記憶（Archival）、履歴記憶（Recall）を分離管理する階層型メモリ管理エージェント基盤。                                                        | 無制限のセッション継続性とエージェントの長期自己整合性の維持。                                                          |
| **llm_wiki** [nashsu/llm_wiki](https://github.com/nashsu/llm_wiki?utm_source=gemini) \[cite: 22\]                                     | nash_su Karpathyパターン22       | ドキュメント群を自律更新型の相互リンクMarkdown Wikiへ段階的にコンパイル。ベクトル検索（オプション）とグラフ構造解析（Louvain法）を併用22。                                          | 検索のたびに都度ゼロから合成するRAGと異なり、事前に整理された知識を参照することで検索再現率を58.2%から71.4%に改善22。   |

コードベースの探索においては、エージェントにファイル全体を読ませるのではなく、まずGraftやcodebase-memory-mcpのグラフから構造的シンボルを特定させ、context-modeのサンドボックススクリプト実行でピンポイントに値を取り出させる多段階パイプラインを組むことが、コンテキスト節約の決定的な最適化手法となる4。

## **コーディングエージェントの規律制御とフルスタックスキル基盤**

自律コーディングエージェントが失敗する根本原因は、生成コードの構文エラーではなく、「テストを書かずに実装を始める」「根本原因を調査せずに対症療法パッチを当てる」「完了確認を行わずにタスク終了を宣言する」というプロセスの短絡化にある24。これを矯正するために、開発手法やワークフローをMarkdownやプラグインとして注入するスキルフレームワークが必須となる25。

### **obra/superpowers によるエンジニアリング規律の強制**

GitHubスター288k超を記録する obra/superpowers は、エージェントに対する規律強制フレームワークの事実上の業界標準である26。Claude Code、Codex CLI、Cursor、Gemini CLI等にインストールすることで、プロセスの省略を構造的に拒否させる25。

&nbsp;

| フェーズ / コマンド                                  | 規律化メカニズムと厳格なルール                                                                                                     | 防止されるアンチパターン                                                                         |
| :--------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------- |
| **要件定義** /superpowers:brainstorm \[cite: 29\]    | ソクラテス式対話により、曖昧な要件を深掘り。複数の実装方針、トレードオフ（速度・保守性・複雑度）を提示し、合意した設計書を生成25。 | 仕様が不十分なまま推測で実装を開始し、後から大幅な手戻りが発生する事態を未然に防止24。           |
| **計画策定** /superpowers:write-plan \[cite: 29\]    | 変更対象の完全なファイルパス、具体的な修正コード、検証コマンド、ロールバック方針を含む厳密な実装計画書を作成29。                   | 抽象的なTODOリストだけを作成し、途中で文脈や実装手順を見失うドリフトを防止29。                   |
| **分散実行** /superpowers:execute-plan \[cite: 29\]  | タスクごとに独立したサブエージェントを起動。各タスク完了時に「仕様準拠確認」と「コード品質確認」の2段階レビューを強制通過29。      | 長時間セッションによるコンテキストの汚染と、エージェントの自己評価過信による欠陥見逃しを排除25。 |
| **TDD強制** （テスト駆動開発）25                     | 「RED（失敗テスト作成） → RED確認（必須実行） → GREEN（最小限の実装） → GREEN確認（必須実行） → REFACTOR」の順序を強制25。         | テストを書かずに実装コードだけを改変し、既存の挙動を破壊するリグレッションを完全に防止25。       |
| **体系的デバッグ** systematic-debugging \[cite: 28\] | 4段階プロセス（根本原因の調査 → 正常箇所との差分分析 → 単一仮説の最小検証 → 根本修正と再発防止テスト追加）を厳格に順守25。         | エラーログの表層だけを見て不要なパッチを乱発し、コードベースをさらに複雑化させる悪循環を防止25。 |

### **開発サイクルを完結させる10大スキルスタック（合計801万ダウンロード）**

開発プロセスの全工程をカバーし、発見から本番化までのループを完結させる主要スキル群は以下の通りである。

> 1. **find-skills** ([vercel-labs/skills](https://github.com/vercel-labs/skills?utm_source=gemini)): 必要な機能や専門スキルを中央レジストリからワンコマンドで検索・インストール。
> 2. **grill-me** ([mattpocock/skills](https://github.com/mattpocock/skills?utm_source=gemini)): エージェントが開発者に対して連続で鋭い質問を投げかけ、要求仕様の曖昧さや論理の穴を徹底的にストレステスト。
> 3. **frontend-design** ([anthropics/skills](https://github.com/anthropics/skills?utm_source=gemini)): プロダクション品質のUI/UX原則、アクセシビリティ、モダンなデザイントークンを注入。
> 4. **agent-browser** ([vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser?utm_source=gemini)): エージェント自身にヘッドレスブラウザの操作、DOM探索、スクリーンショット取得機能を提供。
> 5. **prototype** ([mattpocock/skills](https://github.com/mattpocock/skills?utm_source=gemini)): 策定された設計から最短の手数で動く最小限のモックアップコードを迅速に出力。
> 6. **diagnosing-bugs** ([mattpocock/skills](https://github.com/mattpocock/skills?utm_source=gemini)): スタックトレースや再現ログから不具合の発生源と根本原因を論理的に特定。
> 7. **skill-creator** ([anthropics/skills](https://github.com/anthropics/skills?utm_source=gemini)): 成功した一連のプロンプトとワークフロー手順を自動解析し、次回以降再利用可能な新規スキルファイルとしてパッケージ化。
> 8. **image-to-code** ([leonxlnx/taste-skill](https://github.com/leonxlnx/taste-skill?utm_source=gemini)): UIのスクリーンショットやデザイン画像から、ピクセル精度で高品質なフロントエンドコードを自動生成。
> 9. **subagent-driven-development** ([obra/superpowers](https://github.com/obra/superpowers?utm_source=gemini)): 親エージェントがタスクを独立作業単位へ分割し、クリーンなコンテキストを持つ子エージェント群へ分散委譲29。
> 10. **mcp-builder** ([anthropics/skills](https://github.com/anthropics/skills?utm_source=gemini)): 外部APIや社内スクリプトを即座にModel Context Protocol（MCP）準拠のツールサーバーとして実装・接続。

### **コーディング体験と出力品質を高める専用ツール**

&nbsp;

| ツール / リポジトリ                                                                                                                   | 開発者 / 分類                     | 技術的特徴と機能                                                                                                                    | 導入効果                                                                                     |
| :------------------------------------------------------------------------------------------------------------------------------------ | :-------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------- |
| **gstack** [garrytan/gstack](https://github.com/garrytan/gstack?utm_source=gemini) \[cite: 30, 31\]                                   | Garry Tan (YC) 役割分担スタック31 | CEO、Designer、Eng Manager、Release Manager、Doc Engineerなど、職能ごとに特化した23種類のオピニオンツール群をエージェントに統合31。 | 単一のコーディング補助を超え、エンジニアリングチーム全体の役割分担をエージェント上で再現31。 |
| **diagram-design** [cathrynlavery/diagram-design](https://github.com/cathrynlavery/diagram-design?utm_source=gemini) \[cite: 33, 34\] | Cathryn Lavery 図表設計スキル33   | 38種類の編集品質ダイアグラムテンプレート集。外部依存関係ゼロの純粋なHTML+SVGを出力し、Mermaidの描画崩れや重いJSライブラリを排除33。 | エージェントがGit差分（diff）として直接認識・編集可能な高品位アーキテクチャ図の自動生成36。  |
| **i-have-adhd** [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd?utm_source=gemini) \[cite: 37, 38\]                        | ayghri 出力制御スキル37           | エージェントの前置き、挨拶、冗長な思考プロセスの出力を破棄させ、次に実行すべきコマンドとコード差分のみを即座に提示38。              | ターミナルの視認性を極大化し、不要な出力トークン消費を抑制38。                               |
| **Agent Skills** [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills?utm_source=gemini)                              | Addy Osmani スキル集              | GoogleのAddy Osmaniによる、コーディングエージェントに高度なエンジニアリング能力を与える再利用可能スキル集。                         | ベストプラクティスに基づく設計・リファクタリングパターンの定着。                             |
| **Pydantic AI** [pydantic/pydantic-ai](https://github.com/pydantic/pydantic-ai?utm_source=gemini)                                     | Pydantic フレームワーク           | PythonのPydanticチームが開発したエージェントフレームワーク。型安全性と構造化出力を静的に検証。                                      | ツールの引数や戻り値の型不整合による実行時エラーを未然に排除。                               |
| **Agent Lightning** [microsoft/agent-lightning](https://github.com/microsoft/agent-lightning?utm_source=gemini)                       | Microsoft 強化学習                | 強化学習と実行時フィードバックを用いてエージェントのプロンプトと判断経路を反復最適化する基盤。                                      | 複雑な特定業務におけるエージェントのタスク達成率の漸進的向上。                               |

## **エージェント実行基盤、オーケストレーション、および推論インフラ**

エージェントの活動領域をローカル環境からWeb、GUI、さらにはマルチエージェントの並列群知能へと拡張するためには、堅牢なオーケストレーション機構と高速な推論基盤が不可欠である。

### **統合ゲートウェイとマルチエージェント・オーケストレーション**

複数のモデルプロバイダを統合管理し、エージェントフリート（艦隊）を統制するためのリポジトリ群である。

- **OmniRoute** ([diegosouzapw/OmniRoute](https://github.com/diegosouzapw/OmniRoute?utm_source=gemini)): 352のプロバイダと1,200以上のモデルを単一のエンドポイントで抽象化する完全無料のAIゲートウェイ。動的なロードバランシングと自動フェイルオーバーを提供。
- **LiteLLM** ([BerriAI/litellm](https://github.com/BerriAI/litellm?utm_source=gemini)): OpenAI仕様の単一インターフェースで数百のLLMプロバイダを切り替え可能。コスト追跡、レート制限、フォールバックを一元管理。
- **Ruflo** ([ruvnet/ruflo](https://github.com/ruvnet/ruflo?utm_source=gemini)): Claude CodeおよびCodexを包摂するメタハーネス14。100以上の専門エージェント、自己学習型ベクトルメモリ、マシン間フェデレーション、GOAP（Goal-Oriented Action Planning）によるA\*探索タスク分解を統合14。
- **Orca** ([stablyai/orca](https://github.com/stablyai/orca?utm_source=gemini)): 複数のコーディングエージェントを並列に管理・ディスパッチし、大規模な機能追加やリポジトリ全体の移行を並行して推進するフリートマネージャー。
- **Agency agents** ([msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents?utm_source=gemini)): 16の業務領域に細分化された232の専門サブエージェント定義を格納したフルパッケージエージェンシースタック。
- **Paseo** ([getpaseo/paseo](https://github.com/getpaseo/paseo?utm_source=gemini)): 単一のワークフロー定義から複数のコーディングエージェントを調停し、複雑な依存関係を持つパイプラインを実行。
- **OpenMAIC** ([THU-MAIC/OpenMAIC](https://github.com/THU-MAIC/OpenMAIC?utm_source=gemini)): 清華大学によるマルチエージェント対話型クラスルーム基盤。エージェント同士の協調討議や教育シミュレーションをワンクリックで構築。
- **MCP-Agent** ([lastmile-ai/mcp-agent](https://github.com/lastmile-ai/mcp-agent?utm_source=gemini)): Model Context Protocol（MCP）を基軸とし、多種多様なMCPサーバーと連携するエージェントを簡易に構築するためのフレームワーク。
- **MCP Servers** ([modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers?utm_source=gemini)): Anthropic公式のリファレンスMCPサーバー群。GitHub、PostgreSQL、Puppeteer、Brave Search、ファイルシステム等への標準接続を提供。

### **Web操作、GUIグラウンディング、外部アクセス**

- **Browser Use** ([browser-use/browser-use](https://github.com/browser-use/browser-use?utm_source=gemini)): 視覚（Vision）と言語モデルを統合し、実ブラウザ上での自律的なクリック、フォーム入力、ページ遷移を実行する標準ライブラリ。
- **BrowserGym** ([ServiceNow/BrowserGym](https://github.com/ServiceNow/BrowserGym?utm_source=gemini)): ServiceNowが提供するWeb操作エージェントの評価・強化学習用サンドボックス環境。
- **Skyvern** ([Skyvern-AI/skyvern](https://github.com/Skyvern-AI/skyvern?utm_source=gemini)): 変更されやすいDOMセレクタに依存せず、コンピュータビジョンを用いてWeb自動化タスクを安定遂行する自動化エンジン。
- **Agent-S** ([simular-ai/Agent-S](https://github.com/simular-ai/Agent-S?utm_source=gemini)): コンピュータのグラフィカルユーザーインターフェース（GUI）を理解し、OSレベルのマウス・キーボード操作を代行する自律エージェント。
- **Agent-Reach** ([Panniantong/Agent-Reach](https://github.com/Panniantong/Agent-Reach?utm_source=gemini)): GitHub、Reddit、YouTube、X（旧Twitter）等のWebサービスに対し、公式APIキーの課金を回避しながら情報を取得・巡回するアクセスライブラリ。

### **推論実行インフラとローカルハードウェア最適化**

ローカルマシンやオンプレミスクラスター上でエージェントを高速稼働させるための基盤技術である。

- **llmfit** ([AlexsJones/llmfit](https://github.com/AlexsJones/llmfit?utm_source=gemini)): 実行マシンのCPU、システムRAM、GPU、VRAM、アクセラレータ構成（CUDA、Apple Silicon、ROCm、Intel OneAPI）を自動スキャンし、各量子化形式（GGUF、AWQ、EXL2）におけるモデルの適合度と推定トークン速度（TPS）を即座に判定するTUI/CLIプロファイラ40。
- **vLLM** ([vllm-project/vllm](https://github.com/vllm-project/vllm?utm_source=gemini)): PagedAttention技術によってKVキャッシュのメモリ断片化を極小化し、超高スループットを実現する大規模推論サービングエンジン。
- **SGLang** ([sgl-project/sglang](https://github.com/sgl-project/sglang?utm_source=gemini)): RadixAttentionを用いた構造化生成とKVキャッシュの再利用に特化し、エージェントワークフローで圧倒的なスループットを誇るフレームワーク。
- **TensorRT-LLM** ([NVIDIA/TensorRT-LLM](https://github.com/NVIDIA/TensorRT-LLM?utm_source=gemini)): NVIDIA GPU上でTensorコアの演算効率を極限まで引き出す推論最適化コンパイラおよびランタイム。
- **llama.cpp** ([ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp?utm_source=gemini)): 外部依存関係のない純C/C++実装。ローカルPCやエッジデバイス上で大規模モデルを効率的にCPU/GPUハイブリッド実行。
- **Ollama** ([ollama/ollama](https://github.com/ollama/ollama?utm_source=gemini)): llama.cppをベースに、オープンモデルのローカルダウンロード、管理、API提供を極めてシンプルなCLI操作で実現。
- **Milvus** ([milvus-io/milvus](https://github.com/milvus-io/milvus?utm_source=gemini)) / **Qdrant** ([qdrant/qdrant](https://github.com/qdrant/qdrant?utm_source=gemini)): 膨大なセマンティック埋め込みベクトルを高速検索可能な、エンタープライズ水準のOSSベクトルデータベース。
- **Ray** ([ray-project/ray](https://github.com/ray-project/ray?utm_source=gemini)): 機械学習ワークロードの大規模分散処理フレームワーク。複数GPUやマルチノード間での推論・強化学習パイプラインをスケーリング。
- **KServe** ([kserve/kserve](https://github.com/kserve/kserve?utm_source=gemini)): Kubernetes環境におけるモデルデプロイメントのデファクトスタンダード。オートスケーリングとカナリアデプロイをサポート。

### **専門領域特化型システムおよび学習リソース**

- **OpenMontage** ([calesthio/OpenMontage](https://github.com/calesthio/OpenMontage?utm_source=gemini)): コーディングエージェントを自律型動画制作スタジオに変えるOSS。プロンプトから企画、脚本、アセット生成、編集、レンダリングまでを自動パイプライン化42。
- **awesome-gpt-image-2** ([freestylefly/awesome-gpt-image-2](https://github.com/freestylefly/awesome-gpt-image-2?utm_source=gemini)): GPT-Image-2向けの精密なプロンプトエンジニアリング・スタイル制御ライブラリ。
- **gods-eye-view** ([bilawalsidhu/gods-eye-view](https://github.com/bilawalsidhu/gods-eye-view?utm_source=gemini)): 実データに基づくブラウザ完結型の軍事・地球観測スパイ衛星シミュレーター。
- **OpenCode** ([opencode-ai/opencode](https://github.com/opencode-ai/opencode?utm_source=gemini)) / **OpenCode Agents** ([remcocats/opencode-agents](https://github.com/remcocats/opencode-agents?utm_source=gemini)): ターミナル上で動作するオープンソースのコーディングエージェント本体および専門分野別エージェント集。
- **Learn Claude Code** ([shareAI-lab/learn-claude-code](https://github.com/shareAI-lab/learn-claude-code?utm_source=gemini)): Claude Codeと同等の自律コーディングエージェントをゼロから12本のPythonスクリプトで構築しながら内部メカニズムを学べる教育リポジトリ43。

## **AIエージェント開発環境を刷新する5段階統合実装ロードマップ**

既存のAIエージェント開発環境（Claude Code、Codex CLI、Cursor等）を段階的に改善し、コストとレイテンシを削減しながらタスク完遂力を最大化するための具体的な実装手順を策定した。

&nbsp;

| 段階                                                  | 主な達成目標                                   | 導入ツール・技術スタック                                   | 具体的な設定および実装内容                                                                                                                                                                                                                                                                                                                                                                                                  |
| :---------------------------------------------------- | :--------------------------------------------- | :--------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Phase 1: ハードウェア適合と統合ゲートウェイ構築**   | ローカル推論の最適化と全プロバイダの統一抽象化 | llmfit, OmniRoute, LiteLLM \[cite: 40, 41\]                | 1\. 開発マシン上で llmfit を実行し、搭載RAM/VRAMに最適な量子化モデル（GGUF/AWQ）を特定40。 2\. OmniRoute または LiteLLM をローカル常駐させ、全LLMリクエストを単一エンドポイント経由に集約。自動フェイルオーバーとトークン集計を有効化。                                                                                                                                                                                     |
| **Phase 2: コードベースグラフ化とコンテキスト隔離**   | ファイル総当たり探索の排除とコンテキスト保護   | Graft, codebase-memory-mcp, context-mode \[cite: 4, 7, 8\] | 1\. リポジトリ直下で graft init および graft build を実行し、tree-sitterによるAST Markdownキャッシュ（graft/）を生成8。 2\. codebase-memory-mcp を常駐させ、関数の依存関係をMCP経由で即時検索可能にする7。 3\. context-mode のフック（PreToolUse/PostToolUse）を設定し、長大なBash/テストログをサンドボックス内に隔離4。                                                                                                    |
| **Phase 3: ハーネス層の自己進化機構移植**             | 中間ターンの削減とログ再送オーバーヘッドの解消 | NVIDIA SoL-Pi パターン6                                    | 1\. **Action Fusion**: エージェントの設定（CLAUDE.md/AGENTS.md）に、ファイル編集とその検証コマンドを単一の複合呼び出しで行う規律を記述6。 2\. **ObservationPack**: 10 KiB超の出力はローカル退避させ、3ターン目以降はポインタと抜粋のみを渡すスクリプトをフックに配置6。 3\. **Evidence-Preserving Reducer**: 4 KiB以上のビルドログはローカル小型モデルで要約し、引用行の完全一致を検証した受領書のみをメインモデルへ渡す6。 |
| **Phase 4: System-1意思決定モデル（Jev）の統合**      | ルーティング、ガードレール、安全承認のミリ秒化 | typesafe-mcp, Jev Codex Router, Winnow \[cite: 1, 9\]      | 1\. typesafe-mcp を環境に登録し、Choice/Score/Noul の判定プリミティブをエージェントに公開1。 2\. Jev Codex Router パターンを取り入れ、タスク難易度を先行判定して廉価モデルと最上位モデルを動的配分。 3\. Winnow を導入し、コンテキストに残留する不要情報のガベージコレクションを自律実行。                                                                                                                                  |
| **Phase 5: エンジニアリング規律とフリート運用の確立** | TDD強制、ノイズ排除、マルチエージェント協調    | superpowers, i-have-adhd, Ruflo, Orca \[cite: 14, 26, 37\] | 1\. superpowers を導入し、RED/GREEN検証を伴うTDDと体系的デバッグを強制25。 2\. i-have-adhd を適用し、余計な会話文を排除して差分とコマンドのみを出力させる37。 3\. 大規模タスクにおいて Ruflo や Orca を起動し、設計、実装、テスト、レビューの専門サブエージェントを並列走査させてブランチを統合14。                                                                                                                         |

自律型エージェントの運用パラダイムは、プロンプトの対話的工夫という経験則の領域を脱し、System-1判定層の切り出し、ハーネスレベルでの不要ターン・不要観測値の体系的排除、そしてASTに基づく構造的コード理解という明確なシステム工学的基盤の上に再構築されつつある。本仕様書に網羅した各コンポーネントをレイヤーごとに正しく配置・統合することは、単にトークン費用やレイテンシを半減させるにとどまらず、長時間の自律セッションにおいてもハルシネーションや文脈崩壊を起こさない堅牢なプロダクション開発環境を実現するための必須の要件である。

#### **引用文献**

> 1. Jevとは｜TypeSafe AIの料金・仕様・使い方【2026年9月】, [https://uravation.com/media/jev-typesafe-ai-system-one-guide-2026/](https://uravation.com/media/jev-typesafe-ai-system-one-guide-2026/)
> 2. How to Use Jev: A practical guide to TypeSafe's System One model, [https://dev.to/valyuai/how-to-use-jev-a-practical-guide-to-typesafes-system-one-model-g5e](https://dev.to/valyuai/how-to-use-jev-a-practical-guide-to-typesafes-system-one-model-g5e)
> 3. 賢くするより無駄を削る。NVIDIAが開発したAIエージェントの劇的, [https://note.com/humble_bobcat51/n/n7256ef770914](https://note.com/humble_bobcat51/n/n7256ef770914)
> 4. context-mode \- AI Agents on GitHub (23.4k ) | SkillsLLM, [https://skillsllm.com/skill/context-mode](https://skillsllm.com/skill/context-mode)
> 5. Jev Explained: Typesafe AI's Non-Autoregressive System-1 Model, [https://www.mindstudio.ai/blog/jev-system-one-model-launch](https://www.mindstudio.ai/blog/jev-system-one-model-launch)
> 6. Recursively Scaling Auto-Research Loops for Efficient Agent Harness, [https://arxiv.org/html/2609.20519](https://arxiv.org/html/2609.20519)
> 7. Stop Making Your AI Coding Agent Grep Your Whole Repo, [https://dev.to/arshtechpro/stop-making-your-ai-coding-agent-grep-your-whole-repo-try-codebase-memory-mcp-4g8l](https://dev.to/arshtechpro/stop-making-your-ai-coding-agent-grep-your-whole-repo-try-codebase-memory-mcp-4g8l)
> 8. GitHub \- trailhq/Graft: Turbocharge Claude Code, Cursor, Codex, [https://github.com/trailhq/Graft](https://github.com/trailhq/Graft)
> 9. Jevとは？TypeSafe AIが発表した判断特化モデルの仕組み・料金, [https://www.ai-souken.com/article/what-is-jev](https://www.ai-souken.com/article/what-is-jev)
> 10. SoL-Pi: Recursively Scaling Auto-Research Loops for Efficient Agent, [https://academy.dair.ai/papers/sol-pi-recursively-scaling-auto-research-loops-for-efficient-agent-harness-2609.20519](https://academy.dair.ai/papers/sol-pi-recursively-scaling-auto-research-loops-for-efficient-agent-harness-2609.20519)
> 11. Jev（TypeSafe AI）はみんなどうやって使っているのか？ \- Qiita, [https://qiita.com/hisashi-ito/items/3d8d26ea591009e7a58e](https://qiita.com/hisashi-ito/items/3d8d26ea591009e7a58e)
> 12. SoL-Pi: Scaling Auto-Research Loops for Efficient Agent Harnesses, [https://github.com/NVlabs/SoL-Pi](https://github.com/NVlabs/SoL-Pi)
> 13. GitHub \- ai-boost/awesome-harness-engineering, [https://github.com/ai-boost/awesome-harness-engineering](https://github.com/ai-boost/awesome-harness-engineering)
> 14. GitHub \- ruvnet/ruflo, [https://github.com/ruvnet/ruflo](https://github.com/ruvnet/ruflo)
> 15. r/LocalLLaMA on Reddit: Pi Agent Users \- Nvidia Released Sol-Pi, [https://www.reddit.com/r/LocalLLaMA/comments/1wcujgg/pi_agent_users_nvidia_released_solpi_a/](https://www.reddit.com/r/LocalLLaMA/comments/1wcujgg/pi_agent_users_nvidia_released_solpi_a/)
> 16. SoL-Pi: Scaling Auto-Research Loops for Efficient Agent Harnesses, [https://nvlabs.github.io/SoL-Pi/](https://nvlabs.github.io/SoL-Pi/)
> 17. Reduce Claude Code Costs & Improve Performance with Graft, [https://www.reddit.com/r/ClaudeWorkflows/comments/1vef933/workflow_reduce_claude_code_costs_improve/](https://www.reddit.com/r/ClaudeWorkflows/comments/1vef933/workflow_reduce_claude_code_costs_improve/)
> 18. Graft for AI Agents: Map Your Codebase with Markdown \- IT-Connect, [https://www.it-connect.tech/graft-the-open-source-tool-that-maps-your-code-for-ai-agents/](https://www.it-connect.tech/graft-the-open-source-tool-that-maps-your-code-for-ai-agents/)
> 19. NanoNets/Graft — Your codebase, as a graph. Clone \#Shorts, [https://www.youtube.com/shorts/PbACu050jG4?vl=it](https://www.youtube.com/shorts/PbACu050jG4?vl=it)
> 20. graft 0.16.0-1 (x86_64) \- Arch Linux, [https://archlinux.org/packages/extra/x86_64/graft/](https://archlinux.org/packages/extra/x86_64/graft/)
> 21. Context Mode | MCP Servers \- LobeHub, [https://lobehub.com/mcp/mksglu-context-mode](https://lobehub.com/mcp/mksglu-context-mode)
> 22. GitHub \- nashsu/llm_wiki: LLM Wiki is a cross-platform desktop, [https://github.com/nashsu/llm_wiki](https://github.com/nashsu/llm_wiki)
> 23. What is the difference between llm_wiki and RAG? I tried it out ... \- note, [https://note.com/hokosaki_inc/n/n87c17ce1b834?hl=en](https://note.com/hokosaki_inc/n/n87c17ce1b834?hl=en)
> 24. Superpowers by obra: What It Is and How to Use It to Improve AI, [https://www.c-sharpcorner.com/article/superpowers-by-obra-what-it-is-and-how-to-use-it-to-improve-ai-coding/](https://www.c-sharpcorner.com/article/superpowers-by-obra-what-it-is-and-how-to-use-it-to-improve-ai-coding/)
> 25. AIコーディングエージェントの弱点を補う「obra/superpowers」, [https://tech-lab.sios.jp/archives/52268](https://tech-lab.sios.jp/archives/52268)
> 26. Superpowers: Skills Framework Reshaping AI Dev \- Termdock, [https://www.termdock.com/en/blog/superpowers-framework-agent-skills](https://www.termdock.com/en/blog/superpowers-framework-agent-skills)
> 27. obra/superpowers \- 288.7k Stars · Global Rank \#12, [https://www.star-history.com/obra/superpowers/](https://www.star-history.com/obra/superpowers/)
> 28. obra/superpowers: An agentic skills framework & software ... \- GitHub, [https://github.com/obra/superpowers](https://github.com/obra/superpowers)
> 29. I Gave Claude Code a Brain. It's Called Superpowers \- Medium, [https://medium.com/@anilmathewm/i-gave-claude-code-a-brain-its-called-superpowers-and-it-has-150-000-github-stars-for-a-reason-16c4074a9209](https://medium.com/@anilmathewm/i-gave-claude-code-a-brain-its-called-superpowers-and-it-has-150-000-github-stars-for-a-reason-16c4074a9209)
> 30. garrytan/gstack \- 133.5k Stars · Global Rank \#76, [https://www.star-history.com/garrytan/gstack/](https://www.star-history.com/garrytan/gstack/)
> 31. GitHub \- garrytan/gstack: Use Garry Tan's exact Claude Code setup, [https://github.com/garrytan/gstack](https://github.com/garrytan/gstack)
> 32. gstack とは — Claude Code を仮想エンジニアリングチームに, [https://note.nec-solutioninnovators.co.jp/n/n10e901edfdb9](https://note.nec-solutioninnovators.co.jp/n/n10e901edfdb9)
> 33. diagram-design \- AI Agents on GitHub (40.9k ) | SkillsLLM, [https://skillsllm.com/skill/diagram-design](https://skillsllm.com/skill/diagram-design)
> 34. cathrynlavery/diagram-design \- 41k Stars · Global Rank \#687, [https://www.star-history.com/cathrynlavery/diagram-design](https://www.star-history.com/cathrynlavery/diagram-design)
> 35. Cathryn Lavery cathrynlavery \- GitHub, [https://github.com/cathrynlavery](https://github.com/cathrynlavery)
> 36. Why diagram-design is a Great Fit for AI Agents｜株式会社ホコサキ, [https://note.com/hokosaki_inc/n/neb8d1c836caa?hl=en](https://note.com/hokosaki_inc/n/neb8d1c836caa?hl=en)
> 37. Analyze ayghri/i-have-adhd \- OSSInsight, [https://ossinsight.io/analyze/ayghri/i-have-adhd](https://ossinsight.io/analyze/ayghri/i-have-adhd)
> 38. GitHub \- ayghri/i-have-adhd: A skill to stop your coding agent from, [https://github.com/ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd)
> 39. GitHub \- ayghri/i-have-adhd \- Amit Gawande's Devlog, [https://dev.amitgawande.com/2026/github-ayghri/i-have-adhd](https://dev.amitgawande.com/2026/github-ayghri/i-have-adhd)
> 40. 'llmfit' is a terminal tool that teaches you the appropriate AI model, [https://gigazine.net/gsc_news/en/20260308-llmfit/](https://gigazine.net/gsc_news/en/20260308-llmfit/)
> 41. GitHub \- AlexsJones/llmfit: Hundreds of models & providers. One, [https://github.com/AlexsJones/llmfit](https://github.com/AlexsJones/llmfit)
> 42. OpenMontage とは｜AI動画制作を自律実行するOSS \- 秋霜堂株式会社, [https://syusodo.co.jp/tech-blog/articles/repo-calesthio-OpenMontage](https://syusodo.co.jp/tech-blog/articles/repo-calesthio-OpenMontage)
> 43. shareAI-lab/learn-claude-code: 从零开始动手实现AI Agent, [https://hellogithub.com/repository/shareAI-lab/learn-claude-code](https://hellogithub.com/repository/shareAI-lab/learn-claude-code)
