# ADR-0002: dotfiles配置をMakefile symlinkベースへ統一する（home.fileとの二重実装を解消）

- **ステータス**: Accepted
- **日付**: 2026-09-18
- **対象コンポーネント**: `nix/modules/home/dotfiles/agent-tools.nix`, `nix/modules/home/dotfiles/shared.nix`, `nix/modules/home/dotfiles/linux.nix`, `Makefile.d/install.mk`（`darwin.nix`の`.gnupg/gpg-agent.conf`は対象外）
- **決定者**: kpango / Claude Code（grill-interview面談による合意）

## 1. コンテキストと問題提起

`~/.claude/plugins/installed_plugins.json`を home-manager の `home.file`（静的宣言、`agent/harnesses/claude/installed_plugins.json` から生成）で管理していたところ、前回の `nix/switch` が残した `.hm-bak` バックアップと衝突し、home-manager の「差分追跡 + バックアップ」機構自体が `make nix/switch` を失敗させた。

調査の結果、`nix/modules/home/dotfiles/agent-tools.nix` は最初から「Home-manager translation of Makefile.d/install.mk's claude/install, pi/install, agy/install, and codex/install targets」と明記された、既存 Makefile ロジックの並行実装だと判明した。`shared.nix`（atuin/ghostty/sheldon/helix 等）・`linux.nix`（`.gnupg/gpg-agent.conf`/`.docker/config.json` の Linux 版）にも、`Makefile.d/install.mk` の `DOTFILES_MAP` と重複する単純ミラーエントリが存在した。

ユーザーは Arch/Linux ホストで実運用している Makefile の symlink 機構（`ln -sfvn`、バックアップなしで冪等に上書き）を nix 環境でも主軸に使いたいと明言した。

## 2. 決定推進要因

- Driver 1: home-manager の「差分追跡 + バックアップ」機構自体が `.hm-bak` 衝突の根本原因であり、回避するには対象パスを `home.file` の管理から外す必要がある。
- Driver 2: 既存の `Makefile.d/install.mk` の `ln -sfvn` ベースの機構はバックアップ処理を持たず、この種の衝突が原理的に発生しない。
- Driver 3: repo 内に実体があるファイル配置のロジックを、Nix（`agent-tools.nix` 等）と Make（`install.mk`）の二重実装として保守し続けるコストを避けたい。
- Driver 4: symlink 先を実際の git checkout にすることで、repo 編集の即時反映という Makefile ベースの symlink 機構本来の利点を得たい（`dotfiles-root` flake input は評価のたびに Nix store へコピーされる不変スナップショットであり、この利点を持たない）。

## 3. 検討された選択肢

- **Option 1**: 現状維持 + `.hm-bak` 自動 prune のみ追加（既に `nix-update.nix` にドラフト済みの修正）。ユーザーの「Makefile の link 機構を主軸にしたい」という要求には応えない。
- **Option 2 [Selected]**: `home.activation` から Makefile の該当 install ターゲットを呼び出す形に統一し、対応する `home.file` エントリを削除する。Nix のビルド成果物（store path 等）に依存する値を埋め込む必要があるエントリのみ例外として Nix 管理を維持する。
- **Option 3**: `home.activation` からは呼ばず、Nix とは完全に独立したステップとしてユーザーが手動で `make ...install` を実行する運用にする。利便性（`make nix/switch` 一発で完結）を失う。

## 4. 決定結果と根拠

Option 2 を選択した。面談は当初 `agent-tools.nix`（AI ツール設定、358 パスの大半）のみを想定していたが、実装検証の過程で以下の2点が判明し、範囲を都度見直した。

1. `claude/install` 等の harness 専用 install ターゲットは前提条件として `dotfiles/install`（`DOTFILES_MAP` 全体、約90エントリ）を引き込む。これを呼ぶと `shared.nix` が個別管理する `atuin`/`ghostty`/`sheldon`/`helix` 等の単純ミラーエントリと衝突する。→ 対象範囲を `DOTFILES_MAP` でカバーされる全ての単純ミラーエントリ（`shared.nix`・`linux.nix` の該当分含む）に拡大した。
2. `agent-tools.nix` を含む `mkHomeManagerBlock` は `mkNixosSystem`（p1/x1/g2/tr）と `mkDarwinSystem` の双方に同一に使われる。→ Darwin 限定にスコープする案も検討したが、home-manager の機構自体に起因する問題であり一貫性を優先すべきという判断から、NixOS 側も含め全ホストに適用する。

home.activation は nix-darwin/home-manager の標準統合により対象ユーザーの文脈で実行される（実測: `make nix/switch` 実行ログで `"Activating home-manager configuration for yusukekato"` を確認済み）。念のため `id -u` が 0 でないことを検証する防御的ガードをスクリプト先頭に追加し、前提が崩れた場合は黙って実行せずエラー停止する。

実機での `make nix/switch` 実行で、`DOTFILES_MAP` 全体を Make 側の唯一の真実源とする前提（§4「決定結果と根拠」1.）が一部の宛先では成立しないことも判明した。`.zshrc`/`.zshenv` は `nix/modules/home/programs/zsh.nix` の `programs.zsh`（`envExtra`/`initContent` でライブ checkout の `zshrc`/`zshenv` を `source` する、home-manager 生成の合成ファイル）が、`.gnupg/gpg-agent.conf` は Darwin では `darwin.nix` の Nix ビルド値埋め込みが、それぞれ単純ミラー以上のことをしている。`dotfiles/install` がこれらを毎回生の live-repo symlink で上書きすると、次の activation で home-manager の `checkLinkTargets` が「自分が置いたものではない」として拒否する（`zsh.nix` 自身のコメントが既に記録している通り、`force = true` はこの 2 ファイルのキー形状には効かない）。`Makefile.d/install.mk` の `dotfiles/install` に `NIX_MANAGED=1` フラグを追加し、この 3 パス（`.zshrc`/`.zshenv` は全 OS、`.gnupg/gpg-agent.conf` は Darwin のみ）を Nix 起動時だけスキップするようにした。genuine Arch Linux の素の bootstrap（`arch/install`/`mac/install` 初回）は `NIX_MANAGED` を渡さないため影響を受けない。

実機での `make nix/switch` 実行で、home.activation の実行環境が想定より遥かに最小限であることが 2 段階で判明した。1 回目は `make: command not found`（`home.packages` の `gnumake` が PATH に無い）、`make`/`envsubst`(gettext)/`jq` を個別に `lib.makeBinPath` で足して再実行したところ、2 回目は `git`/`awk`/`zsh`/`go` も同様に見つからず失敗した（`/usr/bin`/`/bin` すら確実に PATH に乗っていない）。個々のツールを失敗のたびに後追いで足すのではなく、home-manager 自身が `home.packages` の全エントリを束ねる `config.home.path`（`home-manager-path` derivation）をそのまま使い、システム標準ディレクトリ（`sudo` 等 home.packages に無いもの用）を併せて PATH に設定する方式に変更した。

sudo を要する root home 共有処理（`$(ROOT_HOME)/.claude` 等、`claude/install`/`pi/install`/`agy/install` に内包）は、既存の install ターゲットをそのまま呼ぶことで維持する。`nix/switch` 実行時の対話的 sudo 認証（`nix-update.nix` の `Password:` プロンプト）のキャッシュに依存するため、資格情報キャッシュが切れている場合は activation 中に sudo の対話プロンプトが発生し activation がハングしうるという既知のトレードオフを受け入れる。

Make に渡す配置元パス（`ROOTDIR`）は、Nix の store コピーされた `dotfilesPath` ではなく、`nix-update.nix` が既に使っている `${homeDirectory}/${settings.dotfilesRelPath}`（ライブな git checkout）の規約を再利用する。

`ARCH_LINK_MAP`/`ARCH_SUDO_*` 等、`arch/install` が使う非 NixOS・非 `DOTFILES_MAP` 系の設定（sway/waybar/fcitx5 等）は対象外とする。これらは `linux.nix` が既に別の実行経路（genuine Arch Linux ホスト向けの Make 経路とは独立した、NixOS 向けの `home.file` 経路）として並行提供している既存の設計であり、重複ではないため変更しない。

実装検証の過程で、`dotfiles/install` が非 Darwin ホストで `/etc/docker/*`・`/etc/containerd/*` へ sudo 書き込みする箇所が NixOS の宣言的 `/etc` 管理と衝突することも判明した。この問題と Docker daemon 設定自体の単一ソース化は ADR-0003（docs/adr/ADR-0003-docker-daemon-settings-single-source.md）で別途扱う。

## 5. 不変条件と影響

### 正の影響 (Positive Consequences)

- `.hm-bak` 衝突が対象パスで構造的に発生しなくなる（`ln -sfvn` はバックアップを作らない）。
- symlink 先が実際の git checkout になり、repo 編集が即座に反映される。
- Nix 側と Make 側の二重実装が解消され、保守対象が1箇所（`Makefile.d/install.mk`）に集約される。

### 負の影響・トレードオフ (Negative Consequences)

- `home.activation` からの make 呼び出しが sudo の資格情報キャッシュに依存する（タイミング依存の脆さを許容する、Q3 参照）。
- ライブ checkout の実在（`${homeDirectory}/${settings.dotfilesRelPath}`）が activation 成功の前提になる。これは既に `nix-update.nix` が同じ前提を置いており新規リスクではないが、明示的に文書化する。
- `~/.docker/config.json` が `DOTFILES_MAP` 経由で Darwin ホストにも配置されるようになる（`darwin.nix` は意図的にこれを避けていたが、apple/container はこのファイルを読まないため実害はない軽微な副作用として許容する）。
- NixOS 側（p1/x1/g2/tr）は実機で検証していない。評価レベル（`nix/test/eval`）の正しさのみ確認済み。

### システム不変条件 (Invariants)

- **Invariant-1**: repo 内に実体があるファイル配置（単純ミラー）は `Makefile.d/install.mk` が単一の真実源となる。Nix の `home.file` は Nix のビルド成果物（store path 等）に依存する値を埋め込む場合にのみ使う。
- **Invariant-2**: `home.activation` から make を呼ぶスクリプトは必ず非 root 実行を検証するガードを持つ。
- **Invariant-3**: `ARCH_LINK_MAP`/`ARCH_SUDO_*` 系（genuine Arch Linux ホスト専用）は本決定の対象外であり、`linux.nix` の対応エントリを削除しない。

## 6. 検証方法

```sh
# 評価が壊れていないこと（NixOS 4ホスト + darwin 3ホスト）
make nix/test/eval && make nix/test/eval/darwin

# 依存グラフの解決（ダウンロード/ビルドなし）
make nix/test/dry-run/darwin

# 実際の activation（要 sudo、ユーザー自身が実行）
make nix/switch

# activation 後、対象パスがライブ checkout への symlink になっていること
readlink ~/.claude/agents  # -> $HOME/go/src/github.com/kpango/dotfiles/agent/agents
readlink ~/.config/ghostty/shaders
```
