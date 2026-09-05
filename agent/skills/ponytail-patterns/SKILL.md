---
name: ponytail-patterns
description: Ponytail 7-step anti-overengineering logic ladder and safe minimal code patterns. Enforces YAGNI, codebase reuse, stdlib priority, and surgical minimal diffs.
allowed-tools: [Read, Grep, Glob, Bash, Edit, Write]
user-invocable: true
---

# ponytail-patterns — 過剰設計防止7段階ロジックラダーと安全な最小コード規範

Ponytail は、LLM エージェントやソフトウェア開発者が陥りがちな「過剰抽象化（Over-engineering）」「推測に基づく機能追加（Speculative Generality）」「外部依存関係の肥大化（Dependency Bloat）」「広範囲な不要リファクタリング（Scope Creep）」を構造的に防止するための実践的コード設計フレームワークである。

「最も優れたコードは、書かれなかったコードである（The best code is no code）」という真理に基づき、真に必要なロジックのみを最小・最速・最も堅牢な形で実装する。

---

## 1. 7段階過剰設計防止ロジックラダー (7-Step Logic Ladder)

コードの構想・作成・レビューにおいて、以下のラダーを Step 1 から順に検証する。上位の段階で解決できる場合は、下位の手段を選択してはならない。

```
Step 1: YAGNI (機能・抽象化・パラメータの存在理由の問診)
    ↓
Step 2: Codebase Reuse (既存コード・共通関数の再利用)
    ↓
Step 3: Stdlib First (言語標準ライブラリの徹底活用)
    ↓
Step 4: Platform Native (実行基盤・OS・ランタイムのネイティブ機能)
    ↓
Step 5: Minimal Dependency (導入済み最小依存関係の限定利用)
    ↓
Step 6: Minimal Expression (1〜5行の簡潔・直接的イディオム表現)
    ↓
Step 7: Surgical Minimal Diff (外科手術的最小差分・ゼロ不要変更)
```

### Step 1: YAGNI (You Aren't Gonna Need It)

- **問診**: 「この抽象化、汎用インターフェース、設定パラメータ、将来の拡張フックは**今この瞬間**に本当に必要か？」
- **判定**: 将来起こるかもしれない要件のために前もって作られたコード、型パラメータ、プラグイン機構はすべて削除する。
- **原則**: 「今使う1つの具体的ケース」だけを解く。2つ目のケースが現れるまで共通化・抽象化してはならない（Rule of Three）。

### Step 2: Codebase Reuse (既存コードの再利用)

- **問診**: 「このリポジトリ内またはプロジェクト内に、既にこの処理を行うヘルパー、ユーティリティ、型、正規表現はないか？」
- **判定**: 新しい関数やクラスを書く前に、必ず `Grep` / `Glob` でコードベースを探索する。
- **原則**: 車輪の再発明を禁止し、テスト済み・枯れた既存の社内/リポジトリ内実装を最優先で呼び出す。

### Step 3: Stdlib First (標準ライブラリ最優先)

- **問診**: 「言語の標準ライブラリ（Go stdlib, Rust std, C++ stdlib, Python standard library, Node/Bun built-ins）で解けないか？」
- **判定**: 標準ライブラリで5〜10行で書ける処理のために、サードパーティ製パッケージ・クレート・ライブラリを新規導入してはならない。
- **原則**: 外部エコシステムの流行り廃りに左右されない、言語公式が長期保守する安定APIに依存する。

### Step 4: Platform Native (実行環境・OSネイティブの活用)

- **問診**: 「実行基盤（Linux / POSIX / Bun / シェル環境）が標準で提供する機能、ファイルシステムプリミティブ、パイプライン、環境変数で完結できないか？」
- **判定**: アプリケーションコードで複雑な並行ワーカープールやプロセス監視を書く前に、systemd、xargs、POSIXパイプ、GNU coreutilsの利用を検討する。
- **原則**: OSの成熟した抽象化境界を尊重し、車輪をアプリ層へ持ち込まない。

### Step 5: Minimal Dependency (依存関係の最小化)

- **問診**: 「どうしても外部依存が必要な場合、既にインストール済みの最小ライブラリで足りないか？」
- **判定**: 単一機能のために推移的依存（Transitive Dependencies）を数十個引き連れてくる重量級ライブラリを禁止する。
- **原則**: 依存を追加する際は、依存ツリーの深さ、メンテナンス継続性、バイナリサイズ影響を厳格に評価する。

### Step 6: Minimal Expression (直接的・簡潔な表現)

- **問診**: 「50行のデザインパターン（Factory, Strategy, Builder等）を使わずに、1〜5行の素直なイディオムで直接書けないか？」
- **判定**: 過剰なレイヤリング、無意味な中間オブジェクト、1回しか使われないprivateメソッドへの過度な細分化を排除する。
- **原則**: コードの可読性とは「行数の多さ」ではなく「認知的ジャンプの少なさ」である。上から下へ素直に読める直線的コードを書く。

### Step 7: Surgical Minimal Diff (外科手術的最小差分)

- **問診**: 「このdiffは、要求された目的を達成するための真の最小差分になっているか？」
- **判定**:
  - タスクと無関係な「ついでにリファクタリング」「変数のリネーム」「フォーマット変更」を一切禁止する。
  - 変更行数・変更ファイル数を最小化する。
- **原則**: diffの行数が少ないほど、レビューが容易になり、リグレッションの混入確率は指数関数的に減少する。

---

## 2. 安全と品質の防壁 (Safety & Quality Guard)

### 「最小主義とは手抜き（Sloppiness）ではない」

Ponytail が目指す「最小コード」は、防御的プログラミングやエラーハンドリングを削って行数を短く見せる悪質なコードゴルフ（Code Golf）を最も強く拒絶する。

以下の 4 大不変条件（Invariants）はいかなる場合も省略・妥協してはならない:

1. **境界値・事前条件検証の完全性 (Never Skip Bounds / Nil Checks)**
   - 引数のバリデーション、ポインタの nil/null チェック、配列の境界チェック、ファイル存在確認を「行数を削るため」に省略してはならない。
   - 外部境界（ユーザー入力、APIレスポンス、ファイル読み込み、ネットワーク通信）では厳格な入力検証を行う。

2. **エラー伝播と明示的ハンドリング (Never Ignore Errors)**
   - Go における `_ = err` や無言のエラー破棄を厳禁とする（Vald Law 5）。
   - TypeScript/Python における空の `catch {}` / `except: pass` による例外の握りつぶしを禁止する。
   - エラーは適切な文脈情報を付与して呼び出し元へ伝播するか、明示的にログ記録・回復処理を行う。

3. **セキュリティとVald Lawsの厳格遵守 (Absolute Security Compliance)**
   - コマンド文字列の単純結合によるシェルインジェクション脆弱性（Shell Injection）を絶対に生み出さない。
   - パストラバーサル（`../`）の検証、機微情報（トークン、パスワード）のハードコード禁止。
   - Vald リポジトリでの作業時は Vald Law 1〜5（生成コード直接編集禁止、生panic禁止、main外log.Fatal禁止、エラー破棄禁止等）を死守する。

4. **型安全性とメモリ安全性の担保 (Type & Memory Safety)**
   - TypeScript における安易な `any` の乱用、Rust における正当な理由のない `unsafe` の導入、C/C++ におけるバッファオーバーフローの放置を禁止する。

---

## 3. 言語別イディオムとアンチパターン (Language-Specific Patterns)

### 3.1 Go

- **Anti-Pattern**:
  - 1つの構造体しか実装しないのに、先回りしてインターフェースを定義する。
  - 単純な文字列操作やスライス操作のために外部サードパーティライブラリを `go get` する。
  - `errors.New` で済む場所に、複雑なカスタムエラー型階層とファクトリを構築する。
- **Ponytail Pattern**:
  - `io.Reader` / `io.Writer` など、stdlib の標準インターフェースのみを使い、具象型を直接受け渡す。
  - Go 1.21+ の `slices`, `maps`, `cmp` などの標準パッケージを徹底活用する。
  - 表駆動テスト（Table-driven tests）を用いて、テストコードも最小かつ網羅的に書く。

### 3.2 Rust

- **Anti-Pattern**:
  - 数行のユーティリティ関数のために、重いマクロや巨大なクレートツリーを `Cargo.toml` に追加する。
  - ライフタイムや型パラメータが複雑に絡み合うトレイトの塔（Trait Towers）を築く。
  - エラーを `unwrap()` で雑に処理するか、逆に過剰に抽象化されたカスタムエラー型を多層化する。
- **Ponytail Pattern**:
  - `std::fs`, `std::path::Path`, `std::collections` を最優先する。
  - `match` や `if let` を使った直線的で安全な制御フロー。
  - 外部クレートを導入する場合も、`serde`, `thiserror` 等の業界標準・最小限のものに厳選する。

### 3.3 C++

- **Anti-Pattern**:
  - デザインパターンを誇示するための多段継承、Abstract Factory、無意味な Pimpl イディオムの乱用。
  - Boost などの巨大ライブラリを、C++20 stdlib で提供されている機能のために引き込む。
- **Ponytail Pattern**:
  - C++20 の標準ライブラリ（`std::string_view`, `std::span`, `std::filesystem`, `std::expected` 等）を活用する。
  - RAII によるリソース管理を愚直に行い、プレーンな構造体と純粋関数でロジックを構成する。

### 3.4 Python

- **Anti-Pattern**:
  - 数十行のスクリプトに対して、過剰なメタプログラミング、BaseClass 抽象クラス、不要な DI コンテナを導入する。
  - 標準ライブラリで足りる HTTP リクエストや JSON 操作、パス操作に外部パッケージを過剰要求する。
- **Ponytail Pattern**:
  - `pathlib`, `dataclasses`, `json`, `subprocess`, `typing` などの標準ライブラリを駆使する。
  - リスト内包表記やジェネレータ式を活用し、シンプルでPythonicな表現に収める。

### 3.5 TypeScript / Node / Bun

- **Anti-Pattern**:
  - `lodash`, `moment`, `request`, `axios` などの重厚なパッケージを漫然と `npm install` する。
  - 状態を持たない関数のためにわざわざクラスを作り、インスタンス化して呼び出す。
  - 型パズル（複雑怪奇な条件付き型や template literal types）でコードの可読性を落とす。
- **Ponytail Pattern**:
  - JavaScript / TypeScript 組み込みの `Array` メソッド（`map`, `filter`, `reduce`）、`Object.entries`、Web標準 `fetch` を使用する。
  - Bun ネイティブ API（`Bun.file`, `Bun.spawn` 等）を直接活用する。
  - クラスではなく、プレーンなオブジェクト（interface/type）と純粋関数（pure functions）で構成する。

### 3.6 Shell (Bash / Zsh)

- **Anti-Pattern**:
  - 1行のシェルコマンドで終わる作業のために、数十行のPython/Nodeスクリプトを起こす。
  - パイプラインで `cat file | grep foo | awk '{print $1}'` のような無駄なプロセス生成（Useless Use of Cat）。
  - クォート忘れやエラーチェック不備による、空白混じりパスでの破綻。
- **Ponytail Pattern**:
  - `set -euo pipefail` をヘッダに必ず明記する。
  - シェル組み込みのパラメータ展開（`${var:-default}`, `${var%/*}`）や `grep`, `sed`, `awk` を的確に使い分ける。
  - コマンドライン引数や変数展開は常にダブルクォートで保護する。

---

## 4. コミット・レビュー前チェックリスト (Ponytail Review Checklist)

変更を完了する前に、エージェント自身またはレビュアーが以下を確認する:

- [ ] **YAGNI**: 今回のタスクで使われていない引数、オプション、関数、将来用のフックはないか？
- [ ] **Reusability**: 既にコードベースにある関数を車輪の再発明していないか？
- [ ] **Stdlib**: 標準ライブラリで書ける処理に外部パッケージを追加していないか？
- [ ] **Simplicity**: 5行で書ける処理を50行のデザインパターンで装飾していないか？
- [ ] **Diff Quality**: 依頼されていない「ついでリファクタリング」や空白フォーマット変更がdiffに含まれていないか？
- [ ] **Safety Guarantee**: 行数削減を理由に、エラーハンドリングや入力バリデーションを削っていないか？
