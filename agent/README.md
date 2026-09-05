# agent/ — claude / pi / agy(/codex) 共通設定ディレクトリ

このディレクトリは Claude Code（`claude/`）・Pi Coding Agent（`pi/`）・Antigravity（`agy/`）の
3 エコシステムが実質的に同一内容で重複管理していた設定・Rule・Skill・Agent・Swarm 規約を、単一の
ソースへ集約する場所である。各エコシステムのツール固有ファイル（後述「共通化しないもの」）はこれまで
どおり `claude/`・`pi/`・`agy/` 配下に残る。

**訂正（Phase 2 で判明）**: 本ファイルの初版（Phase 1）は skills/ を「85 ディレクトリ」と記載していたが、
これは誤りだった。実際のスキルディレクトリ数は **33**（85 は `find claude/skills -type f` の総ファイル数
であり、ディレクトリ数と取り違えていた）。以降の記載は訂正済みの数値を用いる。

## 調査結果

`claude/`・`pi/`・`agy/` 配下の実ファイルを md5sum/diff で全数比較した:

| 対象                                                                             | claude vs agy                                                                    | claude vs pi                                | 備考                                                                                                                                                                          |
| -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `rules/*.md`（4件）                                                              | 完全一致                                                                         | 完全一致                                    | 差分ゼロ、変換不要                                                                                                                                                            |
| `SWARM.md` / `SWARM_REFERENCES.md`                                               | 完全一致                                                                         | 完全一致                                    | 差分ゼロ、変換不要                                                                                                                                                            |
| `skills/`（**33ディレクトリ**）の静的部分（SKILL.md・scripts/・reference.md 等） | 完全一致                                                                         | 完全一致（`allowed-tools` frontmatter含む） | 差分ゼロ、変換不要                                                                                                                                                            |
| `skills/*/SKILL.stats.json`                                                      | **エコシステムごとに実際に異なる実行統計データ**                                 | 同左                                        | **Git管理下の実データ**（.gitignore対象外）。例: `security-scan` の実行回数は claude/pi=1回、agy=7回。集約対象から除外（後述）                                                |
| `self-improve-registry.tsv`・`harness-registry.tsv`                              | 当初はエコシステムごとに別内容（実行統計）だったが2026-09-04に単一正典へ統合済み | 同左                                        | `agent/skills/{swarm-loop,swarm-meta}/`へ統合。詳細は「registry.tsvの単一正典化」節参照                                                                                       |
| `agents/*.md`（25件）                                                            | 完全一致                                                                         | frontmatter `tools:` 行のみ機械的に異なる   | 例: `Read, Write, Edit, Bash, Grep, Glob`（claude/agy）↔ `read, write, edit, bash, grep, find, ls`（pi、全小文字化＋`Glob`→`find, ls`分割、順序は保持）。本文・順序以外は同一 |
| `AGENTS.md`(pi)/`SYSTEM.md`(pi/agy)/`CLAUDE.md`(claude)                          | 意図的に非共通                                                                   | 意図的に非共通                              | ツール固有のアイデンティティ・システムプロンプト。共通化対象外                                                                                                                |

**codex について**: `/usr/local/bin/codex` バイナリは本マシンに存在するが、`~/.codex/` 相当の設定
ディレクトリは存在せず、dotfiles にも codex 向けテンプレートは無い（未設定）。現状 codex は本ディレクトリ
の移行元にも移行先にもなり得ない。将来 codex 向け設定を新設する場合、本ディレクトリの内容を出発点にできる
かは別途調査が必要（codex の Skill/Agent 相当機構の有無が未確認のため）。

**Pi Coding Agent 自体の調査所見**（[github.com/earendil-works/pi](https://github.com/earendil-works/pi)、
[pi.dev](https://pi.dev/)）: Pi 本体はサブエージェント機構を持たない
（"Pi ships with powerful defaults but skips features like sub agents and plan mode"）。

**訂正（2026-09-03、agent-hooks-and-pi-agents-unificationミッションで判明）**: 本節の初版は
「`pi/agents/` が機能しているのはサードパーティ拡張`tintinweb/pi-subagents`経由と推定される」と
記載していたが、これは推測であり誤りだった。実際にsubagent機構を提供しているのは本リポジトリ
自身のfirst-partyコード`pi/extensions/subagents.ts`である（Pi Coding Agent本体の拡張機構
= Pi Extension API経由、`tintinweb/pi-subagents`はこの環境にインストールされていない）。
`tintinweb/pi-subagents`の仕様(固定3ディレクトリ・`Glob`概念なしの単純comma-split・登録API不在)は
WebFetchで裏取り済みで実在するが、それは**別のサードパーティ拡張の仕様**であり、このリポジトリの
subagent機構には適用されない。この誤認により「pi/agentsの実行時変換は技術的に不可能」という
誤った不採用判断が導かれていた(下記「pi/agentsの実行時変換について」節参照、現在は撤回・採用済み)。
first-partyコードである`subagents.ts`の`frontmatter`スキーマも当然自由に拡張可能で、
`disable-model-invocation`/`user-invocable`相当の制御フィールドが無いのは「まだ実装していない」
だけであり構造的制約ではない——Swarm系skill移行の設計課題としては変わらず残るが、既知のギャップの
性質(サードパーティの構造的制約 → 単なる未実装)が変わった点に注意する。

## 現状（Phase 1・Phase 1b・Phase 2・Phase 3、および2026-09-03のagent-hooks-and-pi-agents-unification実施後）

```
agent/
├── README.md          # 本ファイル
├── rules/              # claude/pi/agy 共通(4ファイル)
├── skills/              # claude/pi/agy 共通(33スキルの静的部分)
├── agents/              # claude/agy/pi 共通(25件、正典)。pi向けもagent/agentsへ直接symlink
│                          (旧gen-pi-agents.sh生成方式・pi/agents/実ディレクトリは廃止済み、
│                          tools:frontmatter変換はpi/extensions/subagents.tsの実行時変換へ移行)
├── hooks/               # claude/agy/pi hooks本体(計30ファイル、実体)。decide.py委譲shim
│                          (rule_engine.py/decide.pyを共有、計14ファイル: claude7+agy4+pi3)+
│                          rtk-rewrite.sh/rtk-optimizer.ts(判定ロジック共有は無い薄いラッパー、
│                          物理配置のみ統一、計3ファイル)+ claude固有の非shimロジック
│                          (swarm-*.sh等12ファイル、2026-09-04にclaude/hooks/から実体移動)の混在。
│                          各サブディレクトリは対応するツール側ディレクトリとper-file symlinkで
│                          merged directory化される
│                          (claude/ ⇔ claude/hooks/、agy/ ⇔ agy/hooks/、pi/ ⇔ pi/extensions/。
│                          詳細は下記「現在の設計」参照)
│   ├── claude/           # 20ファイル(security-gate.sh・vald-law*.sh等decide.py委譲shim7件+
│   │                        rtk-rewrite.sh(非decide.py、1件)+swarm-fable-gate.sh・
│   │                        swarm-post-edit-lint.sh・permission-request.sh等claude固有の非shim
│   │                        12件。claude/hooks/自体は現在空(.gitkeepのみ)、merged directoryの
│   │                        find走査対象としてのみ残る)
│   ├── agy/              # 5ファイル(security-gate.sh等decide.py shim 4件+rtk-rewrite.sh 1件)
│   └── pi/               # 5ファイル(decide.py shim 3件+rtk-optimizer.ts 1件+共有lib/shared.ts 1件)
├── scripts/
│   └── hooks/            # rule_engine.py・decide.py(判定ロジック本体、上記shimが呼び出す)
├── RTK.md               # claude/pi/agy 共通
├── SWARM.md             # claude/pi/agy 共通
└── SWARM_REFERENCES.md
```

**2026-09-03: リポジトリ内の claude/pi/agy 側 symlink を全廃した**（ユーザー指示:「dotfiles内部に
symbolic linkは不要、Makefile/nixだけが配置先を知っていればいい」）。以前は `claude/rules`・
`pi/rules`・`agy/rules` が `agent/rules` を指すディレクトリシンボリックリンク、`claude/agents`・
`agy/agents` が `agent/agents` を指すシンボリックリンク、`claude/RTK.md`・`pi/RTK.md`・`agy/RTK.md`
が `agent/RTK.md` を指すシンボリックリンク、`claude/skills/<name>/<entry>` 等が
`agent/skills/<name>/<entry>` へのファイル単位シンボリックリンクとして存在していたが、これらは
`Makefile.d/install.mk`（`claude/install`・`pi/install`・`agy/install` ターゲット）の実際の
`ln -sfvn` が最初から `agent/` を直接ソースとして `$HOME` 側へ symlink する設計になっていたため
（「リポジトリの見た目を `$HOME` の配置に似せる」ための中間層に過ぎず、install 処理からは元々
参照されていなかった）、実インストール挙動に一切影響を与えず削除できた。

現在の設計:

- **`claude/rules`・`claude/agents`・`claude/RTK.md`・`pi/rules`・`pi/RTK.md`・`agy/rules`・
  `agy/agents`・`agy/RTK.md` は存在しない**。`$HOME/.claude/rules`・`$HOME/.pi/agent/rules`・
  `$HOME/.agy/rules` 等は `Makefile.d/install.mk`（および `nix/modules/home/dotfiles/agent-tools.nix`）
  が `agent/rules`・`agent/agents`・`agent/RTK.md` から直接 symlink する。
- `claude/skills`・`pi/skills`・`agy/skills` は**実ディレクトリとして残る**（`agent/skills` への
  symlinkミラーではない）。動的な実行統計ファイル（`SKILL.stats.json`、`scripts/skill-stats.sh` が
  直接読み書きする git 管理下の実データ）だけを保持し、静的な entry（`SKILL.md`・`scripts/`・
  `reference.md` 等、以前はファイル単位symlinkだったもの）は完全に削除した
  （`self-improve-registry.tsv`・`harness-registry.tsv`は2026-09-04に`agent/skills/{swarm-loop,
swarm-meta}/`へ単一正典化済みのため、この2ファイルに関しては現在claude/pi/agy側に実体は無い。
  詳細は「registry.tsvの単一正典化」節参照）。$HOME 側の `~/.claude/skills` 等は `agent/skills` へ直接 symlink される
  ため、静的内容の配信自体はこのリポジトリ内ディレクトリを一切経由しない。
- `pi/agents` は**廃止済み**(2026-09-03)。`~/.pi/agent/agents` は claude/agy と同型で `agent/agents`
  へ直接 symlink される。tools: frontmatter の変換(PascalCase→pi-coding-agentのlowercase語彙)は
  ビルド時生成ではなく `pi/extensions/subagents.ts` の実行時変換(`mapToolNames`)へ移行済み
  （経緯は本ファイル冒頭「Pi Coding Agent 自体の調査所見」の訂正、および「pi/agentsの実行時変換
  について」節を参照）。
- `claude/hooks`・`agy/hooks`・`pi/extensions` の一部ファイル(decide.py委譲shim本体、計15ファイル)
  は `agent/hooks/{claude,agy,pi}/` へ実体移動済み(2026-09-03)。**claudeについては2026-09-04の
  claude-hooks-full-agent-consolidationミッションで、残っていた非shimファイル(swarm-\*.sh等
  Harness governance 5件+permission-request.sh等汎用lifecycle hook 7件、計12件)も含め`claude/hooks/`
  配下の全ファイルを`agent/hooks/claude/`へ実体移動した — `claude/hooks/`は現在空ディレクトリ**
  (対応するagy/pi実装が存在しないため単純な物理配置の統一のみ、判定ロジック共有はこれらのファイルには
  無い)。agy/piの非shimファイル(agy/hooks/post-edit-lint.sh、pi/extensions/bridge-*.ts等)は本ミッション
  のスコープ外のため元のディレクトリに実ファイルとして残る(claudeとの非対称は意図的、詳細は「rtk-rewrite.
  sh/rtk-optimizer.tsの物理配置統一について」節と同じ判断基準)。`$HOME` 側の `~/.claude/hooks`・
  `~/.agy/hooks`・`~/.gemini/hooks`・`~/.pi/agent/extensions`
  は、非shim側(元ディレクトリ、claudeは現在空)とshim側(`agent/hooks/`)の両方から個別ファイルsymlinkする
  「merged directory」として `Makefile.d/install.mk`・`nix/modules/home/dotfiles/agent-tools.nix`
  が構成する(単一ディレクトリsymlinkでは複数の物理ソースを1つのターゲットへ合成できないため。
  **訂正(2026-09-04、Phase 4.5 Round 3/4敵対的レビューで発見・時系列を明確化)**: 当初
  「findベースの走査のため空ディレクトリでもMakefile/nix側の変更は不要だった」と記述していたが
  誤りだった。`claude/hooks/`が空になった際に追加した`.gitkeep`(placeholder、下記
  「claude/hooks/.gitkeepについて」節参照)は拡張子.shを持たないため、当時の`Makefile.d/install.mk`
  (`claude/install`ターゲット)・`nix/modules/home/dotfiles/agent-tools.nix`の`mergedDirFiles`
  ヘルパーとも"regular"ファイルなら拡張子を問わず全て対象にしており、どちらも`.gitkeep`を
  誤ってsymlinkしてしまう状態だった(`claude/docker/install`ターゲットのみ元々`-name "*.sh"`
  フィルタを持っていたため無事だった)。Round 3で`Makefile.d/install.mk`の`claude/install`
  ターゲットへ`-name "*.sh"`フィルタを追加、Round 4で`nix`側にも
  `mergedDirPlaceholders`という名前ベースのblocklistを`mergedDirFiles`へ追加して揃えた
  (この関数は`.agy/hooks`ターゲットで`hooks.json`という非`.sh`ファイルも正当に含むため、
  拡張子allowlist化は他ターゲットを壊す。placeholder名のblocklist化で対処した)。
  修正後の現状: 5箇所の`mergedDirFiles`呼び出し全てと`claude/install`・`claude/docker/install`
  両ターゲットが`.gitkeep`を正しく除外する。)。
- `claude/SWARM.md`・`claude/SWARM_REFERENCES.md` は `agent/` へ移動済み。`Makefile.d/install.mk` の
  `DOTFILES_MAP`（6 destination 分）のソース列は `agent/SWARM.md`・`agent/SWARM_REFERENCES.md` を
  直接参照する（symlink chain を作らず単一ソースを直接参照する設計）。
- 配線の正しさ（`$HOME` 側の各symlinkが期待どおり `agent/` 等を指しているか）は
  `agent/scripts/sync-verify.sh` で機械検証できる（`agent/sync-manifest.json` を読み、実際に
  `readlink -f` で解決先を確認する）。

## MCP サーバー定義の統合（Executor gateway 経由）

`claude/settings.json` の `mcpServers`・`pi/mcp.json`・`agy/mcp_config.json` で個別定義していた
`memory`・`codegraph`・`filesystem` の3サーバーは、[Executor](https://executor.sh/)
（[github.com/UsefulSoftwareCo/executor](https://github.com/UsefulSoftwareCo/executor)、MIT
ライセンス）という MCP ゲートウェイへ集約した。3ツールとも `mcpServers` に `executor` という単一
エントリ（`http://127.0.0.1:4788/mcp`）だけを持ち、実際のサーバー定義は Executor 側のカタログで
一元管理される（`executor tools integrations` で確認可能）。

- `bun add -g executor` でインストール。`executor install`（OS常駐サービス化）は行っていない —
  `executor call` がオンデマンドで daemon を自動起動する挙動（`localhost:4788`）で運用している
  （永続サービス化は auto mode クラシファイアにブロックされたため未実施、今後常駐させたい場合は
  ユーザーが `executor install` を実行する）。
- サーバー登録は `executor call executor mcp addServer '{"transport":"stdio","name":"<name>",
"command":"<cmd>","args":[...]}'`（承認が必要、`executor resume --action accept` で確定）。
- **`filesystem` サーバーの許可パスは claude/pi 側の安全な範囲（`~/go/src/github.com/kpango`・
  `~/go/src/github.com/vdaas/vald`）を正典として採用した**。agy 側は従来 `/home/kpango` 全体を
  含む広い許可設定になっており（claude/CLAUDE.md に記載の通り、mcp filesystem ツールは
  `permissions.deny` の secret系ファイル保護をバイパスしうるため意図的に除外していたはずの範囲）、
  これは設定ドリフトだった可能性が高い。今回の統合で agy 側の広い許可設定は自動的に解消された
  （3ツールとも同一の安全な `filesystem` 定義を共有するため）。
- 各ツールのスキーマ差異はそのまま（`claude`: `{"type":"http","url":...}`、`pi`: `{"url":...}`、
  `agy`: `{"serverUrl":...}`、`add-mcp` の client 自動検出により agy 分は自動生成）。
  `lsp-rust`/`k8s`/`slack`（claude）、`lsp-go`/`lsp-rust`/`k8s-native`/`k8s-cli`/`serena`/`cipher`/
  `github`/`slack`（agy）等、共通でないサーバーは今回の統合対象外（各ツールに個別で残っている）。
- `add-mcp`（`bun add -g add-mcp`）は Claude Code・Antigravity（globalのみ）を自動検出して接続する。
  **Pi Coding Agent は `add-mcp list-agents` の対応リストに存在しない**ため、`pi/mcp.json` は手動編集した。

## 共通化しないもの（意図的に対象外）

- `AGENTS.md`（pi）/ `SYSTEM.md`（pi・agy）/ `CLAUDE.md`（claude）: ツールごとのアイデンティティ・
  システムプロンプト文言。内容の性質上、各ツールに固有であるべきもの。
- `settings.json` / `models.json` 等の実行時設定本体: 権限リスト・hooks 等はツール固有のスキーマに
  依存するため共通化しない（MCP サーバー定義のみ上記「MCP サーバー定義の統合」で部分的に集約済み）。
- `extensions/`（pi のみ）・`policies/`・`hooks/`（agy のみ）: 各ツール固有の拡張機構（I/Oプロトコル
  自体はツールごとに別物）。ただし `security-gate.sh`/`security-gate.ts` が判定に使う破壊的コマンド・
  機微パスの**ルールデータ**は `agent/security-rules.json` へデータレベルで共有済み（下記
  「hooks/ のルールデータ共有化」参照）。
- **`SKILL.stats.json`**: git管理下だがエコシステムごとの実行時テレメトリであり、静的な設定ではない。
  集約すると他エコシステムの利用履歴を上書き・消失させるため、意図的に集約対象から除外し各
  ディレクトリに real file のまま残す。
  **副次効果（意図的・望ましい挙動）**: `Makefile.d/install.mk` の `claude/docker/install` 等
  `*/docker/install` ターゲット（skills を `cp -R` でコンテナイメージへコピーする経路）は
  `agent/skills/` を参照元とするため、このテレメトリファイルはコピーされなくなった
  （移行前は各エコシステムの `skills/` に混在していたためコピーされていた）。新規コンテナが
  ホストの利用統計を継承しないのは望ましい挙動であり、これは意図した設計判断である
  （`code-reviewer` 指摘を受けて明記）。
  **`self-improve-registry.tsv`・`harness-registry.tsv` はこの限りではない**: これらは
  2026-09-04に単一正典（`agent/skills/{swarm-loop,swarm-meta}/`）へ統合した（「集約すると
  他エコシステムの利用履歴を上書き・消失させる」という上記SKILL.stats.jsonと同じ懸念は、
  この2ファイルについては該当しない——各行が`mission-slug`で一意に識別されるTSVレコードの
  「追記/置換」であり、SKILL.stats.jsonのような「エコシステム丸ごとの実行回数サマリを
  1つの値へ潰す」形の集約とは構造が異なるため。詳細は「registry.tsvの単一正典化」節参照）。
- ~~`pi/agents/*.md` の実ファイル本体: `agent/agents/*.md`（正典）からの生成物として real file のまま
  残す（tools: frontmatter がエコシステム固有のため symlink化できない）~~ — **この判断は2026-09-03の
  agent-hooks-and-pi-agents-unificationミッションで覆り、`pi/agents/` は廃止済み**。`tools:`
  frontmatterの変換は`pi/extensions/subagents.ts`の実行時変換（`mapToolNames`）へ移行し、
  `~/.pi/agent/agents`は`agent/agents`へclaude/agyと同型で直接symlinkされる（経緯は上記
  「Pi Coding Agent 自体の調査所見」の訂正、および「pi/agentsの実行時変換について」節を参照）。

## Tier B 保護・rule frontmatter との整合（今後の変更で必ず確認すること）

`SWARM.md`/`SWARM_REFERENCES.md`/`rules/`/`skills/`/`agents/` を `claude/`・`pi/`・`agy/` から
`agent/` へ移す変更は、それらのファイルパスをハードコードで参照する既存の仕組み（Tier B 書き込み保護・
rule frontmatter の autoload glob）を連鎖的に壊しうる。Phase 1・Phase 2 で発見・修正した実例:

- `claude/skills/swarm-implement/scripts/write-scope-lib.sh`（現在は `agent/skills/swarm-implement/
scripts/write-scope-lib.sh`）の `write_scope_is_protected()` は realpath サフィックスパターンで
  Tier B 書き込み保護を判定する。`*/agent/SWARM.md`・`*/agent/SWARM_REFERENCES.md`・
  `*/agent/skills/*/SKILL.md`・`*/agent/skills/*/scripts/*`・`*/agent/skills/*/*.md`・
  `*/agent/agents/*` パターンを追加済み。**`*/claude/skills/*`・`*/claude/agents/*` の旧パターンは
  Phase 2 で全て symlink 化されたことで到達不能な死んだパターンとなったため削除済み**（no-dead-code
  原則）。
- `agent/rules/harness-design.md` の frontmatter `paths:`（autoload glob）にも `**/agent/skills/**`・
  `**/agent/agents/**` を追加済み。
- **今後 `agent/` 配下の物理構造を変更する場合は、`grep -rn "claude/SWARM\|claude/rules\|claude/skills\|claude/agents\|pi/SWARM\|pi/rules\|pi/skills\|pi/agents\|agy/SWARM\|agy/rules\|agy/skills\|agy/agents"` 相当で `claude/hooks/`・`agent/skills/*/scripts/`・`rules/*.md` の frontmatter を横断検索し、パス参照のハードコードが無いか確認すること**（`git status`/`make -n` だけでは検出できないクラスの回帰であり、`code-reviewer` の指摘で2回とも発見された）。

## SSoT 同期フレームワーク（`sync-manifest.json` + `sync-verify.sh`）

`/swarm-architect` フル設計モードの提案（`ssot-dotfiles-sync-framework`, 2026-09-02）を受けて新設。
「何が正典で、各エコシステムへどう配線されるか」を `agent/sync-manifest.json` に宣言的に記述し、
`agent/scripts/sync-verify.sh` で機械検証する。今後新しい共通化候補を見つけたら、まず manifest への
追加を検討する（既存の symlink/生成スクリプトを個別に検証するアドホックな手法を積み重ねない）。

**発端となった事故**: 直前の `pi-agent-config-consolidation` ミッションで `claude/SWARM.md` 等を
`agent/SWARM.md` へ移動した際、`Makefile.d/install.mk` の参照元は正しく更新したが、
**`make claude/install`・`pi/install`・`agy/install` を実際には一度も実行せず、`make -n`
（dry-run）のみで検証を終えていた**。結果、ライブ環境（`~/.claude`・`~/.pi/agent`・`~/.agy`・
`~/.gemini`）の `SWARM.md`・`SWARM_REFERENCES.md` symlink が全6箇所とも壊れたまま放置され、
`/swarm-architect` の調査で発覚した（`make dotfiles/install && make {claude,pi,agy}/install`
を実行して修復済み）。`sync-verify.sh` の `live-copy-or-symlink` モードはこの再発を機械検出する。

**4つのmode**:

| mode                   | 対象                                                                  | 検証内容                                                                                                                  |
| ---------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `symlink`              | `rules`・`agents`（claude/agy/pi分、2026-09-03以降pi分もsymlink方式） | targetがcanonicalを指すsymlinkであること                                                                                  |
| `generate`             | `AGENTS.md`・`SYSTEM.md`（pi/agy分）                                  | 対応スクリプトの`--check`で鮮度検証（旧`gen-pi-agents.sh`が持っていた契約の一般化。同スクリプト自体は2026-09-03廃止済み） |
| `symlink-per-entry`    | `skills`                                                              | canonical配下の全entryがtarget側に存在すること（動的ファイルは自然に対象外）                                              |
| `live-copy-or-symlink` | `SWARM.md`・`SWARM_REFERENCES.md`                                     | リポジトリ側でなく`$HOME`配下のライブ環境への到達可能性                                                                   |

`not_shareable` にはこれまでの調査で「集約不可能」と判定した対象（`settings.json`・`hooks/*.sh`・
`validate-harness.sh`・`keybindings.json`・`AGENTS.md`/`SYSTEM.md`/`CLAUDE.md`・MCP個別定義・
動的テレメトリファイル）とその理由を記録し、次に似た判断を迫られたときの再調査を省略できるようにする。

**実装時に踏んだbashの罠**（`sync-verify.sh` 自体の教訓、他スクリプトでも再発しうる）:
`IFS=$'\t'`（タブ）で `read` すると、bashは空白class文字（space/tab/newline）の連続を1つに
畳み込む（POSIXのフィールド分割と異なり、awkのデフォルト分割と同じ挙動）。本manifestは
`script` フィールドが空文字になる行（symlink/live-copy-or-symlinkモード）があり、空欄の前後で
タブが連続するため、後続フィールド（`canonical`）の値が1つ前のフィールドへ吸われて空になるという
実害が出た。区切り文字を空白class外の `|` に変更して解決した。今後 tab区切りのデータをbashで
`read` する設計をする際は、空フィールドが生じうるかどうかを必ず確認すること。

**使い方**: `agent/scripts/sync-verify.sh`（引数なし、exit 0=全PASS・1=FAILあり）。CI/pre-commit
hookへの配線は未実施（今回のスコープ外、次のフォローアップ候補）。

## rtk-rewrite.sh/rtk-optimizer.tsの物理配置統一について（2026-09-04、決定の変更）

`agent-hooks-and-pi-agents-unification`ミッション完了時点では、`rtk-rewrite.sh`（claude・agy）・
`rtk-optimizer.ts`（pi）は「decide.py委譲shimではない（`rule_engine.py`/`decide.py`を呼ばない、
外部`rtk`バイナリの`rtk rewrite`サブコマンドへ委譲するだけの薄いラッパー）」ことを理由に、hooks統合
（`agent/hooks/{claude,agy,pi}/`への実体移動）の対象外としていた。

ユーザーからの追加要望（2026-09-04）により、この判断を変更し`agent/hooks/{claude,agy,pi}/`へ
実体移動した。3実装（claude=bash+jq、agy=bash+embedded python3、pi=TypeScript）は依然として
**判定ロジックを共有していない**（各ツールのhook I/Oスキーマへ翻訳するだけの独立実装のまま、
`rule_engine.py`/`decide.py`は呼ばない）——今回の統合は「decide.py委譲shimと同じ物理ディレクトリへ
配置する」という**物理配置レベルの一貫性**のみが目的であり、ロジック統合ではない点に注意する。
既存のmerged directory機構（`Makefile.d/install.mk`の`find <src> -maxdepth 1 -type f -exec
ln -sfvn`ループ）は拡張子・ファイル名でフィルタしないため、3ファイルを`git mv`するだけで自動的に
デプロイ対象へ含まれた（Makefile/nix側の追加変更は不要、実機`make claude/install pi/install
agy/install`後に`~/.claude/hooks/rtk-rewrite.sh`等へ正しくsymlinkされることを確認済み）。

3ファイルとも repo-relative なパス解決ロジック自体を持たない（`dirname`/`$BASH_SOURCE`/
`import.meta.url`によるrepo root探索を一切行わない、外部`rtk`コマンドを`$PATH`経由で呼ぶだけ）ため、
2026-09-03のCRITICAL回帰（merged directory化によるroot解決崩壊、上記「hooks/ のルールデータ
共有化」節以降の「パス注記」参照）と同種のリスクは無い。

## hooks/ のルールデータ共有化（`agent/security-rules.json`）

**パス注記(2026-09-03、agent-hooks-and-pi-agents-unificationミッション以降)**: 以下の本節および
後続の複数節(判定ロジック統合・Vald Law統合・memory_context統合等)は、`claude/hooks/*.sh`・
`agy/hooks/*.sh`・`pi/extensions/*.ts`という当時の実際のファイル配置を前提に書かれた歴史的記録
であり、意図的にそのまま残してある。decide.py委譲shim本体(security-gate.sh・graphify-hint.sh・
vald-law*.sh・session-start.sh等)は現在 `agent/hooks/{claude,agy,pi}/` へ実体移動済みで、
以下の記述にある`claude/hooks/xxx.sh`は`agent/hooks/claude/xxx.sh`、`agy/hooks/xxx.sh`は
`agent/hooks/agy/xxx.sh`、`pi/extensions/{security-gate,graphify-hint,auto-memory}.ts`・
`pi/extensions/lib/shared.ts`はそれぞれ`agent/hooks/pi/`配下と読み替えること(現状の正確な配置は
本ファイル冒頭「現状」節のディレクトリツリーを参照)。claude/agy固有の非shimファイル
(permission-request.sh・post-write.sh・post-edit-lint.sh等)は移動対象外で元のパスのまま。
**追記(2026-09-04)**: `rtk-rewrite.sh`（claude/agy）・`rtk-optimizer.ts`（pi）は当初この「移動
対象外」リストに含まれていたが、後続の統合作業で`agent/hooks/{claude,agy,pi}/`へ実体移動済み
（判定ロジックの共有は無い＝decide.py委譲shimではないが、物理配置の一貫性のため。詳細は下記
「rtk-rewrite.sh/rtk-optimizer.tsの物理配置統一について」節参照）。
**追記(2026-09-04、claude-hooks-full-agent-consolidationミッション)**: 上記文中の
`permission-request.sh`・`post-write.sh`(claude側)も、この「移動対象外」リストに含まれていたが、
claude/hooks/配下の残存全ファイルをagent/hooks/claude/へ実体移動する対応の一環で
`agent/hooks/claude/permission-request.sh`・`agent/hooks/claude/post-write.sh`へ実体移動済み
（判定ロジックの共有はやはり無いが、claude固有ファイルは全てagent/hooks/claude/へ集約する方針へ
転換したため）。`post-edit-lint.sh`(agy側)は本ミッションのスコープ外のため`agy/hooks/`に残ったまま
で変更なし。

`/swarm-architect` フル設計モードの提案（`ssot-dotfiles-sync-framework`, 2026-09-02）は当初、hooks/
のルールデータ共有化（案2）を「既存の枯れたセキュリティコードへの変更は正規表現の意味を誤って変え
防御が劣化するリスクが高い」として独立した安全審査付きミッションに先送りしていたが、本ミッションで
そのミッションとして着手・完了した。

**構成**: 破壊的コマンド判定（`shell_command_rules`）と機微パス書き込み判定
（`sensitive_write_path_rules`）のルール**データ**を `agent/security-rules.json` に一本化し、以下の
5実装が実行時に読む（うち`permission-request.sh`は2026-09-03に追加、詳細後述。以下の表の
パスはいずれも現在の正典配置`agent/hooks/{claude,agy,pi}/`基準——`security-gate.sh`・
`write-security-gate.sh`・`permission-request.sh`は2026-09-03/04にそれぞれ`agent/hooks/claude/`へ
実体移動済み）:

| 実装                                        | 消費するルール               | 備考                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------- | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `agent/hooks/claude/security-gate.sh`       | `shell_command_rules`        | `tier=block`を全件評価してから`tier=ask`を評価する2パス構成（後述の罠対策）                                                                                                                                                                                                                                                                                                                                                                                                             |
| `agent/hooks/claude/write-security-gate.sh` | `sensitive_write_path_rules` | 既存の`realpath -m`正規化・大小文字無視は維持                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `agent/hooks/claude/permission-request.sh`  | `sensitive_write_path_rules` | Bashコマンドの自動承認可否を判定する`SENSITIVE_HIT`計算にのみ使う（block/ask/allowを直接返す実装ではない）。2026-09-03に独自の14項目ハードコードリストから移行、`.gnupg`・`.cargo/credentials`・`.npmrc`・`/etc/passwd`等・`/boot`・`/sys`・`/proc`・`/dev`・systemd unit配下が判定漏れになっていたギャップを修正済み。ルールデータ欠落時はfail-safe(センシティブ扱いにして自動承認をスキップし通常確認へ委ねる)— 他3実装のfail-open(無条件allow)とは意図的に非対称、理由は本節末尾参照 |
| `agy/hooks/security-gate.sh`                | 両方                         | agyには`ask`相当の中間承認primitiveが無いため、`tier=ask`も`tier=block`と同じくdenyへ倒す                                                                                                                                                                                                                                                                                                                                                                                               |
| `pi/extensions/security-gate.ts`            | 両方                         | `ctx.hasUI`時は両tierとも確認ダイアログ、UI無しでは両tierともhard block。Vald Law 1/2チェックは引き続きpi固有として本ファイルに残す                                                                                                                                                                                                                                                                                                                                                     |

**JSONの設計原則**（3実装を突き合わせて判明した保護範囲の差異は、最も広い版を正典として採用する
「安全側統合」— 詳細は `agent/security-rules.json` の `$comment` 参照）:

- **PCRE互換構文**で記述し、`grep -P`（bash）・Python `re`・Node `RegExp`いずれでも同一解釈される
  ことを`agent/scripts/test-security-rules.sh`でテスト済み。唯一 `(?i)` インライン大小文字無視フラグ
  だけはNode RegExpが構文エラーにするため、pi実装側で先頭の`(?i)`を検出し外側のflagsへ変換する
  `compileRegex()`ヘルパーで吸収した。
- **`force_push_protected_branch`・`git_reset_hard_protected_branch`** は正規表現1本で表現できない
  手続き的ロジック（ブランチ一覧の`{branches}`テンプレート展開、`cd`/`git -C`によるターゲット
  ディレクトリ解決）を持つため、ルールIDで分岐する専用コードを各実装に残した（JSON側は
  `protected_branches`/`cd_target_pattern`/`dash_c_target_pattern`等のデータのみを持つ）。
- **`git_reset_hard_protected_branch`のcd/-C対応はagy/piには元々無かった**（hookプロセス自身のcwd
  だけで判定しており、`cd /other/repo && git reset --hard`がすり抜ける抜け穴があった）。claude実装に
  倣い本統合でagy/piにも追随させた（保護範囲の拡大、意図的）。
- **`tier=ask`のagy/piへの倒し方**: agyは元々`git clean -f`（`-fdx`の有無を問わず）を無条件denyに
  していたため、ask→denyは既存の保護範囲を狭めない。`git checkout .`はagy/pi双方に元々チェックが
  無かったため、ask→deny/block-with-confirmは**新規追加の保護**である（安全側統合の原則に整合する
  判断だが、範囲拡大自体は本ミッションの意図的な選択であることを明記する）。

**検証**: `agent/scripts/test-security-rules.sh`が4実装を実プロセス（`claude`/`agy`はstdin JSON経由、
`pi`は`bun`でTypeScriptハンドラを直接起動）で駆動し、block/ask/deny/allowの判定結果を確認する
（引数なし、exit 0=全PASS）。個別のPython向け正規表現検証には
`/tmp/.../scratchpad/security_rules_validator.py`（セッションローカル、リポジトリ非管理）も使った。

**`agent/hooks/claude/permission-request.sh`のsensitive_write_path_rules利用（2026-09-03追加、
2026-09-04に`claude/hooks/`から実体移動）**:
Bashコマンドを「確認なしで自動承認してよいか」判定する際、コマンドが参照するパスが機微パスかどうかの
判定に`sensitive_write_path_rules`を再利用する。以前は`.env`・`.pem`・`.key`・`.p12`・`.pfx`・
`id_rsa`・`id_ed25519`・`.ssh/`・`.netrc`・`.kubeconfig`・`.kube/config`・`.tfstate`・
`terraform.tfvars`・`.aws/credentials`・`.credentials.json`のみを対象とする独自の14項目ハードコード
リストを持っており、`write-security-gate.sh`（`agent/security-rules.json`を既に消費していた）とは
別に手動維持されていたため、`.gnupg`・`.cargo/credentials`・`.npmrc`・`/etc/passwd`等の`etc_auth`・
`/boot`・`/sys`・`/proc`・`/dev`・systemd unit配下が判定漏れになっていた（例:
`cat ~/.gnupg/secring.gpg`が誤って自動承認対象になりうる状態だった）。このギャップを実際のコマンド
実行で再現・確認した上で修正し、リグレッションテストを追加した。合わせて`agent/security-rules.json`
自体に欠けていた`terraform_state`（`\.tfstate(?:\.backup)?$`）・`terraform_vars`
（`terraform\.tfvars(?:\.json)?$`）ルールを新設した（`claude/settings.json`の`permissions.deny`と
旧`permission-request.sh`には既にあったが、`write-security-gate.sh`・`agy/hooks/security-gate.sh`側
には無く、agyでの`*.tfstate`/`terraform.tfvars`書き込みが無保護だった）。security-rules.jsonの
パターンは`(?:...)`等PCRE構文を含むため、`permission-request.sh`側の照合は`grep -E`ではなく
`grep -P`（write-security-gate.shと同じ）を使う。**fail-open/fail-safeの非対称は意図的**:
security-gate.sh/write-security-gate.sh/agy/pi実装はルールデータ欠落時にfail-open（無条件allow/何も
しない）——ルール無しで壁を作れないなら壁を作らない設計——だが、permission-request.shは逆にfail-safe
（判定不能な全コマンドをセンシティブ扱いにし、自動承認をスキップして通常の確認ダイアログへ委ねる）。
ここでの誤判定コストは「確認が1回増える」程度に過ぎず、破壊的操作のブロック（他4実装の役目）とは
コストの非対称性が異なるため、より安全側に倒す判断とした。

**既知の限界（fail-open）**:

- `agent/security-rules.json` が見つからない・パースできない場合、上記5実装のうち4実装（`security-gate.sh`系・pi）は fail-open（allow/何もし
  ない）になる（`permission-request.sh`のみ上記のとおりfail-safe）。claude/agy/piいずれの通常インストール
  経路（`agent/hooks/{claude,agy,pi}/`とツール固有ディレクトリのper-file symlink合成による
  merged directory、2026-09-03以降）でも`readlink -f`でファイル自身のsymlinkを先に解決してから
  `dirname`する方式（bash）/`fs.realpathSync(fileURLToPath(...))`をファイルパス自身へ`dirname`より
  先に適用する方式（pi、`import.meta.url`がbun/nodeの現行実装では既にsymlink解決済みのパスを返す
  ためこの`realpathSync`は多くの場合冪等なno-opだが、bashの修正と同じ順序へ意図的に揃えることで
  将来のbun/node実装変化に依存しない設計にした — 2026-09-03 Phase 4.5 Round 2レビューで指摘・修正）
  で正しくリポジトリルートを辿れることを実測済みだが、`Makefile.d/install.mk`の`claude/agy/pi`
  いずれの`docker/copy-install`ターゲット
  （symlinkでなく実体コピー）でもこの解決は破綻し、常にfail-openになる(agy限定ではなく3ツールとも
  同一の制約 — 2026-09-03のagent-hooks-and-pi-agents-unificationミッションPhase 4.5 Round 2
  レビューで、旧記述がagy限定のoverclaimだったことが指摘され訂正)。当面は許容する（同様の
  docker/copy-installターゲットは元々このアーキテクチャが最初から想定していなかった経路であり、
  通常のsymlink/merged directoryインストール経路が主）。
  **既知の関連バグ(発見・修正済み)**: 同ミッションのT2実装(merged directory化)は当初、旧来の
  「ディレクトリ自体がsymlink」前提の`cd -P "$(dirname "${BASH_SOURCE[0]}")"`idiomをそのまま
  引き継いでいたため、merged directory化後は`dirname`がファイル名を落としてから評価される結果
  ディレクトリ自体は実体でありsymlink解決が一切行われず、ROOTが誤ったパスに解決してfail-openする
  CRITICAL回帰を生んでいた(security-adversarial-reviewer・shell-config-adversarial-reviewer
  双方が独立に発見・実機再現、readlink -fでファイル自身のsymlinkを先に解決する方式へ修正済み)。
- `agent/hooks/claude/write-security-gate.sh`（2026-09-03に`claude/hooks/`から実体移動済み、
  および同ルールを読むagy/pi実装）は、`realpath -m`で
  symlinkを完全解決してから機微パスと照合する。この環境の `~/.ssh` は`pass`管理下のパスへの
  symlinkであるため、`realpath -m`解決後は文字列`.ssh`が経路から消え、`~/.ssh/config`のような
  basename非依存のファイルは`ssh_keys`ルールの対象から漏れる（`id_rsa`/`id_ed25519`/`id_ecdsa`と
  いうbasename自体にマッチする`ssh_id_files`ルールでのみカバーされる）。**これは本統合による
  回帰ではなく、旧実装（`realpath -m`によるsymlink完全解決という既存設計そのもの）から引き継いだ
  既知の穴であることを実測で確認済み**（`git show HEAD:claude/hooks/write-security-gate.sh`を
  同じ入力で実行し同一の許可判定になることを確認した）。symlink管理下の機微ディレクトリを持つ
  環境固有の限界であり、修正するには「realpath解決前後の両方の文字列で照合する」等の設計変更が
  必要 — 本ミッションのスコープ外として記録するに留める。

## graphify-hint のデータ共有化（`agent/graphify-hint-config.json`）

「その他に共通化できる部分はありますか」というユーザーからの問いを受けた棚卸しで発見・着手。
grep/find検出時にgraphifyの利用を提案するhookが claude/agy/pi 3実装とも存在したが、突き合わせた
結果 **agyの実装は判定ロジックだけ書いてありヒント出力自体を一度も行っていなかった**
（`for ws in workspaces: ... break` で存在確認した結果を握り潰し、常に `{"decision":"allow"}`
だけを返す死んだコードだった）。`session-start.sh`が既に使っている`context`フィールド
（PreToolUse hookの出力としてagyが受理する、モデルへの追加コンテキスト注入手段）を使って
実際にヒントを返すよう修正した。

検出パターン（コマンド名の網羅性）・グラフパス候補（`.claude/`・`.gemini/`両方を見るかどうか）
も3実装で微妙に食い違っていたため、最も広い版を正典として `agent/graphify-hint-config.json`
にデータ化した。検証は `agent/scripts/test-graphify-hint.sh`（3実装を実プロセス起動）。

## Vald Law hook の強制力統一（`agent/vald-law-rules.json`）

同じ棚卸しで発見。Vald Law（1〜5）の強制力が3ツールで大きく食い違っていた:

| ツール     | Law 1                     | Law 2            | Law 3/4/5                                 |
| ---------- | ------------------------- | ---------------- | ----------------------------------------- |
| claude(旧) | PreToolUse block          | PreToolUse block | **PostToolUse warn のみ(ブロックしない)** |
| agy(旧)    | PreToolUse deny           | PreToolUse deny  | PreToolUse deny                           |
| pi(旧)     | block(security-gate.ts内) | block(同左)      | **チェック自体が存在しない**              |

`agent/vald-law-rules.json`へ判定データ(Law1の生成ファイルpattern・Law2の禁止コマンド一覧・
Law3/4/5のcontentルール・vald_repo_pattern)を集約し、以下の設計判断で統一した:

- **claude**: `vald-law345-check.sh`をPostToolUse(書き込み後にファイル全文を読んで警告するのみ)
  からPreToolUse(書き込み前に検査、ask-tier)へ引き上げた。Write/Edit/MultiEditそれぞれの
  `tool_input`実フィールド(`content` / `old_string`+`new_string` / `edits[].new_string`)は
  実際にツールを呼び出して実測確認した（公式ドキュメントに明記が無かったため）。検査対象も
  「ファイル全文の再走査」から「その変更が新たに持ち込む内容のみ」へ絞った(既存箇所への
  重複指摘を避ける、意図的な変更)。vald側の `.claude/settings.json` も
  `PostToolUse:Write|Edit|MultiEdit` → `PreToolUse:Write|Edit|MultiEdit` へ配線変更した。
- **agy**: 元々PreToolUse denyだったため据え置き、データソースを共有JSONへ差し替えただけ。
  `is_vald`判定を緩い部分文字列一致(`'vald' in path`、`myvald-test`のような無関係なpathも
  誤検知しうる)から`vald_repo_pattern`(`vdaas/vald`パスセグメント一致)による厳密な判定へ
  改善した。
- **pi**: Law3/4/5チェック自体が存在しなかったため新規追加。`security-gate.ts`の
  write/editハンドラへ組み込んだ。pi の`edit`ツールの実スキーマは`old_string`/`new_string`
  ではなく`edits: [{oldText, newText}]`という配列形式である点を、ローカルにキャッシュされた
  `@earendil-works/pi-coding-agent`パッケージの型定義(`dist/core/tools/edit.d.ts`)を読んで
  確認した(既存のpath解決ロジックは`file_path || path`のfallbackで元々対応できていたが、
  content抽出は新規に対応が必要だった)。

Law2の対象コマンドに`test`を追加(claude旧実装は`build|run|install`のみで`go test`/
`cargo test`を見逃していた、agy実装は元々`test`を含んでいた)。`agent/agents/vald-reviewer.md`・
`claude/CLAUDE.md`のVald Project Hooksテーブルもこの変更に合わせて更新した。検証は
`agent/scripts/test-vald-law-rules.sh`（5実装を横断検証）。

**security-audit agentレビュー(2026-09-03)で検出・修正した問題**（Critical無し、High 2件・
Medium 1件）:

- **[High] `vald_repo_pattern`の末尾アンカーがコマンド文字列マッチを壊していた**: 当初版
  `(?:^|/)vdaas/vald(?:/|$)`はパス文字列専用の設計で、agyのLaw2フォールバック
  (`cd /x/vdaas/vald && go build`のようなコマンド文字列自体への一致確認)を静かに機能不全に
  していた。`(?:^|/)vdaas/vald(?=/|$|[\s;&|])`(lookaheadでシェル区切り文字も許容)へ修正。
- **[High] `law2_prohibited_commands`の`^`アンカーが複合コマンドを見逃す既存の穴**:
  claude/agy旧実装から引き継いだ`^go\s+(?:build|...)`のような先頭アンカーは
  `cd /path/to/vald && go build`のような複合コマンドにそもそもマッチしなかった(vald判定以前の
  問題、この統合作業で初めて気付いた既存の穴)。`(?:^|[;&|])\s*go\s+...`(先頭、または`;`/`&`/`|`
  区切り直後)へ緩め、単体コマンドの誤検知を増やさず複合コマンド内の出現も検出できるようにした。
- **[High] agyのLaw3/4/5が`workspacePaths`のみで判定し、Write/Editの実ターゲットパスを見ていなかった**:
  `workspacePaths`にvald一致entryが無ければ、書き込み先が実際にvald配下でも丸ごとすり抜けていた
  (piは元々`ctx.cwd`と対象パスの両方をORしておりagyだけこの判定漏れがあった)。target自体も
  `vald_repo_pattern`で判定に加えた。同じ箇所を触ったついでに、Law1のtool_name whitelistには
  含まれるのにLaw3/4/5には含まれていなかった`edit_file`の欠落(この統合以前からの既存の穴)も
  修正した。
- **[Medium] pi(global extension)のLaw2がセッションcwdのみで判定しコマンド埋め込みの`cd`を
  見ていなかった**: `cd /other-repo && ...`でセッションのcwdがvald外であれば丸ごとすり抜けた。
  `security-rules.json`の`git_reset_hard_protected_branch`と同型の`cd_target_pattern`/
  `dash_c_target_pattern`によるターゲットディレクトリ解決を`commandTargetsVald()`として追加した。
  claude側は同種の対策ではなく、project-scoped hookという設計そのものにより「配線されていれば
  無条件にチェックする」(旧claude実装の元々の設計に復元、余分なcwdゲートを削除)で解決した。

いずれも`agent/scripts/test-vald-law-rules.sh`へ再発防止の回帰テストを追加済み。指摘の詳細な
根本原因分析はsecurity-auditの永続メモリ(`.claude/agent-memory/security-audit/`)にも記録されている。

## validate-harness.sh の共通ライブラリ化（`agent/scripts/harness-check-lib.sh`）

claude/pi/agy それぞれの `validate-harness.sh` は検証項目自体（各ツールのsettings.jsonスキーマに
依存する部分）は大きく分岐しており、ファイル全体の1本化は対象外（上記「共通化しないもの」参照）。
一方で `check()` 関数（PASS/WARN/FAIL集計と整形出力）は3ファイルでbyte-identicalだったため、
`agent/scripts/harness-check-lib.sh` へ切り出した（`check()`・外部test-*.shの結果を1件のcheckへ
畳み込む `harness_run_shared_test()`・最終サマリを出す `harness_summary()`）。

あわせて2種類のstalenessを発見・修正した:

- **pi/validate-harness.sh が独自コピーの古いセキュリティ正規表現を持っていた**（本フェーズの
  最優先修正項目）: 「Security Gate Pattern Verification」節が `agent/security-rules.json` への
  参照ではなく、パターンを再度ハードコードしており、`nvme[0-9]n[0-9]`（bare controller device
  未対応の旧版）等が古いまま残っていた。3ファイルとも該当節を削除し、`harness_run_shared_test`
  経由で `agent/scripts/test-security-rules.sh`・`test-vald-law-rules.sh`・`test-graphify-hint.sh`
  へ委譲する形に統一した。
- **claude/validate-harness.sh のMCPサーバーチェックがExecutor gateway移行前の名前のまま**:
  `mcpServers.codegraph`/`mcpServers.filesystem`/`mcpServers.memory` を個別に確認していたが、
  これらは本セッションのExecutor gateway統合で既に `mcpServers.executor` 1エントリへ集約済み
  だった。単一の `mcpServers.executor.url` チェック + `executor` バイナリのPATH確認へ置き換えた
  （pi/agy側は元々該当チェックを持っていなかった、またはEexecutorキー名は正しかったため対象外）。

3ファイルとも最終テスト結果はクリーン（claude: 53/59 pass・5 warn・0 fail、warnはいずれも
環境依存の任意ツール未導入、pi: 71/71 pass、agy: 52/52 pass）。

## settings.json 部分値の共通化（`agent/settings-common.json`）

claude/pi/agy の `settings.json` はトップレベルキー体系が根本的に別物（上記「共通化しないもの」
参照）であり、ファイル全体のテンプレート化・生成対象にはしない。一方で調査の結果、値まで完全一致
していた少数のキーと、意図的にスクリプト参照を共有しているキーが見つかったため、それらだけを
対象にした軽量な補助データ `agent/settings-common.json` を新設した:

- **`shared_values`**: `worktree.symlinkDirectories`（claude/agyで15要素の配列が完全一致、pi には
  `worktree` キー自体が存在しないため対象外）・`subagentPromptCacheTtl`（claude/agyで`"1h"`が
  完全一致）・`autoMemoryEnabled`（claude/agyで`true`が完全一致、piには存在しないため対象外）の3キー。
- **`status_line`**: `agy/settings.json` の `statusLine.command` は `claude/statusline-command.sh`
  をそのまま参照している。これがバグ（本来は独立実装すべきものの誤参照）ではなく正しく機能する
  意図的な共有であることを、`agy -p` の非対話print modeで実際にstatusLine呼び出し時のstdin JSONを
  捕捉して実機検証した（2026-09-03）。捕捉したJSONは `cwd`/`model.display_name`/
  `context_window.remaining_percentage` を含め `claude/statusline-command.sh` が実際に参照する
  フィールドと同一のパス・名前で存在することを確認済み。`pi/extensions/status-line.ts` は
  外部コマンド+stdin JSONプロトコルではなくpi-coding-agent拡張APIの `ctx.ui.setStatus()` を使う
  TUI内蔵実装であり、この方式では共有できないため独立実装のまま維持する（pi側の設計として妥当、
  変更不要と判断）。
- **`model_profiles`**: claude(Anthropic専用)・pi(複数provider対応)・agy(Google Gemini専用)は
  モデル名のvocabularyが根本的に別物であり「同じモデル名を共有する」ことはできない。代わりに
  named profile（例: `"baseline"`）ごとに各ツールが自分のvocabularyで対応するモデルIDを登録する
  マッピング方式を採用した。`current` を書き換えて `apply-settings-common.sh` を実行すれば
  3ツールへ伝播できる。現状は1プロファイル(`baseline`)のみで、2026-09-03時点の各ツールの実設定を
  そのまま登録した(新規選定ではない追認)。`pi.defaultModel` が明らかに古いモデルID
  (`claude-3-7-sonnet-20250219`)であることを検出したが、どの現行モデルへ更新するかはユーザー判断が
  必要なため、抽象化機構の構築に留め値自体は変更していない。

検証は `agent/scripts/test-settings-common.sh`（読み取りのみ、各ツールの実settings.jsonとの
drift検出、非0 exitでdrift件数を報告）、反映は `agent/scripts/apply-settings-common.sh`
（`--dry-run` 既定/`--apply` で明示実行、jqによる該当json_pointerのみの surgical な書き換え）。
Python の `json.load`+`json.dump` は使わない — 検証中に実際に発生させて確認した副作用として、
`ensure_ascii=True` の既定挙動により非ASCII文字（em-dash等）が `\uXXXX` へエスケープされ、かつ
ファイル全体が再整形される（コミット直前に `git checkout` で復旧した実例がある）。両ツール実行の
安全性はドリフト注入→検知→dry-run→apply→再検証のサイクルを実際に1周させて確認済み（unicode保持・
対象外キーの無変更・apply後のgit diffが完全に空になることまで含めて実証済み）。

## CLAUDE.md / AGENTS.md の統一（`agent/AGENTS.md`）

ユーザー指示「CLAUDE.md AGENTS.mdをclaude, codex, antigravity, piで汎用的に使える物に統一、さらに
DeepResearchによって2026/09/03時点最新の記入すべき内容や記法を調査して構成」を受けて実施。
上記「共通化しないもの」節の旧判断（AGENTS.md/CLAUDE.mdは意図的に非共通）を覆した。

**リサーチ結果（2026-09-03、一次情報で裏取り済み）**:

- **AGENTS.md は Linux Foundation が管理するオープン標準**へ成長し、OpenAI Codex・Google Jules/
  Gemini CLI・Cursor・Aider・Devin・Windsurf・Amp・Zed・Warp・GitHub Copilot 等 25 以上のツールが
  対応（[agents.md](https://agents.md) 公式サイト実査）。プレーンMarkdown、必須フィールド無し。
- **Claude Code は2026-09-03時点でも`AGENTS.md`をネイティブには読まない**（`CLAUDE.md`のみ）。
  Anthropic公式ドキュメント（[code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory)、
  直接fetch確認済み）が明示する公式移行パターンが今回採用した設計そのもの: 「リポジトリが既に
  AGENTS.mdを使っているなら、それをインポートするCLAUDE.mdを作り両方のツールが重複無く同じ指示を
  読めるようにする」。`@path`インポート構文: 相対パスはインポート元ファイル基準で解決・絶対パス/`~/`可・
  再帰インポート最大4hop・コードスパン/フェンス内はスキップ。CLAUDE.mdは200行未満推奨（旧316行は超過、
  今回8行まで削減）。
- **Pi Coding Agent**: `~/.pi/agent/AGENTS.md`(グローバル)+ カレント/親ディレクトリの`AGENTS.md`を
  ロード。`@`インポート構文は無い（pi.dev公式クイックスタート実査で確認）。
- **Antigravity (agy)**: `~/.agy/AGENTS.md`・`~/.gemini/AGENTS.md`をグローバルスコープとして読む
  （既存`agy/settings.json`の`context.fileName`と整合）。`@`インポート相当の機構は無い（複数の一次/
  二次情報で確認）。
- **OpenAI Codex CLI**: グローバル`AGENTS.md`は`~/.codex/AGENTS.md`に置ける。このマシンには`codex`
  バイナリはあるが`~/.codex/`自体が未作成（未設定）だったため、今回`agent/AGENTS.md`への直接symlinkの
  配線のみ新設した（codex固有の追加コンテンツはまだ無いため補完ファイルは作らない、後述）。

**設計**: `claude`のみ`@`インポートで動的合成できるが、`pi`/`agy`にはインポート機構が無いため、
同じ「生成」パターンを踏襲した(旧`agent/scripts/gen-pi-agents.sh`が`agent/agents/*.md` →
`pi/agents/*.md`変換で使っていたのと同型のパターン、同スクリプト自体は2026-09-03廃止済み)。

| ファイル                                                                          | 種別             | 内容                                                                                                                                                                                                                                       |
| --------------------------------------------------------------------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `agent/AGENTS.md`                                                                 | 正典・汎用コア   | Identity & Context・Response Style・Development Environment・Required External Tools・Code Style Preferences・Vald Law要旨・Multi-Agent原則・セキュリティ方針(ポリシー記述のみ)。AGENTS.md仕様準拠、約110行                                |
| `agent/AGENTS-claude-supplement.md`                                               | claude固有補完   | Hooks Active・MCP Servers・Custom Subagents全表・Skills・Plugins・Memory System・Security詳細・statusLine                                                                                                                                  |
| `agent/AGENTS-pi-supplement.md`                                                   | pi固有補完       | External Coding Agent Bridges・Specialized Subagents全表(pi model文字列)・Teamwork-Preview Bridge・Skills & Prompts表                                                                                                                      |
| `agent/AGENTS-agy-supplement.md`                                                  | agy固有補完      | Identity note・Multi-Agent & CLI Orchestration Bridges・Specialized Subagents全表(agy role表記)・Teamwork-Preview Bridge・Agent Skills一覧                                                                                                 |
| `agent/scripts/gen-tool-agents.sh`                                                | 生成本体         | `agent/AGENTS.md` + `agent/AGENTS-<tool>-supplement.md` を連結。`[pi\|agy\|all] [--check]`引数                                                                                                                                             |
| `agent/scripts/gen-agents-md-for-pi.sh`・`agent/scripts/gen-agents-md-for-agy.sh` | 生成ラッパー     | sync-manifest.jsonのgenerateモード呼び出し契約(`$script --check`を追加引数無しで呼ぶ、1 target = 1 script)に合わせた薄いラッパー                                                                                                           |
| `claude/CLAUDE.md`                                                                | claude用エントリ | `@AGENTS.md` + `@AGENTS-supplement.md`の2行インポート + `## Claude Code`節(極小、`/doctor`リマインド等)。8行                                                                                                                               |
| `pi/AGENTS.md`・`agy/AGENTS.md`                                                   | 生成物           | 冒頭に生成物である旨のnoteブロック(blockquote、HTML commentではない — Claude Codeはブロックレベル HTMLコメントを注入前に除去するが、pi/agyでの同等の除去は未確認のため、除去されなくても違和感なく読めるプレーンテキストにした) + 連結内容 |
| `~/.codex/AGENTS.md`                                                              | 新規配線         | `agent/AGENTS.md`への直接symlink(補完無し)                                                                                                                                                                                                 |

`SYSTEM.md`(pi/agy)は対象外のまま(今回の指示は明示的に「CLAUDE.md AGENTS.md」のみ、SYSTEM.mdは
システムプロンプト置換/追記という別レイヤーの機構でありスコープ外 — 上記「共通化しないもの」節参照)。

**配線**: `Makefile.d/install.mk`のDOTFILES_MAPに`agent/AGENTS.md .claude/AGENTS.md`・
`agent/AGENTS-claude-supplement.md .claude/AGENTS-supplement.md`・`agent/AGENTS.md .codex/AGENTS.md`
を追加。`claude/docker/install`にも同2ファイルの`install`行を追加(Docker build layer経由でも
`@`インポートが解決できるように)。`codex/install`ターゲットを新設(`dotfiles/install`依存のみ、
AGENTS.mdのみの最小ターゲット)。`arch/install`・`mac/install`の依存リストに`codex/install`を追加。
`nix/modules/home/dotfiles/agent-tools.nix`に対応する`home.file`エントリを追加。
`agent/sync-manifest.json`に`AGENTS.md`(claude/codex: live-symlink、pi/agy/gemini: generate)・
`AGENTS-supplement.md`(claudeのみ)エントリを新設し検証を`sync-verify.sh`へ組み込んだ。

**検証**: `make claude/install pi/install agy/install codex/install`を実際に実行し、
`~/.claude/AGENTS.md`・`~/.claude/AGENTS-supplement.md`・`~/.codex/AGENTS.md`・
`~/.pi/agent/AGENTS.md`・`~/.agy/AGENTS.md`・`~/.gemini/AGENTS.md`が全て期待通り`agent/AGENTS.md`
(またはpi/agy分は生成物経由で)を指すことを`readlink -f`で確認済み。`agent/scripts/sync-verify.sh`
全entry PASS。`nixfmt --check`/`statix check`/`deadnix`はクリーン(`nix build --dry-run`はこのマシンの
sandbox制約(`NIX_REMOTE=local?root=...`ワークアラウンド使用)で試みたが、`agent-tools.nix`とは無関係の
既存`nix/modules/nixos/network/resolved.nix`のnixpkgs非互換エラーで完走せず — 本統合の変更範囲外)。

**副次的な発見**: `agent/scripts/test-security-rules.sh`の`git_reset_hard_protected_branch`関連
テストケースは、リポジトリのcwdが実際に`main`/`master`ブランチ上にあることに依存する(ルール自体が
cd/-C対象の指定が無い場合はhookプロセスのcwdブランチを判定するため、意図した仕様どおり)。feature
ブランチ上でこのテストを実行すると該当ケースがFAILする — バグではなくテストの環境結合、`main`へ
マージ後に再実行すればPASSする。

## SYSTEM.md の統一（`agent/SYSTEM.md`）

ユーザー指示「SYSTEM.mdについてもagentディレクトリで管理して下さい」を受けて、直前の「CLAUDE.md /
AGENTS.md の統一」と同じ設計思想をSYSTEM.mdへ適用した。

**AGENTS.mdとの違い**: AGENTS.mdは節単位で内容が実質同一だった（Identity & Context・Response Style
等がまるごと重複）のに対し、SYSTEM.mdはツール固有の自己同一化宣言（「あなたはPiである」/
「あなたはAntigravityである」）と各Directive内の具体的なツール呼び出し名（`read`/`write`/`edit`
vs `view_file`/`write_to_file`/`replace_file_content`）が本文中に混在しており、節単位の機械的分離が
できない。実際に重複していたのは「Teamwork-Preview Subagent Bridge」（archetype一覧、pi版は名前の
みの簡略版・agy版は説明付きのフル版で内容は同一）・「Security & Invariant Enforcement」・
「Verifier Independence & Deterministic Tool Supremacy」の3項目のみで、これらを`agent/SYSTEM.md`
（汎用コア、独立した`## Shared Directives`節として）へ切り出した。ツール固有のアイデンティティ宣言と
冒頭のBehavioral/Operational Directivesは`agent/SYSTEM-pi-supplement.md`・
`agent/SYSTEM-agy-supplement.md`に残した。

**連結順がAGENTS.mdと逆**: `agent/scripts/gen-tool-agents.sh`は「汎用コアが先、補完が後」だが、
`agent/scripts/gen-tool-system.sh`は「補完が先、汎用コアが後」。システムプロンプトは「あなたは
<ツール名>である」という自己同一化の宣言が常に文書の先頭に来る必要があり、ツール名を持たない汎用
コアを先頭には置けないため。生成物（`pi/SYSTEM.md`・`agy/SYSTEM.md`）の呼び出し契約は
`agent/scripts/gen-system-md-for-pi.sh`・`agent/scripts/gen-system-md-for-agy.sh`という薄い
ラッパー経由（AGENTS.mdエントリと同じ、sync-verify.shの「1 target = 1 script」契約への対応）。

**claude/codexは対象外**: Claude Codeのsystem promptはユーザーが永続ファイルで上書きする仕組みを
持たず、`--append-system-prompt`という都度指定のCLIフラグのみが存在する
（[code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory)実査で確認: 「CLAUDE.md
content is delivered as a user message after the system prompt, not as part of the system prompt
itself」）。codexにも同種のファイルはこのリポジトリで確認できる範囲では無い。よってpi/agyのみが
対象で、Makefile.d/install.mk・nix/modules/home/dotfiles/agent-tools.nixの配線先パス自体は変更不要
（pi/SYSTEM.md・agy/SYSTEM.mdという既存の配線先へ生成物を書き込むだけで、AGENTS.mdの時と違い新規の
symlink先を追加する必要が無かった）。

**副産物**: 生成の過程でpi/SYSTEM.mdのTeamwork-Preview Subagent Bridge節が旧来はarchetype名のみの
簡略版だったのに対し、agy/SYSTEM.md相当のフル説明付き版へ統一された（情報量が増える方向の変更、
リグレッションではない）。

`agent/scripts/test-security-rules.sh`等の既存テストスイート・3つの`validate-harness.sh`は
SYSTEM.mdの中身を検証対象にしていないため、本変更による直接の回帰は無い
（`agent/scripts/sync-verify.sh`の新entryのみが検証対象）。

## SKILL.stats.jsonの値レベル統合（`agent/skills/<name>/SKILL.stats.json`）

以前は「エコシステムごとに異なる実行時テレメトリ、集約すると利用履歴が失われるため意図的に対象外」と
していた判断をユーザー指示により覆した。実際の中身を調べたところ、`scripts/skill-stats.sh`は元々
1回の記録呼び出しでclaude/pi/agy 3ファイルへ同時書き込みする設計(常に同期する設計意図)だったが、
静的スキル内容の再編成(claude/skills・pi/skills配下に一部スキルのディレクトリしか無かった時期が
あった)の影響で、実際には呼び出しごとに書き込み先の一部だけが存在し、3ファイルの値が部分的に乖離
していたことが判明した(例: golang-testingはclaude=3回・pi=不明・agy=20回)。

`scripts/merge-skill-stats.py`(新設、一回限りの移行スクリプト)で、execution_count等のmetricsは合算・
lifecycleのcreated_at/first_executedは最古・last_executedは最新・failure_signaturesはcategory単位で
集約・prompt_revision_historyはtimestamp重複除去の上マージし、`agent/skills/<name>/SKILL.stats.json`
(単一正典)へ統合した。`scripts/skill-stats.sh`(`record-end`・`register-revision`・`aggregate`)も
この単一正典のみを読み書きするよう書き換えた。`agent/skills`は既にディレクトリ丸ごと
claude/pi/agy/geminiへlive-symlinkされているため、新たな配線は不要(既存symlinkがそのまま機能する)。

claude/skills・pi/skills・agy/skills配下の個別SKILL.stats.jsonは削除済み(git履歴には残る)。
`self-improve-registry.tsv`・`harness-registry.tsv`はこの指示の対象外(明示的に「stats.json」のみが
指示されたため)として当時は引き続きエコシステムごとに分離したまま維持していた
**（2026-09-04、この判断は覆り単一正典化済み。詳細は「registry.tsvの単一正典化」節参照）**。

**副次効果として残る既知の限界**: `agent/skills`はdocker/copy-installターゲット(`cp -R`でコンテナ
イメージへコピー)の対象でもあるため、SKILL.stats.jsonが今後この経路に含まれるようになった
(以前は各エコシステムのskills/配下にあり対象外だった)。新規コンテナがホストの利用統計を継承する
方向の変化であり、上記「共通化しないもの」節が元々述べていた「新規コンテナがホストの利用統計を
継承しないのは望ましい挙動」という設計原則とは逆行するが、今回のユーザー指示(値ごと一本化)を
優先した結果として記録する。

## registry.tsvの単一正典化（`self-improve-registry.tsv`・`harness-registry.tsv`、2026-09-04）

上記のSKILL.stats.json統合ミッション当時は、`self-improve-registry.tsv`（`swarm-loop`の自己改善
ミッション重複検知に使う）・`harness-registry.tsv`（`swarm-meta`のharness推薦の実績フィードバックに
使う）を明示的に対象外とし、claude/pi/agy各`skills/`配下に別々の実ファイルとして維持していた
（「集約すると他エコシステムの利用履歴を上書き・消失させる」という理由）。ユーザー指示により、
この判断を覆しagent/配下への単一正典化へ変更した。

**なぜSKILL.stats.jsonと違ってこの2ファイルは単一正典化できるのか**: SKILL.stats.jsonは
「skillごとの実行回数」のような**スカラー値をエコシステム間でどう集約するか**という問題を持つ
（claude=3回・agy=20回を1つの値に潰すと元の内訳が失われる）。一方`self-improve-registry.tsv`・
`harness-registry.tsv`はいずれも**`mission-slug`で一意な行の集合**（TSV、1ミッション=1行）であり、
複数ソースの内容は「行の和集合」として矛盾なく合成できる（同一ミッションが複数エコシステムで
別々に記録される、という状況が構造的に発生しない——1回のミッションは1回だけGATEを通過し1回だけ
登録される）。実際、統合時点でclaude/pi/agy 3ファイルの内容を比較したところ、pi/agyは常に
byte-identicalで、claudeがそれよりわずかに新しい（直近数件多い）というだけの**単純な部分集合
関係**であり、要素の対立(同一sludgに異なる内容)は皆無だった。

**実施内容**:

- `claude/skills/swarm-loop/self-improve-registry.tsv`（最新版、31行）→
  `agent/skills/swarm-loop/self-improve-registry.tsv`（新設）としてそのまま採用（pi/agy版は
  この厳密な部分集合だったため追加マージ不要）。
- `claude/skills/swarm-meta/harness-registry.tsv`（47行）+ `agent/skills/swarm-meta/
harness-registry.tsv`（5行、後述の理由で既に単一正典化が部分的に先行していた）を
  mission-slugの重複が無いことを確認した上で単純結合し52行（51データ行）へ統合。
- claude/pi/agy側の実ファイル9件（各2ファイル×3エコシステム、ただし`.lock`は元々一部
  gitignore対象outだったため実際の`git rm`対象は9件）を削除、空になった
  `claude/skills/swarm-loop/`・`claude/skills/swarm-meta/`ディレクトリも削除。
- `self-improve-check.sh`・`self-improve-register.sh`（`swarm-loop`）・`harness-select.sh`・
  `harness-record.sh`（`swarm-meta`）の4スクリプトが行っていたregistry.tsvパス解決を変更した:
  旧来は`cd "$(dirname "$0")/.." && pwd`（**`-P`無し**、bashのlogical cdはsymlink祖先を辿らず
  文字列としてpop するため、`~/.claude/skills/...`等のデプロイ済みsymlink経由で呼ばれた場合に
  `~/.claude/skills/swarm-loop`という論理パスがそのまま`pwd`の出力になる——ただし最終的な
  ファイルI/Oでは`~/.claude/skills`自体がsymlinkであるため物理的には`agent/skills/swarm-loop`
  と同一ファイルを指す。ここが2026-09-03CRITICAL回帰〈本ファイル別節参照〉と対照的な点:
  bashのlogical cdは「祖先ディレクトリのsymlinkは保持したまま`..`をポップする」ため、ファイル
  自体がsymlinkだった今回のケースとは異なり、実は元から`agent/skills/...`と同じ実体を指して
  いた）を、`readlink -f "$0"`でファイル自身を先に物理解決してから`dirname`する方式へ変更した。
  実質的な挙動は変わらない（元々`~/.claude/skills`経由なら同じ実体を指していた）が、
  (a) 挙動が呼び出しパスの`~/.claude/skills`シンボリックリンクの存在に暗黙依存しない
  明示的な設計になった、(b) `agent/skills/...`という**repo相対パス**で直接呼び出した場合
  （worktree内での直接実行等）にも同じ実体を指すことが保証される、という2点で堅牢化した。
  なお`harness-record.sh`/`harness-select.sh`の旧コメントは「pi-agent-consolidation-phase2
  ミッション直後に発生した実バグ」の回避策として`-P`無し方式を**意図的に**採用した経緯を
  説明していたが、これは「per-ecosystem分離を維持する」という当時の設計目標のための対処であり、
  今回はその設計目標自体を変更した（単一正典化）ため、対処法も逆転させた。歴史的record として
  旧コメントは削除せず残し、変更の経緯を追記する形にした。
- `.gitignore`の`.lock`除外パターンを`claude/skills/swarm-{loop,meta}/...`（旧・一部のみ対象）から
  `agent/skills/swarm-{loop,meta}/...`（新・単一正典パスのみ）へ更新。

**検証**: 統合後のファイルを`harness-status.sh`・`self-improve-check.sh`へ実際に通し、全51/31行が
正しくパース・検索可能なことを確認（`harness-select.sh`の`registry_matches`が正しい過去実績を
返すこと、`self-improve-check.sh`が既知の重複ターゲット集合に対し正しく`OVERLAP`判定を返すことを
実行して確認済み）。`~/.claude/skills/...`経由・`agent/skills/...`repo相対パス経由の両方の呼び出し
方法で同一の結果になることも実行して確認した。`harness-record.sh`の書き込みパスも実際にテスト
エントリを追記→内容確認→削除する形で検証済み。

## hooksスクリプト本体の単一実装への統合（`agent/scripts/hooks/`、Phase 1〜4完了）

ユーザー指示「各hookについても全て統合」を受け、上記「hooks/ のルールデータ共有化」で既に共有していた
判定**データ**(`agent/security-rules.json`等)に対し、判定**アルゴリズム**自体(bash・bash+埋め込み
Python・TypeScriptで3回独立に再実装されていたall_of/any_of/not_any_of評価・force_push/
git_reset_hardの特別扱い等)を単一のPython実装へ統合する作業。3ファミリー(security-gate・
graphify-hint・vald-law)に分け、フェーズごとに個別コミット・全既存テストPASSを確認してから
次フェーズへ進む方針(枯れたセキュリティコードを触るリグレッションリスクが高いため)。

**Phase 1(security-gateファミリー)完了**:

- `agent/scripts/hooks/rule_engine.py`(新設): 判定アルゴリズムの正典実装。
  `matches_all_of`/`matches_any_of`/`matches_not_any_of`・`eval_force_push`・
  `resolve_command_target_dir`(cd/-Cターゲット抽出、`absolutize`引数でclaude方式/pi・agy方式の
  意図的な差異を保持)・`eval_git_reset_hard`・`eval_shell_command_rules`・
  `eval_sensitive_write_path`(5候補: raw/expanded/resolved/normalized/canonical、最も広いpi方式を
  正典化)・`eval_vald_law1/2/345`・`eval_graphify_hint`(Phase 1時点では未接続、Phase 2/3で接続完了)。
- `agent/scripts/hooks/decide.py`(新設): 上記をCLIとして呼び出すエントリポイント。stdinで
  正規化JSON(`family`で分岐)を受け、stdoutへ`{"decision":"allow"|"ask"|"block","reason":...}`を
  返す。`security_shell` familyは`all_matches`(JSON宣言順の全一致、tier/description**込み**)も
  返す — piの「宣言順に走査しconfirm毎に承認後継続」というUXを、呼び出し側が別途ローカルキャッシュを
  持たずに再現できるようにするため(下記security-audit指摘参照)。
- 変更(いずれも上記2ファイルへ判定ロジックを委譲する薄いシムへ書き換え、I/Oプロトコル変換のみ残す):
  `claude/hooks/security-gate.sh`・`claude/hooks/write-security-gate.sh`・
  `agy/hooks/security-gate.sh`・`pi/extensions/security-gate.ts`(shell_command_rules/
  sensitive_write_path_rules部分のみ、Vald Law部分は当時未変更のまま残した — Phase 3で接続完了)。

**検証**: 新設Pythonファイルに対し独立した55件の直接テスト(security_shell 25件・security_write
8件・vald_law1/2/345 19件・graphify_hint 3件、ツールごとの意図的な差異—`resolve_command_target`・
`scope_mode`—を全パターン網羅)を実施し、既存の期待挙動と完全一致を確認してからシムの書き換えに
着手した。書き換え後は既存`agent/scripts/test-security-rules.sh`(claude 25件・write 8件・agy 12件・
pi 11件、計56件)が新規ケース追加なしで全PASSすることを確認(振る舞い変更ゼロの回帰テストとして
既存スイートをそのまま使う設計)。`test-vald-law-rules.sh`・`test-graphify-hint.sh`(pi/extensions/
security-gate.tsの周辺コード変更がVald Law部分に影響していないか)・3つの`validate-harness.sh`も
再実行しクリーンであることを確認。

**security-auditレビューで発見・修正した指摘**:

- **High**: `pi/extensions/security-gate.ts`がモジュールロード時に1回だけ読み込む`RULES`キャッシュへ
  `all_matches`のidで逆引きしていたため、`decide.py`がフレッシュに読んだルールファイルとこの
  プロセス寿命中のキャッシュがズレた場合(ルールid変更・追加等)、該当マッチが確認ダイアログも
  block出力もされずサイレントに握り潰される穴があった。`decide.py`側が`all_matches`に
  tier/descriptionを直接埋め込み、pi側のローカルキャッシュ逆引きそのものを削除して修正(呼び出し側が
  別途キャッシュを持たない設計へ変更、根本的にこの種の陳腐化バグが起こり得ない構造にした)。
- **Medium**: `claude/hooks/security-gate.sh`・`write-security-gate.sh`の`decide.py`呼び出しに
  timeoutが無く、agy(`subprocess.run(...,timeout=10)`)・pi(`execFileSync(...,{timeout:10000}）`)と
  非対称だった。`timeout 10 python3 "$DECIDE"`(`timeout`コマンド不在時はフォールバック)を追加し統一。

**Phase 2(graphify-hintファミリー)完了**:

- `decide.py`の`graphify_hint`ハンドラ(Phase 1で実装済みの`eval_graphify_hint`を接続)を経由するよう、
  `claude/hooks/graphify-hint.sh`・`agy/hooks/graphify-hint.sh`・`pi/extensions/graphify-hint.ts`の
  3ファイルを薄いシムへ書き換え。`search_bases`(グラフパス候補の探索基準ディレクトリ一覧)は
  claude/pi=`[cwd]`単一・agy=`workspacePaths`(無ければ`[os.getcwd()]`)という既存の意図的な差異を
  そのままリクエストパラメータとして保持。
- **検証**: 既存`agent/scripts/test-graphify-hint.sh`(claude/agy/pi各3件、計9件)が新規ケース追加なしで
  全PASS。

**Phase 3(vald-lawファミリー)完了**:

- `decide.py`の`vald_law1`/`vald_law2`/`vald_law345`ハンドラ(Phase 1で実装済み)を経由するよう、
  `claude/hooks/vald-law-gate.sh`(Law1)・`claude/hooks/vald-law2-gate.sh`(Law2)・
  `claude/hooks/vald-law345-check.sh`(Law3/4/5)・`agy/hooks/vald-law-gate.sh`(3法まとめて1ファイル)・
  `pi/extensions/security-gate.ts`のVald Law部分(shell/write部分はPhase 1で既に統合済み、今回は
  無変更)を薄いシムへ書き換え。`scope_mode`(スコープ判定方式)はclaude=`"none"`(project-scoped配線に
  依存し無条件評価)・agy=`"workspace_and_cwd_and_command_string"`・pi=`"cwd_and_resolved_path"`の
  既存の意図的な差異をそのまま保持。
- **この統合で自然に解消した既存バグ**: `agy/hooks/vald-law-gate.sh`旧実装の
  `f"Vald Law 1 violation: {law1_msg}"`は`law1_msg`自体が既に同じ接頭辞で始まっており出力が二重に
  なっていた(claude/piの旧実装は元々`law1_message`をそのまま使っており二重化していなかった)。
  3ツールとも`decide.py`が返す`reason`(=`law1_message`そのもの)をそのまま使う設計へ統一したことで
  再発しない構造になった。
- **意図的に受け入れた表示形式の差異解消**: Law3/4/5の違反メッセージは旧agy/pi実装が「行番号+該当行の
  引用+先頭5件までの切り詰め」形式、旧claude実装が「ルール単位のメッセージ一覧、無制限」形式という
  異なる書式だった。共有エンジン(`eval_vald_law345`)はルール単位のメッセージ一覧のみを返すため、
  agy/piは行番号・該当行引用を失う(判定=decisionそのものは変化しない、表示文言のみの変更)。
  5件切り詰めはagy/pi双方のシム側で維持した(claudeは元々無制限のためそのまま無制限)。
- **あわせて修正した既存の配線ギャップ**: `agy/hooks/hooks.json`の`security-gate`/`vald-law-enforcer`の
  `matcher`に`edit_file`が含まれておらず、スクリプト側のtool_name whitelistには`edit_file`が
  含まれるのに実際には起動しない既存の穴があった。両matcherへ`edit_file`を追加。
- **security-auditレビューで発見・修正した指摘(Medium)**: `vald_command_targets`の
  `scope_mode="workspace_and_cwd_and_command_string"`(agy専用)は元々cd/-Cターゲットのディレクトリ
  解決を行わず、cwd・workspaces・コマンド文字列そのものへの直接一致のみで判定していたため、
  `cd ../vald && go build ./...`のような相対パスcdでコマンド文字列自体に`vdaas/vald`が literal に
  出現しないケースが丸ごとすり抜けていた(`scope_mode="cwd_and_resolved_path"`(pi方式)との非対称な
  弱点)。`resolve_command_target_dir`によるcd/-C解決をこのscope_modeにも追加し(既存の一致経路を
  狭めない検出範囲の拡張のみ、他scope_modeの挙動には影響しない)、`test-vald-law-rules.sh`に
  再発防止の回帰テストを追加。
- **検証**: 既存`agent/scripts/test-vald-law-rules.sh`(claude Law1 2件・Law2 4件・Law345 4件・agy 9件
  [上記Medium修正の回帰テスト1件を追加]・pi 6件、計25件)・`agent/scripts/test-security-rules.sh`
  (pi/extensions/security-gate.tsのVald Law部分書き換えがshell/write部分の既存ロジックへ影響して
  いないかの回帰確認)が全PASS。3つの`validate-harness.sh`も再実行しクリーンであることを確認。
  なお`test-security-rules.sh`の「git reset --hard on main cwd」系4件は、本diff適用前のベース
  コミット(`66c3be0f`)でも同一条件(実行時のカレントブランチがmain/master以外)でFAILすることを
  `git stash`で確認済み — 実行時のカレントブランチに依存する既存のテスト設計上の弱さであり、
  本統合による新規リグレッションではない。

**Phase 4(SessionStartメモリコンテキスト合成)完了**（2026-09-03、AI関連dotfiles横断調査で発見・実施）:

- `agent/scripts/hooks/memory_context.py`(新設): `claude/hooks/session-start.sh`・
  `agy/hooks/session-start.sh`が独立に再実装していた「MEMORY.md索引 + トピック別`*.md`ファイル +
  ローカルoverrideファイル」の合成ロジックの正典実装。`memory_dirs`(走査するディレクトリの順序
  リスト、同名ファイルは先勝ちでdedup)・`local_files`(cwd直下で確認するローカルoverride候補)・
  `index_head`/`topic_head`/`local_head`(各セクションの先頭何行まで読むか)・`multi_dir_labels`
  (複数dir区別のためのヘッダ付与要否)・`local_all_matches`(ローカルoverrideを最初の1件だけ使うか
  全件使うか)で claude方式(dir1つ・ヘッダなし・ローカル全文・最初の1件のみ)と agy方式(dir2つ
  `~/.gemini/memory`→`~/.claude/memory`の順・ヘッダあり・ローカル150行まで・両方使う)の既存の
  意図的な差異を保持する。`decide.py`に`memory_context` family(判定ではなくデータ合成のため
  decision/reasonを持たず`{"context","file_count","byte_count","matched_local"}`を返す専用shape)
  として接続。
  - **ソート順の locale 依存性(実装時に発見・修正)**: 旧bash実装(claude/agyとも
    `find ... -print0 | sort -z`)はホストのlocale照合順序(大文字小文字を区別しない辞書順、
    `-`/`_`等の記号を軽く扱う)でソートしていたが、Python純正の`sorted()`はUnicode符号点順になり、
    実データ(`~/.claude/memory`の124ファイル)に対しこの2つが異なる順序を返すことを実測で確認した。
    手元でlocale照合ルールを再実装するのではなく、実際に`sort`コマンドをsubprocessで呼びホストの
    localeへ委譲する設計(`_locale_sort`)にして解決した(`sort`が使えない環境のみ`str.lower`近似へ
    fallback)。
- `claude/hooks/session-start.sh`・`agy/hooks/session-start.sh`: 判定ロジックを上記へ委譲する薄い
  シムへ書き換え(セッションログ書き込み・hookSpecificOutput/JSON整形のみ残す)。
- `pi/extensions/auto-memory.ts`: pi は元々`~/.claude/memory`(claude/agyが共有するトピック別知識
  ベース)へのアクセスを一切持たなかった(claudeは自身のみ・agyは`~/.gemini/memory`と両方読むのに
  piだけこの非対称があった)。pi固有の`~/.pi/agent/memory/`(global-memory.md・プロジェクト単位
  memory・`/memory`コマンド用、ユーザーが直接編集する別用途)は置き換えず、これに**追加する形**で
  `~/.claude/memory`のcontextを`decide.py`経由で注入するようにした(`local_files`は空— pi は
  AGENTS.md読み込みで既にローカル文脈を持つため、ここでの二重注入は避ける)。
  - **注意(トークンコスト)**: `~/.claude/memory`は現時点で約124ファイル・約37万文字あり、
    claude/agyは元々毎セッション開始時にこれを全文注入している(既存の受け入れ済みコスト)。
    piも同じ設計を踏襲するため、pi側は新たに毎セッションこの規模のコンテキストを追加で消費する
    ことになる点は明示しておく(既存踏襲であり新規の設計判断ではないが、pi利用者にとっては
    セッション開始コストの増加として体感されうる)。
- **既存出力との差異(意図的に許容、内容の欠落・重複ではない)**: 旧bash実装は各セクションを
  常に前後`\n`付きで連結していたため先頭・末尾に空行が入っていたが、新エンジンは`\n\n`区切りの
  joinのみで先頭・末尾の余分な空行を持たない。`git stash`でPhase4適用前の実装と実HOME
  (`~/.claude/memory`124ファイル・約37万文字)に対する出力を比較し、この先頭/末尾の空行1行分
  以外は完全に一致することを確認済み(claude側は偶然この境界条件が相殺し完全に byte-for-byte 一致)。
- `agent/scripts/test-memory-context.sh`(新設、14ケース): `decide.py`直接呼び出しでのdedup・
  ヘッダ有無・ローカルoverride選択方式の違いを検証し、claude/agy双方の実hookファイル経由でも
  動作することを確認。3つの`validate-harness.sh`へ共有テスト委譲を配線。

## Post-Write lintフックの対象拡張子superset化（`agent/hooks/claude/post-write.sh`(2026-09-04実体移動、

発見当時は`claude/hooks/post-write.sh`) / `agy/hooks/post-edit-lint.sh`）

2026-09-03のAI関連dotfiles横断調査で発見: `agent/hooks/claude/post-write.sh`(json/yaml/toml/sh/Makefile を
読み取り専用でチェック+書き込み監査ログを残す)と`agy/hooks/post-edit-lint.sh`(go[gofmtで**書き換え**]/
python/json/shのみチェック、ログなし)が対象拡張子・副作用(書き換えの有無)・ログの有無いずれも
食い違っていた。pi にはこの種のPostToolUse lintフック自体が存在しない。

判定アルゴリズムそのものが2回独立実装されて発散した(security-gate等と同種)のではなく、**各ツールが
チェックする拡張子の集合が単純に異なっていた**ケースのため、共有エンジンへの統合ではなく
「broadest-safest-superset」方針(既存の`agent/security-rules.json`統合等で採用した規約と同じ)で
各側に不足していたチェックを追加する形で解消した:

- `agent/hooks/claude/post-write.sh`: go(`gofmt -l`によるパースエラー検出、読み取り専用でclaude既存の
  「書き換えない」方針を維持)・python(`py_compile`)を追加。
- `agy/hooks/post-edit-lint.sh`: yaml(`yaml.safe_load`、PyYAML未導入なら黙ってskip)・
  toml(`tomllib`)を追加。既存の「サイレント(検出結果を一切出力しない)」方針は変更せず維持。
- go の書き換え可否(claude=読み取り専用でwarnのみ／agy=`gofmt -w`で自動整形)・ログの有無
  (claude=あり／agy=なし)は既存の意図的な差異として維持し、統一しなかった。
- **実装時に発見・修正したバグ**: claude側の追加実装で`ERR=$(gofmt -l "$FILE_PATH" 2>&1 >/dev/null)`
  のような代入形式は、`set -e`下でコマンドが失敗すると代入の時点でスクリプトが即座に中断し、
  後続のWARNING出力に到達しない(exit codeがそのまま伝播する)。`|| true`を代入に付与して修正し、
  この回帰を検知する専用テスト(`claude/validate-harness.sh`の「exits 0, does not abort」系)を追加。
- **security-auditレビューで発見・修正した指摘(HIGH)**: 当初 Makefile/`.mk` の構文チェックとして
  `make -n -f`(dry-run)を両ツールに実装していたが、GNU Makeは`$(shell ...)`/`!=`を**レシピ実行
  ではなくパース(変数展開)時に評価する**ため、`-n`フラグは実行を抑制しない。実機PoCで
  `X := $(shell touch PWNED_MARKER)`を含むMakefileに対し`make -n -f`を実行するだけで
  実際にファイルが作成されることを確認した — つまり「read-onlyな構文チェック」のつもりの
  hookが、書き込まれたMakefile内容次第で確認なしの任意コマンド実行プリミティブになっていた
  (`agent/hooks/claude/post-write.sh`側は本diff以前から存在した`.mk`/Makefileチェックが同じ穴を
  持っていたため同時に削除、`agy/hooks/post-edit-lint.sh`側は本Phase 4で新規に追加しようと
  していたものを実装せず終えた)。GNU Make自体に「`$(shell ...)`を評価しない安全なdry-run
  モード」は存在しないため、Makefile構文チェックは両ツールとも**実装しない**方針にした
  (claude/agy双方の`validate-harness.sh`に、`$(shell touch <marker>)`入りMakefileを渡しても
  マーカーが作成されないことを確認する再発防止テストを追加)。あわせてLow指摘として、
  `gofmt`/`py_compile`/`bash -n`へのファイルパス引数の前に`--`を挿入し、`-`始まりのファイル名が
  誤ってフラグとして解釈される余地を塞いだ。
- 検証: 手動fixture(有効/無効なgo・python・yaml・toml)での動作確認、`make -n`のPoC再現、
  および3つの`validate-harness.sh`(claude +3件・agy +3件の新規テストケース)が全PASS。

## pi/agentsの実行時変換について(2026-09-03: 不採用判断を覆し採用済み)

旧記述(2026-09-02頃)は「pi/agentsについても実行時変換で対応してほしい」という指示に対し、
`pi-subagents`拡張(サードパーティOSS、`tintinweb/pi-subagents`)のソースコードとpi.dev公式
Extension APIドキュメントを一次情報として実査した結果、**技術的に不可能(著しく困難)** と判断し
不採用としていた(固定3ディレクトリ読み込み・単純comma-split の`tools:`パース・登録APIの不在等)。

**この判断は誤りだった**: agent-hooks-and-pi-agents-unificationミッション(2026-09-03)のEXPLORE段階で
再検証したところ、上記の技術的制約は実際にこのリポジトリで動いているコードとは**別物**
(サードパーティ`tintinweb/pi-subagents`)を対象にした調査結果だったと判明した。このリポジトリで
実際に動作しているsubagent実装は本リポジトリ自身のfirst-partyコード`pi/extensions/subagents.ts`
であり、自由に編集可能。同ファイルの`discoverAgents()`は`~/.pi/agent/agents`と`<cwd>/.pi/agents`の
2ディレクトリを読む設計で、`tools:`変換(PascalCase→pi-coding-agentのlowercase語彙、Glob→[find,ls]の
2トークン展開)を`subagents.ts`の`loadAgentsFromDir()`/`mapToolNames()`(新設)へ実行時変換として
移植することで、`~/.pi/agent/agents`のsymlink先を`pi/agents`から`agent/agents`へ直接変更する
「Option A(完全統合)」が成立した。旧`agent/scripts/gen-pi-agents.sh`(ビルド時生成方式)・
`pi/agents/*.md`(25件の生成物)は廃止済み。pi-coding-agent 0.84.4本体のtool語彙自体(小文字限定・
`Set.has()`完全一致、Globという概念が無い)という制約は今も本物だが、これは「どこで変換するか」の
問題であり、`subagents.ts`内での実行時変換で吸収できる。

## AI関連dotfiles横断調査 Round 2（2026-09-03、pi extensions共有化・swarm hooks共有lib化）

Phase 1〜4完了後、「まだ統合できる余地がないか」の再調査で見つかった4件の追加改善。

**1. `agy/hooks/hooks.json`のハードコードパス修正**: 全6コマンドが
`"bash /home/kpango/.gemini/hooks/xxx.sh"`という絶対パス+ユーザー名ハードコードだった
(claude/settings.jsonの`~/.claude/hooks/xxx.sh`というチルダ表記と非対称)。`$HOME`変数へ置換
(`"bash $HOME/.gemini/hooks/xxx.sh"`)。Gemini CLI公式ドキュメントで`"command"`が「シェルコマンドを
実行する」と明記されていることを根拠に、シェル展開が効くと判断した(確度: 中〜高、実機での
動作確認は次回フォローアップとする — 静的検証のみで実機のGemini CLI/Antigravity CLIバイナリを
このセッションから起動して検証することはできなかった)。

**2. `pi/extensions/lib/shared.ts`新設 — `repoRoot()`の3重実装を統合**: `security-gate.ts`・
`graphify-hint.ts`・`auto-memory.ts`に一字一句同一の`repoRoot()`が独立に3回コピーされていた
(Phase 1〜4で各ファイルを書き換えた際に見落としていたもの)。`@earendil-works/pi-coding-agent`の
拡張機能ローダー実装(`dist/core/extensions/loader.js`)を直読して確認した結果、
`pi/extensions/lib/`のようなサブディレクトリに`index.ts`/`index.js`/`package.json`(pi.extensions
宣言付き)を置かなければ、そのサブディレクトリ自体が拡張機能ディスカバリの対象から完全に
スキップされることが判明したため、安全に切り出せた。呼び出し元の`import.meta.url`を引数で渡す
設計にした点に注意(`repoRoot()`自身の`import.meta.url`を使うと`lib/`という1階層分ずれた場所を
起点に解決してしまうバグになる)。

**3. `pi/extensions/lib/cli-bridge.ts`新設 — CLIブリッジ3ファイルの重複コード統合**:
`bridge-claude.ts`・`bridge-antigravity.ts`・`bridge-codex.ts`(各180行前後)は「他CLIバイナリを
spawnし、stdout/stderrをストリーミング蓄積し、AbortSignal経由のキャンセルをSIGTERM→3秒後SIGKILLで
処理する」という約35行のコードが一字一句同一だった。`runCliBridge()`(プロセス起動・ストリーミング・
abort処理)と`deriveCliBridgeOutput()`(isError/outputText導出)の2関数へ切り出し、各ファイルは
paramsスキーマ・CLI引数構築・render関数(ツールごとに文言・タグが異なる)のみを残した。
aborted分岐の`details`オブジェクトにmodelフィールドを含めるかどうかがclaude版とagy/codex版で
元々非対称だった点は、既存の意図しない差異である可能性が高いが、統合の一環で silently 揃えず
そのまま保持した(挙動変更を最小化する方針)。fakeバイナリを使った実機テスト(正常終了・
非ゼロ終了・abort・バイナリ不在の4パターン)で新旧の出力が完全一致することを確認済み。

**security-auditレビューで発見・修正した指摘(Medium)**: abort時のSIGTERM→3秒後SIGKILL
フォールバックが実質不発だった(3ブリッジ統合前から一字一句同一のまま存在していた既存バグ、
今回の統合作業中に発見)。`ChildProcess#killed`は「`kill()`が呼ばれたか」を示すフラグであって
「実際に終了したか」ではない(Node.js公式ドキュメント) — `proc.kill("SIGTERM")`の呼び出し
成功時点で即座にtrueになるため、旧実装の`if (!proc.killed) proc.kill("SIGKILL")`は通常ケースで
常にfalse判定となりSIGKILLへのフォールバックが不発だった。`proc.on("exit", ...)`による実際の
終了確定フラグへ置き換えて修正したが、それだけでは不十分なことも実機検証で判明した:
単一PIDへのkillでは、子プロセス自身が更に生成した孫プロセス(bashスクリプトが起動した
`sleep`等)へシグナルが届かず、孫プロセスが標準出力パイプを保持し続けて`close`イベントが
(SIGKILLしたにも関わらず)自然終了まで発火しないケースを確認した(fakeバイナリで実測:
SIGKILL後`close`が期待値の3.5秒ではなく自然終了の10秒まで遅延)。`detached: true`で子
プロセスを新しいプロセスグループのリーダーにし、`process.kill(-pid, sig)`(負のPID = プロセス
グループ全体)でkillする設計へ変更し、3.5秒での終了を確認した。`pi/extensions/lib/cli-bridge.test.ts`
(新設、bun実行、12ケース)で正常終了・非ゼロ終了・バイナリ不在・SIGTERM協調終了・
SIGTERM非協調(SIGKILLフォールバック必須)の5シナリオを再発防止テストとして追加。

**4. swarm系hooksの共有lib化 + 重大バグの発見・修正(`agent/skills/swarm-implement/scripts/swarm-lint-lib.sh`新設)**:

`claude/hooks/swarm-fable-gate.sh`と`swarm-write-scope-gate.sh`(いずれも当時のパス。2026-09-04に
`agent/hooks/claude/`へ実体移動済み、下記追記参照)に一字一句同一のgrant消費ループ
(TTL失効チェック+mvによる原子的消費)が独立実装されていたため、`grant_consume()`として統合した。
`swarm-lint-lib.sh`には併せて`swarm_lint_dockerfile()`/`swarm_lint_go_package()`(hadolint/
golangci-lint呼び出し+build-tag再試行ロジック、`swarm-post-edit-lint.sh`と`swarm-stop-verify.sh`で
20行超がほぼ同一のまま重複している箇所)も用意したが、**本Roundではgrant_consume()の配線までに
留め、この2関数はまだどこからも呼ばれていない**(意図的なスコープ限定 — `swarm-post-edit-lint.sh`
は即時1ファイルblock、`swarm-stop-verify.sh`はセッション全体をバッチ収集して報告、という制御
フローの違いをどう関数分離するか設計判断が要るため、次回フォローアップとする)。

**追記(2026-09-04、claude-hooks-full-agent-consolidationミッションで実施)**: 上記の次回
フォローアップを実施し、`swarm_lint_dockerfile()`/`swarm_lint_go_package()`を
`agent/hooks/claude/swarm-post-edit-lint.sh`・`agent/hooks/claude/swarm-stop-verify.sh`両方へ
実際に配線した。制御フローの違い(即時block vs バッチ収集)はhadolint/golangci-lint呼び出し自体を
共有関数に委ね、呼び出し元での成否判定・エラー蓄積方法はそれぞれ従来どおり個別に保持することで
分離した(`swarm_lint_go_package`の`timeout_seconds`・`extra_golangci_flags`引数で
post-edit-lint.sh=120秒/フラグ無し、stop-verify.sh=180秒/`--new-from-rev=HEAD`という既存の
意図的差異を表現)。併せて`swarm_lint_is_vald_repo()`(go.modのvald判定、2ファイルで重複していた
grep)も新設・統合した。

**この作業中に発見した重大な既存バグ(2026-09-03以前から存在)**: `swarm-write-scope-gate.sh`
(Tier Bガバナンスファイルへの直接書き込みをブロックするhook)は新設当初から
`$(dirname "${BASH_SOURCE[0]}")/../skills/swarm-implement/scripts/write-scope-lib.sh`という
文字列連結でライブラリをsourceしていたが、**POSIXパス解決の仕様上 `..` はシンボリックリンクの
「リンク先」を基準に解決される**ため、`claude/hooks`(実体でも`~/.claude/hooks`symlink経由でも)
からの`../skills`は常に`claude/skills`(swarm-loop/swarm-metaの統計ファイルのみを保持する別の
実ディレクトリ)に解決され、`agent/skills/swarm-implement/scripts/write-scope-lib.sh`には
**一度も到達できていなかった**。結果、`[ -f "$lib" ] || exit 0`が常にtrueとなり、
**このhookは新設以来一度もTier Bファイルを保護できておらず、恒久的にno-op化していた**
(既存の限界として明記されていた「暗号学的な証明ではない」という程度の話ではなく、
実質的に何も防いでいなかった)。同じ`../skills/`パターンは`swarm-fable-gate.sh`・
`swarm-parallel-gate.sh`のTTL上書き設定(`fable-budget.conf`)読み込みにも使われており、
これらも常にデフォルト値へフォールバックしていた(実害は前者ほど大きくないが同種のバグ)。

修正は`claude/hooks/security-gate.sh`等が既に使っている堅牢なパターン
(`cd -P`による物理解決 → 実体ディレクトリを得てから`agent/...`へ絶対パスで降りる)へ統一した。

**この発見に至った経緯**: `agent/skills/swarm-implement/scripts/test-fable-gate.sh`・
`test-parallel-gate.sh`という既存の回帰テストが**両方とも**hookへの相対パス計算を1階層
間違えており(`agent/skills/swarm-implement/scripts`から実hookの`claude/hooks/`へは4階層上る
必要があるのに3階層+`hooks/`だけになっていた)、常に`bash: command not found`(exit 127)で
FAILし続けていた。テストが機能していなかったため、hooks側の`../skills/`バグも長期間検出されずに
残っていた。両テストファイルのパス計算を修正した上で再実行し、grant消費ロジックの実際の挙動が
初めて正しく検証できるようになった。`swarm-write-scope-gate.sh`には専用テストが存在しなかったため
`test-write-scope-gate.sh`(13ケース)を新設した。

**検証**: `test-fable-gate.sh`(19件、全PASS)・`test-parallel-gate.sh`(7件、全PASS)・
`test-write-scope-gate.sh`(新設13件、全PASS)・`test-fable-guard.sh`(43件、既存のまま影響なし
全PASS)。3つの`validate-harness.sh`・共有hooks test-*.sh群も再確認しクリーン。

**Tier B保護が実際に機能するようになったことの実地確認**: 本Roundの作業中、`swarm-write-scope-gate.sh`
自身への2回目の編集(`../skills/`修正後)が実際にブロックされ、`budget-guard.sh --write-scope-grant`
での明示的なgrant発行を要求されたことで、修正が正しく効いていることを意図せず実地検証する形になった。

## 既知の残課題（未着手）

- **`test-security-rules.sh`の「git reset --hard on main cwd」系ケースがカレントブランチ依存**:
  `rule_engine.py:_git_branch`は`git -C <target_dir> rev-parse --abbrev-ref HEAD`でこのリポジトリ
  自身の実ブランチ名を取得するため、テストをmain/master以外のブランチ(feature branch等)で実行すると
  `protected_branches`と不一致になりFAILする(2026-09-03のhooks Phase2/3統合時にsecurity-auditが
  発見、`git stash`でPhase2/3適用前のベースコミットでも同一条件で再現することを確認済み — 本統合による
  新規リグレッションではなく、既存のテスト設計上の弱さ)。テストをmain/master相当のfixtureディレクトリ
  (実際のgitリポジトリではない固定ブランチ名を持つ何か)に対して実行するよう改修する必要があるが、
  本ディレクトリの対象外(Phase 1で新設された`security-rules.json`/`test-security-rules.sh`自体の
  設計課題)として残す。
- **codex 向け設定の新設**: 現状 codex に設定ディレクトリが存在しないため着手できない。
- **Pi の `dmi:true` 相当機構の欠如**: 上記調査結果参照。Swarm 系 skill を Pi へ本格移行する際の
  設計課題として残る。
- **`agy/skills/` の `SKILL.stats.json` 32件 vs claude/pi の2件という利用実績の偏り**: 設定の話では
  ないため本ディレクトリの対象外だが、Antigravity 経由での skill 利用が突出して多いという観察事実は
  記録しておく（原因調査は別ミッション）。
- **Executor の常駐サービス化**: `executor install` は auto mode クラシファイアにブロックされたため
  未実施。現状はオンデマンド daemon（`executor call` 実行時に自動起動）で運用している。マシン再起動後は
  最初の MCP 呼び出し時に起動し直しになる（数秒の遅延）。永続化したい場合はユーザーが手動で
  `executor install` を実行する。
- **`agy/settings.json` の `mcpServers` がExecutor移行時に未更新だった問題**: 解消済み（2026-09-03）。
  `agy/mcp_config.json`（Antigravity CLI が読む）は `b06a8e86` で `codegraph`/`filesystem`/`memory` を
  `executor` へ集約済みだったが、`agy/settings.json`（Google公式 Gemini CLI が
  `~/.gemini/settings.json` 経由で直接読む、[公式ドキュメント](https://github.com/google-gemini/gemini-cli)
  で `mcpServers.<name>.httpUrl` によるリモートHTTP MCPサーバー指定をサポートすることを確認済み）は
  この移行の対象から漏れており、旧来の生の `codegraph`/`filesystem`/`memory` サーバー定義がそのまま
  残っていた。`agy/mcp_config.json` と同じ方式（`{"httpUrl": "http://127.0.0.1:4788/mcp"}`）で
  `executor` エントリへ統合し解消した。
- **`claude`/`agy` の `mcpServers.executor` 呼び出し許可（`permissions.allow`）が未更新**: 一部解消
  （2026-09-03）。`claude/settings.json` の `permissions.allow` にあった旧 `mcp__codegraph__*`(10件)・
  `mcp__filesystem__*`(7件)・`mcp__memory__*`(9件)、計26件の失効済みエントリは削除した。
  ただし**新しい `mcp__executor__*` 相当のエントリは追加していない** —
  `executor tools describe`/`executor tools search`・executor MCPエンドポイント(`http://127.0.0.1:4788/mcp`)
  への直接プローブを試みたが、これらはExecutor自身のCLI経由の内部カタログ表現
  （`codegraph.org.default.codegraph_explore` のような namespace付きpath）であり、Claude Codeが
  MCP `tools/list` 経由で実際に見る `mcp__executor__<name>` の名前解決規則とは異なる可能性が高く、
  静的調査だけでは確証が持てなかった（daemon起動には `executor call` 経由の実呼び出しが必要で、
  単純なHTTP `initialize` プローブでは自動起動しなかった）。誤った名前を先回りで追加するより、
  実際にcodegraph/memory/filesystem相当のツールをClaude Code経由で呼び出した際に出る本物の許可
  プロンプトを承認する形で自然に追加されるのを待つ方が安全という判断。
- **`agy/settings.json` の `hooks` キーが `agy/hooks/hooks.json` と別スキーマ・別内容のまま放置されている
  （未着手）**: `agy/settings.json.hooks` は `"BeforeTool"` というイベント名で `rtk hook agy`（rtk
  バイナリ自身の組み込みサブコマンド、dotfiles側の `agent/hooks/agy/rtk-rewrite.sh` とは別物）だけを実行する
  設定を持つ。これは `agy/hooks/hooks.json`（`"PreToolUse"`/`"PostToolUse"` イベント名、
  security-gate/vald-law-enforcer/graphify-assistant/post-edit-verifier等をフル装備）とは全く別の、
  Gemini CLI固有の独立したhooks設定である可能性が高い（上記のmcpServers同様、Gemini CLIと
  Antigravity CLIが別々の設定ファイルを読む2バイナリ構成だと推測される）。もしユーザーが実際に
  素の `gemini` CLIバイナリを使う場合、そちらには現状 security-gate/vald-law/graphify-hint の
  保護が一切効いていないことになる。実機でどちらのバイナリを使っているか・gemini-cli単体の
  hooks機構がPreToolUse相当のblock/ask/allow分岐をサポートするか、次回フォローアップで確認要
  （2026-09-03のAI関連dotfiles横断調査で発見、今回は調査対象4件の合意スコープ外のため未着手）。
- **claude/pi/agy 実機での動作確認は未実施**: 設定ファイルの書き換えとExecutor側のカタログ登録までは
  完了しているが、各ツールを実際に起動してExecutor経由でmemory/codegraph/filesystemツールが呼び出せる
  ことの実地検証はしていない。次回起動時に確認すること。
- **`sync-verify.sh` の CI/pre-commit hook 配線は未実施**: 実際にデプロイ済みの `$HOME` 側 symlink
  を検証するため `make *_install` 前提で意味のある結果を返さず、CI runner 上では false-FAIL が
  多発する。現状は手動実行のみ。`make` ターゲットやpre-commit hookから自動的に呼び出す配線は次の
  フォローアップとする（`.github/workflows/agent-sync-verify.yaml` でも意図的にスコープ外にしている）。
  一方 `test-security-rules.sh`（および `test-graphify-hint.sh`・`test-vald-law-rules.sh`・
  `test-memory-context.sh`・`test-settings-common.sh`）は同ワークフローの `test-suite` ジョブへ
  CI配線済み（push/workflow_dispatchで実行、pull_requestは detached HEAD による
  `test-security-rules.sh` の一部サブテストのフィクスチャ分離ギャップのためジョブ全体をスキップ）。
- **`agent/security-rules.json` データ共有化後の`security-audit` agentレビュー**: 実施済み
  （2026-09-02）。Medium 1件（`chmod_777_system_path` がサブディレクトリを捕捉しなくなっていた —
  旧claude実装は非アンカーgrepでサブディレクトリも捕捉していたが、安全側統合の過程で誤って
  最も狭い版に寄ってしまっていた）、Low 2件（`dd`/`redirect`の`nvme`デバイス判定がnamespace
  suffix必須になり`/dev/nvme0`のようなコントローラ文字デバイスへの書き込みを見逃していた、
  `git_reset_hard_protected_branch`の`worktree`除外がcase-insensitive化され大文字混じりの
  コメントで保護ブランチ上の`reset --hard`をすり抜けられた）を検出・修正済み。いずれも
  `agent/scripts/test-security-rules.sh`へ再発防止の回帰テストを追加した。Critical/High無し、
  正規表現インジェクション・コマンドインジェクションも無しと確認済み。
- **`vald-law345-check.sh`のPreToolUse化に伴う「差分スキャン」トレードオフ(意図的、受容済み)**:
  security-audit指摘(2026-09-03)。claude/piのLaw3/4/5は「その変更が新たに持ち込む内容のみ」を
  検査する設計(旧PostToolUseはファイル全文を毎回再走査していた)。このため、1回のEdit呼び出しでは
  違反にならないが複数回のEdit呼び出しに分割すると検出をすり抜ける組み合わせ(例:
  1回目でfunc骨格を追加、2回目で`panic(err)`を追加)が理論上ありうる。悪意ある回避というより
  通常のインクリメンタルな編集で偶発的に起こりうるトレードオフであり、Vald Lawはハードな
  セキュリティ境界ではなくコーディング規約のガードレールである点、golangci-lintやコードレビュー
  ("vald-reviewer" agent)が別途バックストップとして機能する点から、受容可能と判断し実装は
  変更しない。旧実装(ファイル全文の毎回再走査)へ戻すことは、Editが触れていない既存箇所への
  重複指摘というトレードオフを逆に持ち込むため、単純な優劣ではなく設計判断であることを明記する。
- **`agent/hooks/{claude,agy,pi}/`のmerged directory化(2026-09-03)に伴う既知の残課題4件**
  (Phase 4.5 Round 1/2敵対的レビューで発見、CRITICAL 1件は修正済み・残りは意図的に見送り):
  1. **Makefile.d/install.mkのmerged directory構築idiomの重複(DRY化見送り)**: `claude/agy/pi`
     いずれの`install`ターゲットも「既存symlinkガード→`mkdir -p`→2連続の`find ... -exec ln -sfvn`」
     という同型の4-6行ブロックを手書きで重複させている(`nix/modules/home/dotfiles/agent-tools.nix`の
     `mergedDirFiles`ヘルパーが同じパターンをNix側では既に抽象化済み)。CRITICAL修正(下記4参照)
     直後の同一領域への追加リファクタリングはリスク対効果が見合わないと判断し本ミッションでは
     見送った。将来`MERGE_DIR_FUNC`のようなMakefile関数マクロを`DEPLOY_FUNC`(既存の単一ソース版)
     に倣って導入するfollow-up候補。
  2. **stale symlinkのprune処理が無い**: `find <src> -exec ln -sfvn {} <dest>/ \;`は既存ファイルへの
     symlink追加・更新のみを行い、ソース側でファイルがrename/削除された場合に宛先の孤児symlinkを
     除去しない(単一ディレクトリsymlinkだった旧設計では発生し得なかった問題)。本ミッションの
     diffでは初回の「旧whole-dir symlink→merged directory」遷移(既存symlinkを丸ごと除去してから
     再構築するため孤児は残らない)のみで、2回目以降の再インストール時にファイルrename/削除が
     あった場合に初めて顕在化する。Nix側(`home-manager`の世代管理による自動cleanup)とは非対称な
     ギャップであり、Makefile側のみの既知の残課題。
  3. **sync-manifest.jsonがmerged directory機構自体を追跡していない**: `not_shareable.hooks/*.sh`
     エントリの`reason`フィールドは現行パスを正しく説明しているが、`sync-verify.sh`はこの
     `not_shareable`配列を機械的に検証しない(プローズとしての説明に留まる)。merged directoryの
     配線が正しいか(両ソースの全ファイルが個別symlinkとして到達可能か)を自動検証する新規
     `mode`の設計は本ミッションのスコープを超えるため見送り。
  4. **`readlink -f`(GNU coreutils限定)のmacOS/BSD非互換性**: CRITICAL修正(merged directory化に
     よるroot解決崩壊、`cd -P "$(dirname "${BASH_SOURCE[0]}")"`が新設計でsymlink未解決になる
     問題)は`readlink -f`でファイル自身のsymlinkを先に解決する方式で対処したが、これはGNU
     coreutils限定の機能で macOS標準の`/usr/bin/readlink`には無い(既存の`agent/scripts/sync-verify.sh`
     の`readlink -f`使用と同じ制約を踏襲)。本リポジトリは`nix-darwin`実サポートを持ち
     (`nix/flake.nix`の`darwinConfigurations`)、`nix/modules/home/dotfiles/agent-tools.nix`は
     `isDarwin`分岐なしで全プラットフォームへ同一のmerged directory機構を適用するため、macOSも
     実デプロイ対象になりうる。`coreutils`パッケージは`nix/modules/home/packages/shared.nix`で
     全プラットフォーム共通に導入されているため通常はGNU版`readlink`がPATH上で優先されるはずだが、
     hook実行時のPATH構成がこれを保証すると実機検証はしていない。将来的な対処案としては
     `python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))'`(python3は全hookが
     `decide.py`呼び出しで既に依存している)への切替が考えられるが、本ミッションの主target環境
     (Arch Linux)ではない検証優先度の低いプラットフォームへの対処のため見送り、既知の残課題として
     記録する(2026-09-03 Phase 4.5 Round 2の security-adversarial-reviewer 指摘)。

## 2026-09-04: ハーネス SSoT 集約（agent/harnesses/）と Pi 高度化・総合検証の確立

### 1. ハーネス設定の完全集約 (`agent/harnesses/`)

従来リポジトリ直下に分散していた `claude/`, `pi/`, `agy/`, `codex/`, `primeagent/` の各設定ディレクトリを `agent/harnesses/` 配下へ一元集約。
リポジトリ内中間 symlink はゼロとし、`Makefile.d/install.mk` および `nix/modules/home/dotfiles/agent-tools.nix` が `$HOME` 側へ直接配線する構造を確立した。

- `agent/harnesses/claude/`: Claude Code 設定（settings, keybindings, hooks, model-routing.json）
- `agent/harnesses/pi/`: Pi Coding Agent 設定（settings, models, extensions, prompts, themes, model-routing.json）
- `agent/harnesses/agy/`: Antigravity 設定（settings, policies, hooks, mcp_config, model-routing.json）
- `agent/harnesses/codex/`: OpenAI Codex 設定（config.toml, model-routing.json, validate-harness.sh）
- `agent/harnesses/primeagent/`: PrimeAgent 設定（settings, models, model-routing.json, validate-harness.sh）

### 2. 抽象モデルルーティング（5 Tier + Fallback System）

- **正典スキーマ**: `agent/models/schema.json`
- **リゾルバ**: `agent/scripts/resolve-model-tier.py`（CLI & Python ライブラリ）
- **5 Tier**: `Low`（探索・軽量サーベイ）, `Medium`（秘書・要約・計画）, `High`（標準実装・Maker/Checker）, `XHigh`（複雑リファクタ・高難度検証）, `Max`（アーキテクト設計）
- **フォールバック トリガー**: `rate_limit`, `token_exhaustion`, `cost_saver` に応じた動的代替モデル解決
- **テスト**: `agent/scripts/test-model-routing.sh`

### 3. Pi Coding Agent の SOTA 拡張群

1. **真の並行ワーカプールとカテゴリ別上限 (`subagents.ts`)**:
   - `runTasksInParallelPool` による任意並行スロット制御。
   - カテゴリ別並行度: Research **100**, Testing **50**, Coding **16**, Review **16**, Benchmark **4**, Debugging **4**。
   - タスク内容と agent 名からの自動カテゴリ推論、混在バッチ時の最小値セーフガード。
2. **自律 Worktree 隔離 (`worktree-manager.ts` & `subagents.ts`)**:
   - コーディング系並列タスクにおいて、`.git/pi-worktrees/` 配下へ一時 Git worktree を自動生成。
   - メインツリーの index/HEAD を保護しつつ、依存関係・ビルドキャッシュを共有して自走。完了時に差分集約と自動解放。
   - コマンド `/worktree [list|cleanup]`。
3. **全会一致型（3/3 PASS）異種モデル合意検証 (`consensus-verifier.ts`)**:
   - Claude Sonnet 5, Gemini 3.8, GPT-6 Astra (または Kimi K3) の 3 系統異種フロンティアモデルによる並行審査。
   - 1 者でも懸念があれば REJECTED、全者一致の場合のみ APPROVED とする厳格な安全基準。
   - ツール `run_consensus_verification`, コマンド `/consensus`。
4. **インメモリ高速フックキャッシュ (`shared.ts`)**:
   - `callDecide` に LRU (Max 500) + TTL (60s) インメモリキャッシュを導入。
   - 高頻度な tool_call に対する Python 起動オーバーヘッド（~40-50ms）を排除し、<0.1ms で判定を即時返却。
5. **Swarm Relay クロスセッション通信 (`swarm-relay.ts`)**:
   - `agent/skills/swarm-relay/SKILL.md` 規約に準拠したセッション間メッセージング。
   - 同一リポジトリ上での並行セッション発見、precommit 競合検知、handoff。
   - コマンド `/relay [list|check|broadcast]`, ツール `relay_message`。
6. **セッション履歴全文検索 (`session-search.ts`)**:
   - `~/.pi/agent/sessions/` の過去ログを高速検索（コマンド `/sessions`, ツール `search_sessions`）。

### 4. 万全な機械検証体制 (`agent/scripts/test-all-harnesses.sh`)

- 全 5 ハーネスの健全性と SSoT 整合性をワンショットで検証する総合テストランナーを配備:
  1. `sync-verify.sh`: 全 36 エントリ PASS
  2. `verify-cache-alignment.sh`: 全 6 ハーネス PASS
  3. `test-model-routing.sh`: 全 Tier & Fallback PASS
  4. `test-harness-guard.sh`: 全 81 ケース PASS
  5. 各種エンジン検証（security-rules, vald-law-rules, graphify-hint, memory-context, merged-dir-root）: 全 PASS
  6. Pi 拡張単体テスト: 全 17 スイート 146+ テスト 100% PASS
  7. 全 5 ハーネス自己診断（Claude, AGY, Pi, Codex, PrimeAgent）: 全て OPERATIONAL
