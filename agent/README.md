# agent/ — 4 ハーネス (claude / pi / agy / hermes) 共通設定の正典

Claude Code・Pi (`@earendil-works/pi-coding-agent`)・Antigravity・Hermes Agent が共有する設定・Rule・Skill・Agent・Swarm 規約の**単一ソース**。
ツール固有の設定は `harnesses/<name>/` に置く。`$HOME` 側への配線は `Makefile.d/install.mk` と
`nix/modules/home/dotfiles/agent-tools.nix` が `agent/` から**直接** symlink / 生成する（リポジトリ内に中間 symlink は無い）。
配線の正しさは `agent/scripts/sync-verify.sh` で検証する。

## 構成

```
agent/
├── rules/  skills/  agents/      共通正典（各ハーネスの $HOME 側へ直接 symlink）
├── models/                       抽象モデル Tier の schema・catalog
├── harnesses/{claude,pi,agy,hermes}/    ハーネス固有設定・model-routing.json・validate-harness.sh
├── hooks/{claude,agy,pi}/        hook 本体（各ツールの hooks / extensions へ個別ファイル symlink で合成）
├── scripts/                      hooks/(decide.py, rule_engine.py)・sandbox/(pa-sandbox)・sync-verify.sh・gen-*・test-*
├── security-rules.json           危険コマンド・機微パスの Hard Floor ルールデータ（hook 全実装が共有）
├── vald-law-rules.json           Vald Law 1–5 のルールデータ
├── write-scope-rules.json        Tier B 書込保護パターン（正典は write-scope-lib.sh の case 文。同期はテストで検証）
├── settings-common.json          settings.json の共通部分
├── sync-manifest.json            「正典 → 各ハーネス配線」の宣言（sync-verify.sh が読む）
└── SWARM.md  SWARM_REFERENCES.md  RTK.md  ROUTING_CATALOG.md  AGENTS*.md  SYSTEM*.md
```

## 配線の要点

- `rules`・`agents`・`skills`・`RTK.md`・`SWARM.md`・`SWARM_REFERENCES.md` は `$HOME` 側から直接 symlink される。
- `hooks` / `extensions` は複数の物理ソース（`harnesses/<h>/` と `hooks/<h>/`）を個別ファイル symlink で合成する
  （merged directory）。拡張子・placeholder の除外は `install.mk` と nix の双方で揃える。
- pi の `settings.json` は起動時にランタイム更新されるため 0600 通常ファイルとして配布し（`defaultProvider`/`defaultModel`/`defaultThinkingLevel` を保持）、`models.json`/`mcp.json`/`lsp.json`/`dap.json`/`keybindings.json`/`sol-pi.json` を直接 symlink する。
- hermes は `agent/skills` を `~/.hermes/skills` へ、`profiles/*` を個別に symlink する。
- `AGENTS.md` / `SYSTEM.md` はハーネス別に `gen-*` スクリプトで生成し、`--check` で鮮度を検証する。
- 指示ファイルの根は 2 つだけ: グローバルは `agent/AGENTS.md`（+ `AGENTS-<tool>-supplement.md`）、dotfiles プロジェクト固有は
  リポジトリ直下の `AGENTS.md`。同じ場所の `CLAUDE.md` / `GEMINI.md` はそれへの symlink で、
  実体は 1 本（`test-root-agent-files.sh` が検証。編集は実体側で行う）。

## 研究コンテキスト（Pi 1.0 時代の30技術）

`agent/context/` は 4 ハーネス共通の調査ドキュメント置き場（`$HOME` へは配線しない）。

- `agent/context/pi30-primary-research.md` — PDF `plans/pi-agent-improvement.pdf`（`plans/` は gitignore された local-only 入力）の全30技術について、
  一次情報（arXiv / 上流 repo）・中核機構・報告された定量結果・実装要件・適用判定を出典付きで整理した dossier。
- `agent/context/pi30-applicability.md` — OMP / Claude Code / Agy への適用性監査。判定（完全 / 部分 / 欠落）と
  導入（完全導入 / 部分導入 / 保留 / 不採用）の 2 軸の凡例、および実装済み／検証済みを分離した検証マトリクスを含む。過大主張はここで訂正する。

新しい技術を導入するときは、先に dossier の該当節を一次情報で確認し、conformance test を追加してから
「完全」と判定する（実装だけでは「部分」）。

## 共通化しないもの

- `CLAUDE.md` / ハーネス固有の `AGENTS.md`・`SYSTEM.md` のアイデンティティ部分
- `settings.json` / `config.yml` 等の実行時設定本体（スキーマがツール固有。共通部分のみ `settings-common.json`）
- ツール固有の拡張機構（pi `extensions/`、agy `policies/`・`hooks/`）。ただしルールデータは `*-rules.json` で共有する
- `SKILL.stats.json`: 実行時テレメトリ（`swarm-implement/scripts/stats-record.sh` が更新）。静的設定ではない

## MCP サーバー定義

`harnesses/agy/mcp_config.json` は Agy MCP の正典です。Agy CLI は配布先の
`~/.gemini/config/mcp_config.json` を読みます。`scripts/gen-harness-parity.py --write` は
Trail の定義を Gemini (`.gemini/settings.json`)、Pi (`harnesses/pi/mcp.json`)、OpenCode (`opencode.json`)、
Claude Code の明示登録用 (`project/claude/trail-mcp.json`) に反映し、Agy のその他のサーバーを
`harnesses/agy/settings.json` に反映します。Claude Code はユーザー設定によってプロジェクト MCP を
自動承認できるため、ルートの `.mcp.json` には登録しません。使う場合はこのリポジトリのルートで
`claude mcp add-json --scope local trail - < agent/project/claude/trail-mcp.json` を実行してください。
`$comment` は `mcpServers` の外に置いてください。

dotfiles プロジェクトの共有 Claude 設定は `project/claude/settings.json` が正典で、
`.claude/settings.json` は生成物です。既存の `.claude/settings.local.json` はローカルの承認や
拒否を保存しうるため生成対象に含めません。`--write` の前にネイティブ設定の未反映差分を確認してください。
`--check` と `scripts/test-harness-parity.sh` は書き換えずに差分を検出します。認証情報や CLI の
実行時状態、ツール固有の権限・フック・プラグインは他のハーネスへ移植しません。
生成先が既存の `$HOME` 配布リンクの参照元になっている場合があるため、実環境への反映を
承認するまでは隔離 checkout で `--write` を実行してください。

## Tier B 書込保護

`skills/*/SKILL.md`・`skills/*/scripts/*`・`rules/*`・`agents/*`・`SWARM*.md`・hooks・`harnesses/*/model-routing.json`・
`*-rules.json` などは書込ゲートで保護される。正典は `skills/swarm-implement/scripts/write-scope-lib.sh` の
`write_scope_is_protected()`。変更するには適用可能な人間の承認を確認してから単発 grant を発行する:
`skills/swarm-implement/scripts/budget-guard.sh --write-scope-grant <file-path>`（TTL 300 秒）。
低リスクの保守に対する常設承認の範囲は `AGENTS.md` を参照。権限・安全ゲート・公開には適用しない。
パターンを変える場合は `write-scope-rules.json` も同時に更新し、`scripts/test-write-scope-parity.sh` で検証する。

`agent/` の物理構造を変更するときは、`claude/`・`pi/`・`agy/` 配下のパスをハードコードした参照が
`hooks/`・`skills/*/scripts/`・`rules/*.md` の frontmatter に残っていないかを grep で横断確認する
（`git status` や `make -n` では検出できない）。

## SSoT 同期検証

`scripts/sync-verify.sh`（exit 0 = 全 PASS）は `sync-manifest.json` を読む。モードは
`live-symlink`、`generate`（`--check` で鮮度検証）、`live-symlink-dir`、`live-regular-file`。
隔離 worktree の設定をテストするときは一時 HOME を使う。既存の `$HOME` のリンクをメイン checkout 基準で
検証するときは `SYNC_VERIFY_LIVE_ROOT=auto` を指定する。新しい配布先は manifest に宣言する。

## 検証コマンド

- `scripts/test-all-harnesses.sh` 全ハーネスの機械検証、`harnesses/<h>/validate-harness.sh` ハーネス別
- `scripts/test-catalog-health.sh` Skill / Agent カタログ、`scripts/test-security-rules.sh` Hard Floor
- `scripts/test-host-capabilities.sh` Pi ホストパッケージ（`@earendil-works/pi-coding-agent` ExtensionAPI 型、自己ホスト型 hashline-edit/lsp-client/dap-client/ttsr-guard/model-roles、RLM_BACKEND / ObservationPack 10240B）を機械検証。Claude/AGY はこのスクリプトの対象外（各 `harnesses/<h>/validate-harness.sh` は設定カタログ検証。Hermes は `~/.hermes` / `~/.omh` の別系統で対象外）。
- `skills/_swarm-common/test-common.sh` swarm 共通ドキュメント

## swarm-\* 共通ドキュメント（`skills/_swarm-common/`）

swarm-\* skill が重複して持っていた定型の正典。`SKILL.md` が無いので skill としては列挙されない。

- `CORE.md`: SWARM.md の要約（約 7KB）と節の行範囲インデックス。各 skill は 63KB の SWARM.md 全文ではなくこれを読む。
- `HANDOFF.md` / `MEMORY_PROTOCOL.md` / `SKILL_STATE.md`: 各 skill は参照のみ持つ。
- `load.sh <doc> [--once] [--force]`: `--once` は同一セッション・TTL 90 分以内の再読込を 1 行スタブに置換する
  （サブエージェント内・コンテキスト圧縮後は `--force` か `--once` なし）。
- `refresh-index.sh`: **SWARM.md を編集したら実行**し、CORE.md の節インデックスを再生成する。
- `test-common.sh`: load.sh の挙動と、CORE.md のインデックスが SWARM.md と一致することを検証する。
