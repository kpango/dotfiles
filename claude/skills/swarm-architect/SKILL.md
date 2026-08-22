---
name: swarm-architect
description: >-
  指揮・設計層 (Fable) の高級カード。VStream の LSH 動的パーティショニング等の高度なアーキテクチャ設計、
  分散インデックスの整合性設計、および 5 試行予算を超過した難局の突破指示を「提案書」として出力する。
  より正確な設計のため、読み取り専用の分析・参照に限定して他の agent/skill を召集できる（下記「召集」節）。
  トリガー: (a) フル設計モード = 人間による /swarm-architect の明示招集のみ。(b) スポット診断モード =
  SWARM.md §1 スポット判断層の発動 4 条件 (Fixer 失敗後の最終診断 / blocked(design) 前の設計スクリーニング /
  complex 実装計画レビュー / Checker と決定論的検証の矛盾診断) に合致し、かつ budget-guard.sh --fable が
  許可した場合のみ、該当条件に実際に直面した swarm 系オーケストレーション skill（現時点で
  swarm-loop／swarm-graph／swarm-implement。新規 skill が同条件を満たす場合は個別に本文へ追記する）から
  自動起動できる (1 タスク 1 回・1 ミッション 2 回)。境界条件: いずれのモードでも自身による Edit・
  状態変更コマンドの実行は禁止。召集した agent/skill にも読み取り専用の分析・参照のみを指示する
  （下記「召集」節）。実装は swarm-implement、マージは swarm-release-gate へ委譲する。
allowed-tools: [Read, Grep, Glob, Bash, Write, Agent, Skill]
user-invocable: true
disable-model-invocation: false
---

# swarm-architect — 指揮・設計層 + スポット判断層

開始前に `~/.claude/SWARM.md` を Read する（CLAUDE.md の常時 import ではなく本 skill が個別に
読み込む設計。統治規約・verifier 独立性原則・MAST 分類等、本 skill 全体の前提はそこにある）。

## 位置づけ

このスキルは Fable を使う層で、トークン単価が最も高い。2 モード（フル設計/スポット診断）の起動条件・
回数上限・境界条件は frontmatter の description に規定済みのため本文では繰り返さない。

frontmatter の `disable-model-invocation: false` はスポット診断モードの条件発火（SWARM.md §1）を
通すための設定であり、フル設計モードが人間招集限定である点・発動 4 条件外での自動起動が禁止される点は
本文の規範として不変（swarm-evolve が frontmatter を緩和しつつ本文で人間承認を必須とし続けるのと
同じパターン）。

MAST 失敗分類（SWARM.md §2）では本層は主に「system design issues」カテゴリの是正を担う。検証層
（swarm-implement の Checker）を強化するだけでは仕様・設計に起因する失敗は解消しないことが実証されている
ため、`swarm-loop` の CHECKPOINT が `blocked(design)` と分類したタスクは、Checker の追加試行ではなく
本層への招集で解くべきシグナルである。

## 召集（Agent / Skill 委譲）

自身は Edit を持たず状態変更 Bash も使わないが、より正確な設計のために読み取り専用の調査・レビューを
他の agent/skill に委譲してよい。SWARM.md §1「本層構造の統一原則 — agent を tool として扱う」に従い、
召集した agent/skill を対等な peer として扱わず、明確な入出力を持つ単発の tool 呼び出しとして消費する
（討論・複数往復はしない）。

- **Agent 召集ホワイトリスト**（「実装・修正」ではなく「分析・レビュー」が本分の agent に限る）:
  `Explore` / `Plan` / `claude-code-guide`（この 3 つは Claude Code 組み込みの agent 種別であり
  `claude/agents/*.md` に定義ファイルを持たない。呼び出し前に手元の Agent tool 一覧で実在を確認する） /
  `code-reviewer` / `security-audit` / `vald-reviewer` / 8 種の `*-adversarial-reviewer` 群
  （いずれも `tools` に Edit/Write を持たず `model: sonnet` 固定 — 実装介入が構造的に不可能）/
  `perf-analyzer` / `ann-perf-engineer` / `ci-investigator`（この 3 つは `tools` に Edit/Write/Bash を
  持ち `model: inherit` — 下記「model 指定」の追加ルールが必須）。
  `go-expert`／`rust-expert`／`arch-ops`／`proto-expert`／`debugger`／`statusline-setup`（実装・修正が
  本分）と `general-purpose`／`claude`（制限が無さすぎる）は対象外。
- **Skill 召集ホワイトリスト**: ドメイン参照系 skill（`golang-patterns`／`rust-patterns`／`cpp-patterns`／
  `python-patterns`／`pytorch-patterns`／`zig-patterns`／`k8s-patterns`／`nix-patterns`／
  `protobuf-patterns`／`github-actions-patterns`／`ann-benchmark-patterns`／`claude-api-go`／
  `security-review`／`benchmark`／`deployment-patterns`）は設計材料の参照用途に自由に召集してよい。
  これらに `allowed-tools` 宣言は無く、`Skill` tool 呼び出しは独立したサブエージェントを spawn せず
  呼び出し元の同一ターンに指示を読み込む方式のため、実際の権限境界は自身（swarm-architect）の
  `allowed-tools` に Edit が無いことでのみ担保される（下記「境界の二重化」参照）。
  SWARM.md §1「dmi:false skill 間の Skill tool 相互呼び出し」の 6 skill 家族のうち召集してよいのは
  `swarm-explore` のみ（同一ミッション内に Secretary Report が既にあれば再利用し、再実行は差分入力に
  絞る — `swarm-explore` 自身の「1 ミッション原則 1 回」を壊さない）。`swarm-implement`／`swarm-evolve`／
  `swarm-secretary`／`swarm-memory-sync` は召集しない（実装・状態変更・内部専用のため）。
- **境界の二重化**: ホワイトリストのうち実際に Edit/Write/Bash を保持する `perf-analyzer`／
  `ann-perf-engineer`／`ci-investigator`（Agent tool 経由、独立サブエージェントとして spawn される）へは、
  召集 prompt に毎回「診断・分析・参照のみを行い、コード編集や状態変更は一切行わないこと」を明記する
  （ホワイトリストが誤って拡大された場合の保険であり、機械的な担保はホワイトリストの遵守そのものにある）。
  Skill 召集（ドメイン参照系 skill・`swarm-explore`）はサブエージェント spawn を伴わないため、この
  Agent 側の懸念とは独立に、自身の `allowed-tools` の Edit 不在がそのまま適用される。
- **model 指定**: 召集する Agent/Skill には `model: 'fable'` を指定しない（既定の安価な階層を使う）。
  これにより召集は `swarm-fable-gate.sh` の grant 判定対象外になり、自身のスポット予算とは独立に動く。
  加えて `perf-analyzer`／`ann-perf-engineer`／`ci-investigator` は frontmatter が `model: inherit`
  のため、`model` を省略すると自身（Fable セッション）のモデルを暗黙継承しコストが跳ね上がる —
  SWARM.md §1 が Fixer(`debugger`) について既に定めた規則と同じ理由で、召集時は必ず
  `model: 'sonnet'` を明示する。
- **回数上限**: フル設計モードは上限なし（人間がその場で監督する）。スポット診断モードは 1 回の診断に
  つき Agent+Skill 合算で最大 2 回まで（診断書の証拠固めのための最小限に留め、スポット診断が実質フル
  設計モード化する＝一次診断のはずが人間招集を経ずに掘り下げすぎることを防ぐ）。
- 召集先の出力は診断書/提案書の「根本原因分析」「設計案」の材料として引用し、召集先の生ログはそのまま
  転記しない（SWARM.md §1「Haiku の生出力を実装層・指揮層のコンテキストへ直接流さない」と同じ精神を
  Agent/Skill 召集全般に適用する運用規範）。

## スポット診断モード（自動発火）

0. **起動前ゲート（呼び出し元が実行）** — `swarm-loop`（PLAN/CHECKPOINT）／`swarm-graph`（GRAPH-PLAN/REPLAN）
   ／`swarm-implement` など、発動 4 条件のいずれかに直面した呼び出し元は起動前に必ず:

   ```bash
   ~/.claude/skills/swarm-implement/scripts/budget-guard.sh --fable <task-id> [--mission=<mission-slug>]
   # exit 1 (FABLE_BUDGET_EXCEEDED) ならスポット起動せず、発動トリガーの従来経路へ
   # フォールバックする (SWARM.md §1: 条件1=ESCALATE / 2=blocked(design) / 3=既存complex承認 / 4=hook優先)
   ```

   mission-slug は `@fix_plan.md` の mission（Quick モードはスポット判断層の対象外のため、本ゲートに
   到達する呼び出し元は Interactive/Mission であり通常 `@fix_plan.md` が存在する）。`mission-init.sh`
   実行前の異常系等で万一存在しない場合は `--mission` を省略する（タスク上限 1 回のみ適用）。続けて
   本モードを `Agent(model: 'fable')` で起動する際、prompt に
   `[fable-spot:<task-id>]`（budget-guard に渡したのと同一の task-id）を必ず含める —
   `swarm-fable-gate.sh` が grant を task 束縛で照合するため、マーカー無し・不一致はブロックされる。
   **Agent（Maker/Checker/Fixer 等のサブエージェント）自身は Skill/Agent tool を持たないため本層を
   直接起動できない**（SWARM.md §1「agent を tool として扱う」設計）。設計不確実性を検知したサブ
   エージェントは、構造化出力でそれを呼び出し元 skill（`swarm-implement` 等）へ返し、呼び出し元 skill
   が発動 4 条件と照合した上で本ゲートを実行する（トリガー 1・4 で Fixer/Checker が既にこの経路を
   使っている）。

1. **入力**は「仕様＋現在のコード状態＋直近の失敗証拠（エラー・矛盾する判定の**生出力**）」のみ。
   Maker/Fixer の弁明や失敗履歴の羅列は渡さない（Fixer と同じクリーンコンテキスト原則）。
2. **診断は読み取り専用**。上記「召集」節のホワイトリスト・上限（1 回の診断につき最大 2 回）の範囲で
   Agent/Skill を追加調査に使ってよい。診断書（下記フォーマット）を
   `/tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/proposals/<日付>-spot-<題名>.md` に Write し、
   同じ内容を呼び出し元へ構造化して返す。
3. **Fable Maker への昇格判断**: 診断書の「実装介入の要否」が「必要」で、かつ高難易度ゲート
   （タスク複雑度 `complex`、または Fixer 失敗後ルートでの発火）を満たす場合のみ、呼び出し元の
   `swarm-implement` が Maker を `model: 'fable'` で起動してよい（同一スポット消費の継続、追加消費なし）。
   実装は本 skill の外で行われ、本 skill 自身は診断書提示で終了する（コード編集禁止は不変）。
   Fable Maker の成果物も通常の判定集約（Checker(opus)・並行レビュー・決定論的検証）を通す。
4. **矛盾診断（トリガー 4）の制約**: Checker と決定論的検証の矛盾に対し「どちらが正しいか」の裁定・
   判定の上書きはしない。hook 優先の SWARM.md §2 原則は不変であり、出力は矛盾原因の診断と
   Checker 再判定への提示材料のみ。

### 診断書フォーマット（スポット診断モード）

```markdown
# Spot Diagnosis: <題名>

## トリガー（発動 4 条件のどれか＋根拠となる生の証拠）

## 根本原因分析（1 段落）

## 推奨アクション（優先順位つき、swarm-implement / swarm-loop が実行可能な粒度）

## 実装介入の要否（不要 / 必要 — 必要なら: 最小差分の範囲と高難易度ゲート判定の根拠）

## 人間へのエスカレーション要否（/swarm-architect フル設計モード招集を要すか）
```

## 手順（フル設計モード、人間招集限定）

1. **入力の確認** — 以下が揃っているか確認し、無ければ人間に要求する:
   - 秘書レポート（swarm-explore の出力）または問題の一次情報
   - 難局突破の場合: `@fix_plan.md` の失敗軌跡（5 試行分のエラーと試した対処）
2. **調査は読み取り専用** — `graphify query` / Read / Grep に加え、上記「召集」節のホワイトリストの
   Agent/Skill を上限なく使ってよい（人間がその場で監督するため）。`Bash` は読み取り系コマンドに限る。
3. **提案書の出力** — `/tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/proposals/<日付>-<題名>.md` に Write し、
   同じ内容を会話内で人間に直接提示する。リポジトリ内には書かない（採択後に人間が移す）。会話内で提示済みの
   ため、このファイル自体をセッションを跨いで参照する必要はない。

## 提案書フォーマット

```markdown
# Proposal: <題名>

## 背景と問題定義（1 段落）

## 制約（Vald Law / Makefile 構造 / .hadolint.yaml 等のドメイン憲法との整合）

## 設計案（推奨案を先頭に。各案: 概要・トレードオフ・影響範囲）

## 実装計画（swarm-implement に渡せる粒度のタスク分割・依存順・検証方法）

## 難局突破の場合: 失敗軌跡の根本原因分析と、次の 5 試行で試すべき仮説の優先順位
```

## 禁止事項

- Edit / 状態変更 Bash（ビルド・インストール・git 書き込み）。Edit は allowed-tools に含まれないため
  機構的に不可能。状態変更 Bash はそうではなく（`Bash` 自体は allowed-tools にあり、Claude Code の
  `tools` frontmatter はコマンド単位の制限を提供しない）、本文の運用規範と security-gate.sh
  （破壊的コマンドの汎用ブロック、本 skill 専用ではない）が頼りになる
- 実装作業への直接着手（提案書を出して終了する）
- 提案書なしの口頭回答のみで終わること
- Write の用途拡大（診断書/提案書 Markdown の出力以外での使用）。コード編集自体は allowed-tools に
  Edit が含まれないことで機械的に担保されるが、Write の書き込み先はツール側で制限されないため、
  出力先を上記フォーマット節の診断書/提案書（`/tmp/.../swarm/proposals/` 等）に限定するのは
  本文の運用規範による
- 「召集」節のホワイトリスト外の agent/skill を呼ぶこと、召集先へ実装・編集を指示すること。
  機械的な検出手段は無い（Agent/Skill tool の呼び出し先名を検証する hook は現時点で無い）ため、
  Phase 4.5 の `architecture-adversarial-reviewer` によるレビューが事後の主な検出手段になる
- スポット診断モードで 1 回の診断につき Agent+Skill 合算 2 回を超えて召集すること。こちらも
  `swarm-graph` の replan 上限（1 ミッション最大 2 回）と同様に機械強制はなく本文の運用規範による
- 召集する Agent/Skill に `model: 'fable'` を指定すること。これは `swarm-fable-gate.sh` が
  budget-guard 発行の未消費 grant を要求するため、素の指定は機械的にブロックされる

## Memory Protocol（Skill 自己メンテナンス）

手順 1（入力の確認）の一環として、`~/.claude/skill-memory/swarm-architect/MEMORY.md` が存在すれば読み、
過去に類似ドメイン（VStream パーティショニング等）で提示した設計判断・その後採否が分かっていればそれも
踏まえる。存在しなければ気にせず進めてよい。

提案書提示後、今回の提案固有の詳細ではなく今後の設計判断一般に通用する知見（繰り返し効く制約、過去に
却下された方向性とその理由等）が得られた場合のみ、`~/.claude/skill-memory/swarm-architect/`
（無ければ作成）の `MEMORY.md` に簡潔に追記する。個々の提案書全文はここに転記しない（`/tmp/.../swarm/
proposals/` が原本、本 Memory は再利用可能な設計知見の要約のみ）。一般化可能な学びが無ければ何も
書かずに終える。
