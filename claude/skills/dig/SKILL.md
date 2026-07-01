---
name: dig
description: コードベース深掘り分析→設計インタビュー→実装計画→自律実行の統合ワークフロー。ワークスペース隔離・codegraph/graphify分析・設計提案・TDAD・体系的デバッグ・コードレビュー・ブランチ完了まで一括対応。汎用開発手法はすべてdigで完走できる。
trigger: /dig
---

<!-- STATIC BLOCK — キャッシュ対象。動的情報は各Phase実行時に注入する -->

# /dig — Goal-Driven Deep Implementation Workflow

ユーザーの目標を達成するまで完走する統合ワークフロー。**Phase 0〜4 を順に実行する。**

**開始時にアナウンス:** "I'm using the dig skill to analyze the codebase and drive your goal to completion."

## モデル選択マトリクス

| 役割                   | モデル     | 備考                                                                                |
| ---------------------- | ---------- | ----------------------------------------------------------------------------------- |
| コードベース探索・grep | `haiku`    | Opusの1/20コスト                                                                    |
| 実装・テスト・レビュー | `sonnet`   | Opusの40%コスト、品質十分                                                           |
| 設計・計画・複雑推論   | `opusplan` | **Opus は4反復で最適解（Sonnet は10反復）。設計フェーズはOpusの方が総コストが低い** |
| 解決不可課題           | `opus`     | DeepResearch + 拡張思考を組み合わせる                                               |

**原則:** haiku→sonnet→opusplan→opus の順で昇格。タスクより高いモデルは使わない。

## 使い方

```
/dig <目標>   # Phase 0 から実行
/dig          # 目標未指定 → Phase 2 ヒアリングから開始
```

## モード選択（起動時に判定）

| モード       | 条件                               | 実行フェーズ     |
| ------------ | ---------------------------------- | ---------------- |
| **Quick**    | バグ修正・既知ファイルへの小変更   | Phase 3-4 直行   |
| **Research** | 調査・質問・設計相談のみ           | Phase 1-2 のみ   |
| **Full**     | 新機能・スコープ不明・複数システム | Phase 0-4 全実行 |

ゴールに `fix/bug/typo` → Quick。`what/how/analyze/research` → Research。それ以外 → Full。  
不明なら「Quick(Phase3-4直行)/Research(Phase1-2のみ)/Full(全Phase)のどれで進めますか？」と1問確認。

---

## Phase 0: ワークスペース準備

**隔離検出 → 作成 → ベースラインテスト** の順で実行する。

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
git rev-parse --show-superproject-working-tree 2>/dev/null  # サブモジュール確認
```

`GIT_DIR != GIT_COMMON`（サブモジュールでない）→ 隔離済み → Step 0-3へスキップ。  
`GIT_DIR == GIT_COMMON` → ユーザーに確認後:

```bash
# ネイティブツール(EnterWorktree)があれば最優先。なければ:
git check-ignore -q .worktrees 2>/dev/null || echo ".worktrees" >> .gitignore
git worktree add .worktrees/<branch-name> -b <branch-name>
```

**ベースラインテスト:** `go test ./...` / `cargo test` / `pytest` / `npm test`  
失敗時: 「<N>件の既存失敗があります。継続しますか？」とユーザーに確認する。

---

## Phase 1: コードベース分析（Explore Agent分離）

**目的:** Context Pollution を防ぎながらコードベースを理解する。Explore Agent を dispatch して JSON サマリーのみ受け取る。

### Step 1-1: インデックス確認（並列実行）

```bash
codegraph status 2>/dev/null || echo "CODEGRAPH_NOT_INITIALIZED"
python3 -c "from pathlib import Path; print('OK' if Path('graphify-out/graph.json').exists() else 'GRAPHIFY_NOT_FOUND')"
graphify hook status 2>/dev/null || echo "HOOK_NOT_SET"
```

未初期化の場合: `codegraph init -i` / graphify インストール + グラフ構築 / `graphify hook install`

### Step 1-2: Explore Agent dispatch（モデル: `haiku`）

```
Goal: <ユーザーの目標>

コードベース探索エージェント。**JSONサマリーのみ返すこと（詳細ログ・tool呼び出し禁止）。**

**「広く始め → 絞り込む」探索戦略を厳守する:**
- Pass 1: 3-5個の広いキーワード（ドメイン名・機能名・モジュール名）で概要を掴む
- Pass 2: Pass 1 の結果を踏まえ、具体的なシンボル・ファイル名に絞り込む

実行:
1. codegraph_search でGoalの広いキーワード検索 → Pass 2 で具体シンボルへ絞り込み → callers/callees/impact
2. graphify query "<Goal関連の概念>" --budget 1000 で意味的探索
3. graphify-out/GRAPH_REPORT.md の God Nodes と Surprising Connections を確認
4. 変更対象ファイルと対応テストファイルのマッピングを生成し /tmp/dig_testmap.json に保存
   形式: {"src/file.go": ["src/file_test.go"], ...}

返却フォーマット(このJSONのみ):
{"key_symbols":["file:line—説明"(max10)],"communities":["コミュニティ名—責務"],
 "reusable_patterns":["再利用できる実装"],"constraints":["制約・注意"],"unknowns":["不明点"],
 "impact_files":N}

**停止条件（必須）:** Pass 1・Pass 2 の探索と `/tmp/dig_testmap.json` の保存が全て完了し、上記 JSON を返した後に停止すること（それ以前は停止しない）。返却後の追加ツール呼び出し・コメントは一切禁止。
```

### Step 1-3: 結果を `/tmp/dig_analysis.json` に保存

コンテキストを軽量に保つ（Scratchpad外部化）。参照時のみ Read する。

### Step 1-4: モード昇格チェック（Phase 1 終了時）

Explore Agent の `impact_files` を使って起動時モードを補正する（降格はしない）:

- `impact_files ≥ 6` → Full モードに昇格
- `impact_files ≤ 2` かつ Quick 以外 → Quick に引き下げ

変更がある場合のみユーザーに通知してから Phase 2 へ進む。

---

## Phase 2: 設計インタビュー & 提案

**3段階:** 自動解決 → ユーザーヒアリング → 設計提案 & 承認ゲート

### 2-1: コードベース自動解決

codegraph/graphify で以下を先に解決する（解決済みはユーザーへの質問から除外）：

- 類似実装の有無 → `codegraph_search`
- テスト戦略 → 既存テストファイル確認
- 後方互換性制約 → `codegraph_impact`
- パフォーマンス要件 → ベンチマークファイル確認

### 2-2: ユーザーヒアリング

**質問前に必ずコードを読む:** 関連コードを事前に読み、コードベースから既に判断可能な情報は質問しない（2-1 で解決済みなら除外）。

**1回あたり1〜3個の関連質問をまとめて聞く。** 独立した話題は次ラウンドへ。外部ライブラリ情報が必要なら WebSearch で先に調べてから質問する。

**質問の具体化ルール（重要）:**

- 「設計はどうしますか？」禁止 → **選択肢・具体例を提示する**
  - ✗ 「エラーハンドリングはどうしますか？」
  - ✓ 「エラー時は `Result<T, E>` を返す / パニックする / ログのみ のどれを想定していますか？」
- 複数の解釈が成立する場合: サイレントに一方を選ばず選択肢を明示してから質問する

**優先度順に質問する（ブロッカー → 詳細の順）:**

1. **技術的設計判断**: ライブラリ選択・データ構造・API 設計（エンドポイント/型）が未決定
2. **ビジネス要件**: エッジケース挙動・エラー時のユーザー向け挙動・入力制約・成功/失敗基準が未定義
3. **既存コード整合性**: 型/API 互換性・命名規則・モジュール依存関係の不明点
4. **実装具体性**: ファイル変更対象・テスト戦略・ステップ粒度の不明点

**終了条件:** 全4観点で情報が揃う、またはユーザーが「十分」「OK」「もういい」等の終了意思を示す。

### 2-3: 設計提案（2-3アプローチ）

```
### アプローチ A: <名前>
概要: <2文> / メリット: / デメリット:
### 推奨: A — 理由: <なぜか>
どのアプローチで進めますか？
```

スコープ過大の場合: サブシステムに分解し最初のものだけ設計する。  
**ユーザー承認なしに Phase 3 へ進まない。**

### 2-4: 設計ドキュメント

**保存先:** `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`

```markdown
**Goal:** / **Architecture:** / **Tech Stack:** / **Success Criteria:** / **Scope:**
```

Spec Self-Review（インラインで修正）: Placeholderスキャン → 内部一貫性 → スコープ → 曖昧性

---

## Phase 3: 実装計画

**保存先:** `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`

**計画ヘッダー（必須）:**

```markdown
# [Feature] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development
> **Goal:** / **Architecture:** / **Model per task:** haiku(探索)/sonnet(実装)/opusplan(設計)
```

**タスク出力スキーマ（全サブエージェント共通）:**

```json
{
  "task_id": "N",
  "status": "DONE|DONE_WITH_CONCERNS|NEEDS_CONTEXT|BLOCKED",
  "files_changed": [],
  "tests_passing": true,
  "commit_sha": "abc",
  "concerns": "?",
  "blocker": "?"
}
```

**TDAD Iron Law:**

> 本番コードを書く前に失敗するテストを書く。テストなしに本番コードを書いたら削除して最初からやり直す。例外なし。

**タスク記述:** `task-template.md` を参照してタスクを記述すること。  
各タスクは **RED → Verify RED → GREEN → Verify GREEN → REFACTOR → Coverage 80%+** の順。  
Git checkpoints: `test: add reproducer for <X>` / `feat/fix: <X>` / `refactor: <X>`

**TDD Verification Checklist（完了前に全確認）:**

- [ ] 全ての新しい関数・メソッドにテストがある
- [ ] REDを目撃した（タイポ・構文エラーが理由ではない）
- [ ] 最小限の実装のみ（YAGNI。テストが要求しない機能を追加しない）
- [ ] 全テストがグリーン（既存テスト含む）
- [ ] カバレッジ80%+
- [ ] RED/GREEN git checkpoint が両方存在する

**テスト分類原則:** Unit(< 50ms, 純粋ロジック) / Integration(< 500ms, DB・API) / E2E(< 30s, クリティカルフロー)。モックは Integration/Unit 境界超えのみ。

**依存関係マップ:** 独立タスクを明示して並行実行を最大化する。

**計画自己レビュー:** スペックカバレッジ / Placeholderスキャン / 型・メソッド名の一貫性 の3点確認。

---

## Phase 4: 自律実装

計画を TodoWrite に全登録してから開始。**完走するまでユーザー確認不要**（ブロッカー時のみ停止）。

### 状態管理

```bash
echo '{"current_task":N,"completed":[],"failed":[],"circuit_open":[],"last_failure_sig":""}' > /tmp/dig_progress.json
```

**コンテキスト予算チェックポイント:** 完了タスク数が 10 を超えたら `/tmp/dig_snapshot.md` に現在の進捗・未完了タスクリスト・主要設計決定を保存し「コンテキストセーブポイントを作成しました」とユーザーに通知する（セッション再開時の文脈再構築用）。

### 並行実行（独立タスク）

Phase 3 の依存関係マップで **独立** と判定されたタスクは単一メッセージで複数 Implementer を同時 dispatch する:

```
# 同一メッセージに並べて送信
Agent(Implementer, task=A, context=...)
Agent(Implementer, task=B, context=...)
```

**動的ディスパッチ:** タスクが完了し次第、ブロック解除された後続タスクを即座に dispatch する（全並行タスクの完了を待たない）。

```
# 例: Task4 は Task1+2 に依存、Task3 は独立
dispatch [Task1, Task2, Task3]          # 同一メッセージで並行開始
→ Task1 完了 → Task4 の依存チェック: Task2 未完了 → 待機
→ Task2 完了 → Task4 の依存チェック: Task1 完了済み → Task4 を即 dispatch (Task3 と並行)
```

- **並行 Implementer の上限: 最大 5 同時。** 独立タスクが 5 超の場合は優先度順に 5 つを先行 dispatch し、完了次第次を補充（sliding window）。タスク数 ≤ 2 は逐次実行（overhead がメリットを上回る）。
- 共有ファイルを変更するタスクは並行させない
- PAX 出力が返ったタスクを即 Spec Reviewer へ（他の並行タスクを待たない）
- 1つでも BLOCKED → その依存後続タスクはブロック、他のタスクは継続

### Design-Sync ゲート（Phase 4 開始前に実行）

`docs/superpowers/specs/` と `docs/superpowers/plans/` を突合する:

- [ ] 全タスクのファイルターゲットが設計のアーキテクチャと矛盾しない
- [ ] 全タスクの Success Criteria が設計の成功基準にトレース可能
- [ ] 依存関係マップの前提（API 境界・型定義）が設計と一致

矛盾発見時: Phase 3 の該当タスクのみ修正して再開（Phase 2 再起動は不要）。

### タスク実行ループ

**役割別コンテキスト制限（最小コンテキスト原則）:**

| エージェント          | 渡すコンテキスト                     | 上限      |
| --------------------- | ------------------------------------ | --------- |
| Implementer           | タスクspec + 関連ファイルパス(max 5) | 2k tokens |
| Spec Reviewer         | タスクspec + `git diff HEAD~1`       | 2k tokens |
| Code Quality Reviewer | `git diff <BASE>..<HEAD>` のみ       | 2k tokens |

設計経緯・他タスク履歴・コメント・実装詳細は**渡さない**。

**0. 実行前: 複雑度ガード（Subagent dispatch スキップ判定）**

計画の `Complexity` フィールドに基づき Subagent 起動コストを回避する:

| Complexity | 判定基準                                                          | 実行方式                       | Model      | Max tool calls |
| ---------- | ----------------------------------------------------------------- | ------------------------------ | ---------- | -------------- |
| `trivial`  | 1ファイル・15行以下・新ロジックなし（設定変更・定数・リネーム等） | **オーケストレーター直接実行** | —          | —              |
| `simple`   | 30行以下・1関数変更・既存パターン踏襲                             | Subagent                       | `haiku`    | ≤10            |
| `standard` | 複数ファイル or 新ロジック導入                                    | Subagent                       | `sonnet`   | ≤30            |
| `complex`  | 複数システム or 新抽象化 or アルゴリズム設計                      | Subagent + Plan Approval       | `opusplan` | ≤80            |

`trivial` タスクはオーケストレーターが TDAD ステップ（RED→GREEN→REFACTOR）を直接実行し、PAX スキーマを自己生成してループを継続する。

**complex タスクの Plan Approval:** `complex` Implementer は「まず実装計画のみを書いて停止せよ。承認の `SendMessage` を受け取ってから実装を開始せよ」と指示する。オーケストレーターが計画を審査し承認後のみ実装開始。差し戻し時は計画修正で済む（Phase 2 再起動不要）。

**1. Implementer dispatch**（モデル: 上記ガード参照）

```
[タスクN の完全テキスト]
変更ファイル: <exact paths, max 5>
対応テスト: </tmp/dig_testmap.json から抽出, max 3>
Success Criteria: <テストコマンド + 期待出力>
ツール上限: <複雑度ガードの Max tool calls>
依存元ハンドオフ: </tmp/dig_task_M_handoff.md があれば参照>

出力:
- 通常: `ACTION | STATUS | KEY_DATA | BLOCKERS | NEXT`
  例: `feat:auth | DONE | files:2,tests:PASS | none | spec_review`
- テスト失敗時: `FAIL:<N>件,first:<TestXxx at file.go:42 — 失敗理由>,details:/tmp/dig_test_failures_N.txt`
- DONE 時の追加義務: `/tmp/dig_task_N_handoff.md` に変更要点・後続が読むファイル(max 3)・注意点を書く（50行以内）
- BLOCKED/CONCERNS 時のみ詳細 JSON も返す

制約（ワンライナー）: 変更はこのタスクにトレース可能なファイルのみ / 不明点は推測せず BLOCKED / ツール上限超過で BLOCKED

**停止条件（必須）:** 以下が全て完了した場合のみ停止すること（それ以前は停止しない、それ以降は何もしない）:
1. 全 TDAD ステップ完了（RED→Verify RED→GREEN→Verify GREEN→REFACTOR→Coverage 80%+）
2. `/tmp/dig_task_N_handoff.md` 書き込み完了
3. 上記出力フォーマット返却完了
NEXT フィールドはオーケストレーター用——自分が次フェーズを実行しないこと。
```

**JSONスキーマのみ受け取る（Observation Masking）— フルログをオーケストレーターに戻さない。**  
古い tool output はplaceholderに置換し、reasoning/action historyは保持する。  
大きな出力（テスト失敗詳細・diff等）は `/tmp/dig_task_N_*.txt` に書き込んでパスのみ返す。

| ステータス           | 対応                                                    |
| -------------------- | ------------------------------------------------------- |
| `DONE`               | Spec Reviewer へ                                        |
| `DONE_WITH_CONCERNS` | 軽微→Reviewへ、重要→修正指示                            |
| `NEEDS_CONTEXT`      | **SendMessage パターン**（下記参照）                    |
| `BLOCKED`            | デバッグプロトコル実行 → 解決しなければ Circuit Breaker |

**NEEDS_CONTEXT の SendMessage パターン:**

1. `NEEDS_CONTEXT: <具体的な不明点>` を受信
2. オーケストレーターが即座に解決（codegraph / Read / graphify — 新規 dispatch なし）
3. `SendMessage(agent_id, "<解決済みコンテキスト>")` で不足情報のみ注入
4. エージェントは自身のコンテキストを保持したまま再開（フルスペック再送不要）

→ SendMessage で解決できない場合（外部情報・設計判断が必要）のみ完全再 dispatch する。

**2. Spec Reviewer dispatch**（`sonnet`）

```
タスク仕様と実装(git diff HEAD~1)を照合。確認: 要件の不足/過剰/テスト通過。
出力: {"compliant":bool,"issues":["..."]}

**停止条件（必須）:** diff 全体のレビューを終え上記 JSON を返した場合のみ停止すること（それ以前は停止しない、返却後は何もしない）。
```

`compliant: false` → Implementer 修正 → 再dispatch（**最大3回**）  
3回後もcompliantでなければ **スペック修正（軽量）**: issues を分析 → `docs/superpowers/plans/` の該当タスクのみ修正 → 再dispatch 1回  
それでも解決しない場合のみ `/dig` を Phase 2 から再起動して設計し直す

**3. Code Quality Reviewer dispatch**（`sonnet`）

```bash
BASE_SHA=$(git rev-parse HEAD~1); HEAD_SHA=$(git rev-parse HEAD)
```

```
git diff <BASE_SHA>..<HEAD_SHA> を言語慣習・パフォーマンス・セキュリティ・可読性でレビュー。
出力: {"approved":bool,"issues":[{"severity":"critical|important|minor","desc":"..."}]}

**停止条件（必須）:** diff 全体のレビューを終え上記 JSON を返した場合のみ停止すること（それ以前は停止しない、返却後は何もしない）。
```

| 重大度             | 対応                                                                                                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| critical/important | 即修正 → 再dispatch（**最大3回**）。3回後も残れば **スペック修正（軽量）**: 該当タスクのみ修正 → 再dispatch 1回。それでも解決しない場合のみ `/dig` を Phase 2 から再起動 |
| minor              | 後続タスクにTODOとして持ち越し                                                                                                                                           |
| 指摘が誤り         | 技術的根拠でpushback（"You're right!" / "Great point!" 禁止）                                                                                                            |

pushback判断基準: 既存機能を壊す / YAGNI違反 / このスタックでは技術的に誤り / ユーザーのアーキテクチャ決定と矛盾

**4. 完了検証ゲート**  
完了宣言前に**このメッセージ内で**テストを実行する。「すべき」「おそらく」「見た感じ」禁止。証拠を示すか、黙るか。

**5. TodoWrite & progress更新 → 次のタスクへ**

---

### デバッグプロトコル（BLOCKED・テスト失敗時）

**REQUIRED SUB-SKILL: superpowers:systematic-debugging**

鉄則: **根本原因確認前に修正禁止。**

**テスト失敗の事前分類（D1 前に判定 — 失敗の最初の行で機械的に判定）:**

| 失敗分類         | 判定基準                              | 次アクション                               |
| ---------------- | ------------------------------------- | ------------------------------------------ |
| 実装エラー       | assertion / logic / undefined         | Implementer 修正（D1〜D4）                 |
| テスト定義エラー | setup / fixture / import error        | Spec Reviewer がテスト自体を確認           |
| 環境エラー       | network / permission / missing binary | オーケストレーターが環境確認 → 再 dispatch |

- **D1 根本原因調査:** エラー完全読み → 再現確認 → 最近の変更確認 → マルチコンポーネントなら各境界でログ追加して証拠収集
- **D2 パターン分析:** 動いている類似実装を探して差異を列挙（小さい差異も見落とさない）
- **D3 仮説と最小テスト:** 仮説1つ → 最小変更でテスト → 確認できたらD4。失敗したら新仮説（複数変更同時禁止）
- **D4 修正:** 失敗するテスト作成（TDAD Iron Law） → 根本原因を修正 → テスト通過確認

**3回以上失敗 → アーキテクチャ疑義。「もう1回試みる」禁止。`/dig` を Phase 2 から再起動してユーザーと設計を詰め直す。**

---

### Circuit Breaker

**エラー分類（リトライ前に判定）:**

| エラー種別 | 判定基準                                                     | 対応                                         |
| ---------- | ------------------------------------------------------------ | -------------------------------------------- |
| Transient  | ネットワーク / rate limit / タイムアウト                     | 通常リトライ（最大3回）                      |
| Permanent  | 存在しない関数名・型不一致・構文エラー・同一エラーの繰り返し | **即時 Circuit Breaker**（リトライ消費なし） |

**無進捗早期終了（回数に関わらず即 Circuit Breaker）:**

- 同一失敗シグネチャ（exception type + 失敗テスト名）が連続2回一致 → `/tmp/dig_progress.json` の `last_failure_sig` と照合
- `git diff` が実質ゼロ（空白・コメントのみの変更）
- 前回提案と意味的に同等（同じ関数・同じロジック変更）

**3回目失敗前の強制 Self-Reflection:**

```
- "What failed?": <具体的エラー>
- "Root assumption that was wrong?": <誤った前提>
- "Specific fix (not 'try harder')?": <仮説>
- "Repeating same mistake?": yes/no
```

`no` で新仮説あり → D3 仮説テスト 1 回のみ実行してから Circuit Breaker へ。  
`yes` → 即座に Circuit Breaker 開放。

**Circuit Breaker 処理:**

1. モデルアップグレード（haiku → sonnet → opusplan → opus）して再試行
2. タスクをサブタスクに分割して再試行
3. 解決しない場合のみユーザーエスカレーション

繰り返すエラー: `/tmp/dig_circuit_open.txt` に記録して後続サブエージェントに通知する。

---

### DeepResearch（必要時のみ）

```bash
WebSearch: "<lib> <ver> API reference" / "<error message> fix"
git clone --depth=1 <url> /tmp/research-<name>  # 参照後削除
graphify update .                                # コード変更後のグラフ更新
```

---

### 全タスク完了後（ブランチ完了処理）

**REQUIRED SUB-SKILL: superpowers:finishing-a-development-branch**

1. **今このメッセージで**テスト全通過を確認する（過去の実行結果を信頼しない）
2. git環境検出: `GIT_DIR` vs `GIT_COMMON`
3. オプション提示:
   ```
   1. <base-branch>にローカルマージ  2. Push + PR作成  3. このまま保持  4. 破棄
   ```
4. ワークツリークリーンアップ（Option 1, 4のみ、**必ずメインリポジトリルートから**実行）:
   ```bash
   MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
   cd "$MAIN_ROOT" && git worktree remove <path> && git worktree prune
   ```
   ※ dotfilesが作成した（`.worktrees/`・`worktrees/`・`~/.config/superpowers/worktrees/`配下）のみ削除。外部ツール作成のものは削除しない。
5. 一時ファイル削除: `rm -f /tmp/dig_*.json /tmp/dig_*.txt /tmp/dig_*.md`

### 停止条件

Circuit breaker後も解決不可 / 設計の根本見直し必要 / セキュリティリスク発見 / **全タスク完了（正常終了）**

---

## ツール使い分け

| 状況                       | ツール                                    | モデル          |
| -------------------------- | ----------------------------------------- | --------------- |
| シンボル名が分かる         | codegraph_search → callers/callees/impact | haiku(subagent) |
| 概念・設計・アーキテクチャ | graphify query                            | haiku(subagent) |
| 最新の外部情報             | WebSearch / WebFetch                      | —               |
| 参照実装の確認             | git clone /tmp/ → 参照後削除              | —               |
| 実装・テスト               | Implementer Subagent                      | sonnet          |
| スペック照合               | Spec Reviewer Subagent                    | sonnet          |
| 品質レビュー               | Code Quality Reviewer Subagent            | sonnet          |
| アーキテクチャ設計・計画   | オーケストレーター（自分）                | 継承            |

## 禁止事項

- **サブエージェントのフルログをオーケストレーターに返す** — Context Pollution。JSONスキーマのみ受け取る
- **Phase 1なしで即行動** — Explore Agentを先行させる
- **ユーザー承認なしに Phase 3 へ進む** — Step 2-3 の承認ゲートを通過する
- **「すべき」「おそらく」「見た感じ」で完了宣言** — 証拠を示すか黙るか
- **3回以上同じアプローチでリトライ** — Circuit Breakerを使う
- **Permanent エラー（構文エラー・存在しない関数名）をリトライで解決しようとする** — 即時 Circuit Breaker 開放
- **根本原因不明のまま修正** — superpowers:systematic-debugging の D1〜D4 を守る
- **レビュアーへの即同意・即実装** — 技術的検証後に実装。誤りなら根拠でpushback
- **一時ファイルをリポジトリルートに置く** — `/tmp/` 以下のみ
- **ワークツリー内から git worktree remove** — メインリポジトリルートから実行する
- **graphify をコード変更後すぐに使う** — `graphify update .` してからクエリ
- **不明点を推測して進む** — `BLOCKED: <不明点>` で止まってユーザーに確認する（Don't assume）
- **隣接コードの改善・整形・リファクタ** — 変更行はすべてタスクにトレース可能なこと（Surgical changes）
