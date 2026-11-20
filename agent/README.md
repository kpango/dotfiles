# agent/ — 4 ハーネス (claude / omp / agy / hermes) 共通設定の正典

Claude Code・Oh My Pi・Antigravity・Hermes Agent が共有する設定・Rule・Skill・Agent・Swarm 規約の**単一ソース**。
ツール固有の設定は `harnesses/<name>/` に置く。`$HOME` 側への配線は `Makefile.d/install.mk` と
`nix/modules/home/dotfiles/agent-tools.nix` が `agent/` から**直接** symlink / 生成する（リポジトリ内に中間 symlink は無い）。
配線の正しさは `agent/scripts/sync-verify.sh` で検証する。

## 構成

```
agent/
├── rules/  skills/  agents/      共通正典（各ハーネスの $HOME 側へ直接 symlink）
├── models/                       抽象モデル Tier の schema・catalog
├── harnesses/{claude,omp,agy,hermes}/   ハーネス固有設定・model-routing.json・validate-harness.sh
├── hooks/{claude,agy,omp}/       hook 本体（各ツールの hooks / extensions へ個別ファイル symlink で合成）
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
- omp は `settings.json` を作らない（`config.yml` 等の YAML が正典。omp の移行処理が symlink を壊すため）。
- hermes は `agent/skills` を `~/.hermes/skills` へ、`profiles/*` を個別に symlink する。
- `AGENTS.md` / `SYSTEM.md` はハーネス別に `gen-*` スクリプトで生成し、`--check` で鮮度を検証する。
- 指示ファイルの根は 2 つだけ: グローバルは `agent/AGENTS.md`（+ `AGENTS-<tool>-supplement.md`）、dotfiles プロジェクト固有は
  リポジトリ直下の `AGENTS.md`。同じ場所の `CLAUDE.md` / `GEMINI.md` はそれへの symlink で、
  実体は 1 本（`test-root-agent-files.sh` が検証。編集は実体側で行う）。

## 共通化しないもの

- `CLAUDE.md` / ハーネス固有の `AGENTS.md`・`SYSTEM.md` のアイデンティティ部分
- `settings.json` / `config.yml` 等の実行時設定本体（スキーマがツール固有。共通部分のみ `settings-common.json`）
- ツール固有の拡張機構（omp `extensions/`、agy `policies/`・`hooks/`）。ただしルールデータは `*-rules.json` で共有する
- `SKILL.stats.json`: 実行時テレメトリ（`swarm-implement/scripts/stats-record.sh` が更新）。静的設定ではない

## MCP サーバー定義

Executor gateway（`mcpServers.executor`、`http://localhost:4788/mcp`）は 2026-11-20 に廃止した。trail 連携用のオンデマンド daemon で、
trail の退役後は待ち受けも導入もなく、定義だけが残っていたため（バイナリは PATH に無く、リポジトリ内にも起動する unit が無い）。
共有 MCP が必要になったら、各ハーネスの設定に直接定義する。
stdio のローカルコンテナ（agy の `serena`）は共有の URL 方式に載せられないため、`agy/mcp_config.json` を正典、
`agy/settings.json` を手動ミラーとする。`$comment` は `mcpServers` の**外**（ファイルルート）に置く
（内側に置くと偽サーバーエントリとして誤解釈される）。

## Tier B 書込保護

`skills/*/SKILL.md`・`skills/*/scripts/*`・`rules/*`・`agents/*`・`SWARM*.md`・hooks・`harnesses/*/model-routing.json`・
`*-rules.json` などは書込ゲートで保護される。正典は `skills/swarm-implement/scripts/write-scope-lib.sh` の
`write_scope_is_protected()`。変更するには人間承認のうえ単発 grant を発行する:
`skills/swarm-implement/scripts/budget-guard.sh --write-scope-grant <file-path>`（TTL 300 秒）。
パターンを変える場合は `write-scope-rules.json` も同時に更新し、`scripts/test-write-scope-parity.sh` で検証する。

`agent/` の物理構造を変更するときは、`claude/`・`omp/`・`agy/` 配下のパスをハードコードした参照が
`hooks/`・`skills/*/scripts/`・`rules/*.md` の frontmatter に残っていないかを grep で横断確認する
（`git status` や `make -n` では検出できない）。

## SSoT 同期検証

`scripts/sync-verify.sh`（引数なし、exit 0 = 全 PASS）は `sync-manifest.json` を読み、`$HOME` 側の配線を `readlink -f` で
実際に解決して検証する。モード: `symlink` / `generate`（`--check` で鮮度）/ `symlink-per-entry` / `live-copy-or-symlink`。
git worktree 内では `git rev-parse --git-common-dir` でメインのチェックアウトを解決する。新しい共通化を足すときは、
まず manifest に宣言する。bash で空フィールドを含むデータを `read` するときは、空白 class の区切り文字（tab 等）を避ける
（連続区切りが畳み込まれる）。`|` を使う。

## 検証コマンド

- `scripts/test-all-harnesses.sh` 全ハーネスの機械検証、`harnesses/<h>/validate-harness.sh` ハーネス別
- `scripts/test-catalog-health.sh` Skill / Agent カタログ、`scripts/test-security-rules.sh` Hard Floor
- `skills/_swarm-common/test-common.sh` swarm 共通ドキュメント

## swarm-* 共通ドキュメント（`skills/_swarm-common/`）

swarm-* skill が重複して持っていた定型の正典。`SKILL.md` が無いので skill としては列挙されない。

- `CORE.md`: SWARM.md の要約（約 7KB）と節の行範囲インデックス。各 skill は 63KB の SWARM.md 全文ではなくこれを読む。
- `HANDOFF.md` / `MEMORY_PROTOCOL.md` / `SKILL_STATE.md`: 各 skill は参照のみ持つ。
- `load.sh <doc> [--once] [--force]`: `--once` は同一セッション・TTL 90 分以内の再読込を 1 行スタブに置換する
  （サブエージェント内・コンテキスト圧縮後は `--force` か `--once` なし）。
- `refresh-index.sh`: **SWARM.md を編集したら実行**し、CORE.md の節インデックスを再生成する。
- `test-common.sh`: load.sh の挙動と、CORE.md のインデックスが SWARM.md と一致することを検証する。
