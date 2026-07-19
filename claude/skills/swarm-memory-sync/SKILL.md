---
name: swarm-memory-sync
description: >-
  swarm-loop 各層(Haiku探索群/秘書/Maker/Checker)の実行と人間との対話(Interactive 設計インタビュー等)
  を通じて `AGENTS.md`・`@fix_plan.md` に蓄積された「学び」のうち、一般化可能なものを
  `~/.claude/memory/`(auto-memory）へ蒸留するブリッジ。トリガー: `swarm-loop` Phase 5 GATE 完了時
  (AGENTS.md 追記の直後、内部呼び出し)、`swarm-loop` Phase 2 PLAN の Interactive 設計インタビュー
  終了時(内部呼び出し)、または人間による `/swarm-memory-sync` の明示招集(既存 AGENTS.md の遡及処理・
  任意タイミングでの手動実行)。境界条件: SKILL.md / hooks / SWARM.md 自体の行動規範変更は
  `swarm-evolve` の対象であり本 skill では行わない(本 skill はドメイン知識の記録のみを扱う)。人間承認
  は不要(知識の記録であり行動規範の変更ではないため)だが、一般化可能性の判定・重複チェックは
  `scripts/memory-guard.sh` による決定論的チェックを必ず経由する(SWARM.md §2/§6 が求める「決定論的
  ツールを第一権威とする」原則を LLM 自己判断のみに頼らず本 skill でも適用するため)。
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit]
user-invocable: true
disable-model-invocation: false
---

# swarm-memory-sync — ドメイン知識の蒸留（swarm-evolve と対）

## 位置づけ

`swarm-evolve`（SWARM.md §5）は「Skill 自体の行動規範」を進化させる。本 skill はそれとは異なる軸 —
「ミッション実行・人間対話で得た一般化可能なドメイン知識」を `~/.claude/memory/`（auto-memory）へ
蒸留する。swarm-evolve と違い、SKILL.md / hooks / SWARM.md の状態機械・閾値・禁止事項には一切触れない。
純粋な知識の記録であり、人間承認は不要（誤って書いても memory はいつでも Edit・削除できる可逆な操作）。

なお、Haiku 探索群・Maker・Checker 個々の生ログそのものを本 skill の入力にはしない。これらは
既に `swarm-secretary` の構造化レポートと `swarm-implement` の完了処理を経て `AGENTS.md` /
`@fix_plan.md` に要約済みであり、本 skill はその要約からさらに一般化可能な部分だけを抜き出す
（Observation Masking 原則、SWARM.md 不変条件を維持）。

`disable-model-invocation: false` は意図的な選択（`swarm-evolve` は SKILL.md/hooks 自体を書き換える
高警戒レベルのため `true` で人間の明示招集に限定している）。本 skill は auto-memory への記録のみで
可逆かつ低リスクなため、`swarm-loop` Phase 2/5 からの内部呼び出しを妨げないよう自然文からの起動を許可する。

## トリガーと入力ソース

1. **`swarm-loop` Phase 5 GATE からの内部呼び出し**（通常経路）: 今回のミッションの `AGENTS.md`
   新規追記行 + `@fix_plan.md` の `## Escalations / 学び` セクション全体 + `## Secretary Report` の
   Root Causes を入力とする。
2. **`swarm-loop` Phase 2 PLAN（Interactive 設計インタビュー終了時）からの内部呼び出し**: この時点では
   `AGENTS.md` / `@fix_plan.md` の学びはまだ記入されていないため、入力は代わりに直近の対話ターン
   （人間の設計判断・好み・制約の回答）そのものになる。件数が少ないため遡及処理のような一覧提示は
   不要で、手順 2〜5 をその場で 1 件ずつ適用してよい。
3. **人間による `/swarm-memory-sync` の明示招集**（遡及処理・任意タイミング）: 対象リポジトリの
   `AGENTS.md` 全体、または人間が指定した日付範囲を入力とする。

## 手順

1. **候補抽出** — 入力ソースから「学び」エントリを 1 件ずつ列挙する。
2. **一般化可能性の判定**（グローバル CLAUDE.md の auto-memory 運用基準をそのまま適用する。新しい
   基準を作らない）:
   - 除外: コードパターン・アーキテクチャ・ファイルパス（現在のコードを読めば分かる）、git 履歴、
     デバッグの解決手順そのもの（コミットメッセージで足りる）、CLAUDE.md に既述の内容、進行中タスクの
     一時的な状態、このミッション限りの固有事情。
   - 採用: このプロジェクト・この人間・このツール群について、次回以降のセッション（`swarm-loop` に
     限らない通常の会話も含む）で振る舞いを変えるべき一般的な事実・訂正・判断根拠。
   - 迷ったら「このメモリが無かったら次回同じ間違い・同じ手戻りが起きるか」を基準にする。
3. **4 分類**（既存 `~/.claude/memory/` の type をそのまま使う。新しい分類を作らない）:
   `user` / `feedback` / `project` / `reference`。判定基準は各 type の既存運用ルール（グローバル
   CLAUDE.md 記載）に従う。
4. **重複チェック（決定論的、必須）**（既存メモリの拡張を優先し、新規乱立を防ぐ）:

   ```bash
   ~/.claude/skills/swarm-memory-sync/scripts/memory-guard.sh <topic-keyword> [<topic-keyword> ...]
   ```

   トピックを表すキーワードを渡し、(a) `MEMORY.md` の行数/バイト数が自動ロード上限（200 行 / 25KB）に
   近いかの警告、(b) 既存メモリファイルの中でキーワードにマッチするものの一覧、を機械的に取得する。
   これは LLM の記憶・主観的な「重複してなさそう」という判断だけに頼らないための決定論的な下準備であり、
   出力を無視して新規ファイルを作らない。
   - マッチがあれば当該ファイルを `Read` で確認し、同一トピックなら **新規ファイルを作らず** `Edit` で
     更新する(追記・訂正・古い情報の置き換え)。
   - マッチが無い、または確認の結果トピックが異なると判断した場合のみ新規ファイルを作る。
5. **書き込み**:
   - メモリ本体: `~/.claude/memory/<name>.md`（frontmatter: `name` / `description` /
     `metadata.type`）。関連する既存メモリへ `[[name]]` でリンクする（特に対象プロジェクトの
     `project_*` メモリ、関連する `feedback_*` メモリ）。
   - インデックス: `~/.claude/memory/MEMORY.md` に 1 行追記（150 字以内）。`memory-guard.sh` が上限
     接近を警告した場合は、新規追記より既存エントリの簡潔化・統合を優先する。
6. **完了報告** — 何件抽出し何件書いた（新規作成 / 既存更新の内訳）か、何件を「一般化不可」として
   却下したかを簡潔に報告する。却下理由の例も 1〜2 件添える(判定基準の透明性のため、AGENTS.md の
   学びの3段階モデルにおける「機械化」の代わりに人間が判定基準を検証できるようにする)。

## 遡及処理(既存 AGENTS.md 全件からの移行)

人間による明示招集時、対象 `AGENTS.md` の全軌跡を読み、上記手順を 1 件ずつ適用する。既に
`~/.claude/memory/` に類似内容がある場合は新規作成せず更新に留める。大量件数になりやすいため、
書き込み前に「今回書く / 更新するメモリの一覧」を会話内に提示してから実行する(承認を求めるのでは
なく、可視性のため — 手順自体は人間承認なしで完結する)。

## 禁止事項

- SKILL.md / hooks / SWARM.md 自体の変更(それは `swarm-evolve` の対象)
- 単発事象・このミッション限りの詳細の記録(一般化不可なものを書かない — memory 肥大化の防止)
- `memory-guard.sh` を経由しない書き込み(既存メモリと重複する新規ファイルの作成を防ぐための必須
  決定論的チェックをスキップしない)
- コードを読めば分かること・git 履歴で追えることの記録
- Haiku 探索群の生ログ・Maker/Checker の生の試行錯誤ログをそのまま転記すること(構造化レポート・
  最終的な学びのみを対象にする)
