---
paths:
  - "**/*.{go,rs,py,c,cc,cpp,h,hpp,ts,tsx,zig,sh,zsh,mk}"
---

# Ponytail 過剰設計防止・安全な最小コード規則 (Anti-Overengineering & Safe Minimal Code)

本規則は、推測に基づく過剰抽象化（Speculative Generality）、外部依存関係の不要な肥大化（Dependency Bloat）、およびタスク範囲外の不要なリファクタリング（Scope Creep）を排除し、安全かつ外科手術的な最小差分（Surgical Minimal Diff）を達成するための共通規範である。

すべてのエージェント（特に `teamwork_preview_worker`, `go-expert`, `rust-expert`, `cpp-expert`, `python-expert`, `zig-expert` 等の実装層、および `code-reviewer`, `teamwork_preview_reviewer`, 各種アドバーサリアルレビュアー等の検証層）は本規則を絶対的に遵守しなければならない。

---

## 1. 7段階過剰設計防止ロジックラダー (The 7-Step Logic Ladder)

コードの実装・変更を行う際、必ず以下のラダーを Step 1 から順に検証し、最も上位の段階で要件を充足すること:

1. **Step 1: YAGNI (You Aren't Gonna Need It)**:
   - この抽象化、インターフェース、設定値、型パラメータ、将来用フックは「今この瞬間」に真に必要か？
   - 必要でなければ即座に削除・排除する。推測による機能追加は一切認めない。
2. **Step 2: Codebase Reuse (既存コードの再利用)**:
   - リポジトリ内に類似・同等の処理を行う共通関数、ユーティリティ、型、正規表現が存在しないか？
   - 既存の枯れた実装を最優先で再利用し、重複実装（車輪の再発明）を禁止する。
3. **Step 3: Stdlib First (標準ライブラリ最優先)**:
   - 言語の標準ライブラリ（Go stdlib, Rust std, C++ stdlib, Python standard library, Node/Bun built-ins）で完結できないか？
   - 標準機能で数行〜十数行で実現可能な機能のために、新規外部ライブラリ/クレートを追加することを禁止する。
4. **Step 4: Platform Native (実行基盤・OS機能の活用)**:
   - 実行基盤（Linux, POSIX, Bun, シェル）が提供するネイティブ機能（ファイルシステム、パイプライン、環境変数、coreutils）で解決できないか？
   - アプリケーション層で不要な車輪（プロセスプールや監視機構等）を自作しない。
5. **Step 5: Minimal Dependency (最小限の依存関係)**:
   - 外部依存が不可欠な場合、既にプロジェクトに導入済みの最小限のライブラリに限定する。
   - 重大な推移的依存（Transitive Dependencies）ツリーを伴う重量級ライブラリの追加を拒絶する。
6. **Step 6: Minimal Expression (直接的・簡潔な表現)**:
   - デザインパターン（Factory, Strategy, Visitor等）による過剰なクラス階層を排し、1〜5行の素直で直接的なイディオムで記述する。
   - 認知的ジャンプ（Cognitive Jumps）の少ない、直線的で読みやすいコードを優先する。
7. **Step 7: Surgical Minimal Diff (外科手術的最小差分)**:
   - 差分（diff）は必要最小限に留める。
   - タスクに関係のない「ついでリファクタリング」「勝手な変数名変更」「無関係なフォーマット変更」を固く禁ずる。

---

## 2. 安全と品質の絶対防壁 (Safety & Quality Invariants)

「最小主義（Minimalism）とは手抜き（Sloppiness）ではない」。行数削減を目的とした安易なコードゴルフや防御的処理の省略は重大な規約違反とみなす。

以下の 4 項目は常時維持されなければならない:

1. **境界値・事前条件検証の維持**:
   - 引数バリデーション、ポインタやオブジェクトの nil/null/undefined チェック、配列境界チェックを省略してはならない。
2. **エラー処理の明示性と不変性**:
   - エラーの破棄（Go の `_ = err`、TypeScript/Python の空 catch/except）は厳禁（Vald Law 5 準拠）。
   - すべてのエラーは適切に伝播するか、明確な文脈情報とともにハンドリングする。
3. **セキュリティの死守**:
   - シェルインジェクション、パストラバーサル、ハードコードされた機微情報を絶対に生み出さない。
   - Vald リポジトリでは Vald Laws 1〜5 を完全遵守する。
4. **型安全性とメモリ安全性の担保**:
   - TypeScript における安易な `any`、Rust における根拠なき `unsafe`、C/C++ における境界外アクセスを禁止する。

---

## 3. レビューおよびゲートでの検証義務 (Review & Gate Verification)

- **レビュアーの責務**:
  - `code-reviewer`, `teamwork_preview_reviewer`, `code-quality-adversarial-reviewer`, `architecture-adversarial-reviewer` は、差分が Ponytail 7段階ラダーおよび安全防壁に適合しているかを監査する。
  - 推測的抽象化、過剰なボイラープレート、標準ライブラリで代用可能な外部依存、タスク外の不要な変更（gratuitous churn）が発見された場合、**必ず REJECT（差し戻し）**とする。
- **MAST 分類との連携**:
  - Ponytail 違反による差し戻しは、MAST カテゴリ (i) system design issues または (v) unnecessary complexity として分類・記録する。
