---
name: codegraph-graphify
description: codegraph (MCP) と graphify (Python) を組み合わせてコードベースを高速・深く理解するコツ集。シンボル精度が必要なときはcodegraph、コミュニティ/意味的繋がりはgraphify、と使い分ける。
trigger: /codegraph-graphify
---

# codegraph × graphify 組み合わせ運用

## ツールの役割分担

| 観点 | codegraph | graphify |
|------|-----------|----------|
| **インデックス** | `.codegraph/` (SQLite, tree-sitter) | `graphify-out/graph.json` (NetworkX) |
| **クエリ精度** | シンボル名で一意に特定 | キーワードマッチ（曖昧さあり） |
| **得意領域** | call chain・影響範囲・callers/callees | コミュニティ・横断的繋がり・セマンティクス |
| **更新コスト** | インクリメンタル自動（MCP常時稼働） | `--update` 実行（LLMコスト発生） |
| **対象ファイル** | コードのみ | コード・ドキュメント・論文・画像 |
| **出力** | MCPツール回答 | HTML・Obsidian vault・JSON・レポート |

---

## ステータス確認（作業前に必ず実行）

```bash
# codegraphインデックスの有無
codegraph status

# graphifyグラフの有無
python3 -c "from pathlib import Path; print('OK' if Path('graphify-out/graph.json').exists() else 'NOT FOUND')"
```

どちらも存在しない場合は以下で初期化：

```bash
# codegraphインデックス構築
codegraph init -i

# graphifyグラフ構築（コードのみなら高速、ドキュメント混在は--mode deepも検討）
/graphify .
```

---

## 判断フロー：どちらを使うか

```
質問を受けたら：

1. 「関数/メソッド/型の名前が分かっている」→ codegraph優先
   → codegraph_search で名前検索
   → codegraph_trace / codegraph_callees / codegraph_callers で辿る

2. 「概念・設計・アーキテクチャを知りたい」→ graphify優先
   → /graphify query "..." でBFS/DFS探索
   → graphify-out/GRAPH_REPORT.md のGod Nodes・Surprising Connections を参照

3. 「変更の影響範囲を調べたい」→ codegraph → graphifyの順
   → codegraph_impact でダイレクトな影響列挙
   → graphifyでコミュニティを確認して「どのモジュール群に波及するか」を把握

4. 「コードとドキュメント/設計書をまたいで調べたい」→ graphify専用
   → codegraphはコードのみ対象。ドキュメント・READMEの意味的関連はgraphifyで

5. 「呼び出しパスを一発で得たい」→ codegraph_trace
   → codegraph_trace は経路上の全関数ボディをインラインで返す（Read/Grepより速い）
```

---

## コンボパターン

### パターン1: 新規コードベースのオンボーディング

**目的**: 全体を素早く掴む

```
Step 1 (graphify) — 全体像
  /graphify . --mode deep
  → GRAPH_REPORT.md の「God Nodes」と「Suggested Questions」を読む
  → コミュニティ名を把握（例: "Auth Layer", "DB Access", "HTTP Router"）

Step 2 (codegraph) — 入口関数を特定
  codegraph_search "main" → エントリポイント確認
  codegraph_callees "main" → 最初の呼び出しツリーを展開

Step 3 (graphify query) — コミュニティをまたぐ繋がりを探索
  /graphify query "認証はどのモジュールに依存しているか"
  → Surprising Connections で想定外の依存を発見
```

### パターン2: バグ調査・デバッグ

**目的**: 症状から原因関数まで辿る

```
Step 1 (codegraph_search) — 症状に関連するシンボルを特定
  codegraph_search "エラーメッセージのキーワード"
  → ヒットしたシンボルの完全修飾名を取得

Step 2 (codegraph_trace) — call chainを一括取得
  codegraph_trace "EntryFunc" "BuggyFunc"
  → 全経路をインラインボディ付きで取得（Read不要）

Step 3 (graphify) — 影響が広がるコミュニティを確認
  /graphify query "BuggyFuncが属するモジュール"
  → 修正時に影響するコミュニティを事前把握
```

### パターン3: リファクタリング計画

**目的**: 変更の影響範囲を正確に把握

```
Step 1 (codegraph_impact) — 直接影響
  codegraph_impact "RefactorTarget"
  → 変更対象に依存する全シンボル一覧

Step 2 (codegraph_callers) — 呼び出し元の全量
  codegraph_callers "RefactorTarget"
  → 呼び出し元ファイルとライン一覧

Step 3 (graphify path) — アーキテクチャ上の距離感
  /graphify path "RefactorTarget" "FarAwayModule"
  → 意外に近い依存パスが見つかることがある

Step 4 — 判断
  codegraphで「何が壊れるか（具体）」
  graphifyで「どのコミュニティが揺れるか（抽象）」
  → 両方確認してから変更開始
```

### パターン4: コードレビュー（PR確認）

**目的**: 変更が設計意図と整合しているか確認

```
Step 1 (codegraph_files) — 変更ファイルのシンボル一覧
  codegraph_files "path/to/changed/file.go"
  → 追加・変更されたシンボルを把握

Step 2 (codegraph_callers) — 変更シンボルを呼んでいる箇所
  変更したシンボルごとに codegraph_callers を実行
  → 影響を受けるテスト・ハンドラを列挙

Step 3 (graphify) — 設計パターンとの整合性
  /graphify query "変更ファイルが属するコミュニティの責務"
  → コミュニティの凝集度(cohesion)が下がっていないか確認
```

---

## ツール呼び出しの具体例

### codegraphツール（MCPで直接使用）

```
# シンボル検索
codegraph_search: { "query": "handleRequest" }

# 単一ノード詳細（calleesも返す）
codegraph_node: { "symbol": "pkg/handler.HandleRequest" }

# 呼び出し元一覧
codegraph_callers: { "symbol": "pkg/handler.HandleRequest" }

# 呼び出し先一覧
codegraph_callees: { "symbol": "pkg/handler.HandleRequest" }

# 影響範囲（変更したら何が壊れるか）
codegraph_impact: { "symbol": "pkg/handler.HandleRequest" }

# 2点間のcall path（ボディインライン付き）
codegraph_trace: { "from": "main.main", "to": "db.Query" }

# ファイルのシンボル一覧
codegraph_files: { "path": "pkg/handler/handler.go" }

# インデックス状態確認
codegraph_status: {}
```

### graphifyクエリ（Pythonで実行）

```bash
# BFSクエリ（広く探索）
/graphify query "認証ミドルウェアの依存関係"

# DFSクエリ（特定パスを追跡）
/graphify query "ユーザーIDはどのように伝播するか" --dfs

# 2ノード間の最短パス
/graphify path "HTTPHandler" "Database"

# ノードの詳細説明
/graphify explain "AuthMiddleware"

# トークン上限付きクエリ
/graphify query "DBアクセスパターン" --budget 1000
```

---

## 避けるべきパターン（アンチパターン）

### NG1: codegraphで解けるものをgraphifyに聞く

```
# 悪い例
/graphify query "processOrder関数は何を呼ぶか"

# 良い例
codegraph_callees: { "symbol": "processOrder" }
```

理由: codegraphは正確なシンボル名でO(1)回答。graphifyはキーワードマッチで誤ヒットする可能性がある。

### NG2: codegraphの回答後にRead/Grepで確認する

```
# 悪い例
codegraph_trace → その後 Read でボディを読む

# 良い例
codegraph_trace のみ（ボディは既にインライン）
```

理由: codegraph_traceは経路上の全ボディを返す。二重取得は無駄。

### NG3: インデックスなしでcodegraphを呼ぶ

```bash
# 作業前に必ず確認
codegraph status
# → "not initialized" なら codegraph init -i を実行してから再開
```

### NG4: graphifyをリアルタイムに使う

graphifyは**バッチ処理**。コード変更後すぐに`/graphify query`しても古いグラフを参照する。
変更後に `/graphify . --update` を実行してからクエリする。

---

## graphify --watch との組み合わせ

コードを頻繁に変更する開発セッション中は：

```bash
# バックグラウンドでgraphify watchを起動
python3 -m graphify.watch . --debounce 3 &

# codegraphはMCPでリアルタイム対応済み（常時稼働）
```

コードファイル変更 → graphifyが自動でAST再抽出 → codegraphも自動インデックス更新
→ 両方のクエリが常に最新状態を参照

---

## トークン予算の考え方

| クエリ種別 | 推奨ツール | トークンコスト |
|-----------|-----------|--------------|
| シンボル検索・call chain | codegraph | ~0（SQLiteクエリ、LLM不使用） |
| 影響範囲の確認 | codegraph_impact | ~0 |
| コミュニティ横断の質問 | graphify query | ~100-300 (graph traversal) |
| 初回グラフ構築 | /graphify . | 高（ファイル数×LLM抽出） |
| インクリメンタル更新 | /graphify --update | 変更ファイル分のみ |

**原則**: 精確なシンボルクエリにはcodegraph（ゼロコスト）、意味的探索にはgraphify（キャッシュ活用）。

---

## インデックス同期チェックリスト

新しいコードベースで作業を始めるとき：

- [ ] `codegraph status` → 未初期化なら `codegraph init -i`
- [ ] `ls graphify-out/graph.json` → なければ `/graphify .`
- [ ] git hook確認: `graphify hook status` → 未設定なら `graphify hook install`
- [ ] codegraphのMCPサーバーが起動しているか確認（settings.jsonに設定済みであれば自動）
