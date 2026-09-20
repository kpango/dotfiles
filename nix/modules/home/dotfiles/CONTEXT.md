# CONTEXT — nix/modules/home/dotfiles/（dotfiles配置）

## 1. ドメイン用語集 (Domain Glossary)

- **単純ミラー (plain mirror)**: `home.file."<path>".source = "${dotfilesPath}/..."` のように、repo 内に実体があるファイル/ディレクトリをそのまま指すだけの `home.file` エントリ。`Makefile.d/install.mk` の `ln -sfvn` と完全に同じ結果を作れるため、Make 側へ委譲できる。
- **Nix派生値エントリ (Nix-derived-value entry)**: `.text`/`builtins.replaceStrings` 等で Nix のビルド成果物（store path、パッケージ derivation の出力等）を埋め込む `home.file` エントリ。例: `darwin.nix` の `.gnupg/gpg-agent.conf`（`pinentry-tmux-darwin` ラッパーの store path を埋め込む）。Make の `ln -sfvn` では再現できないため、Nix 管理のまま残す。
- **DOTFILES_MAP**: `Makefile.d/install.mk` が定義する、repo 内パス → `$HOME` 配下パスの対応表（約90エントリ）。`dotfiles/install` ターゲットが `ln -sfvn` で一括展開する。`claude/install`/`pi/install`/`agy/install`/`codex/install`/`primeagent/install` は全てこれを前提条件に持つ。
- **ARCH_LINK_MAP / ARCH_SUDO_LINK_MAP / ARCH_SUDO_CP_MAP**: `arch/install`（genuine Arch Linux ホスト専用のブートストラップ）が使う別系統のマップ。sway/waybar/fcitx5 等の Linux デスクトップ設定と、pacman/systemd 等の sudo が要る system 設定を含む。NixOS ホストはこの経路を使わない（`linux.nix` の `home.file` が NixOS 側の並行実装）。
- **ライブ checkout (live checkout)**: `${homeDirectory}/${settings.dotfilesRelPath}`（例: `$HOME/go/src/github.com/kpango/dotfiles`）。編集可能な実際の git working tree。`nix-update.nix` の `flakeDir` が既に使っている規約で、`dotfilesPath`（flake の `path:..` input、評価のたびに Nix store へコピーされる不変スナップショット）とは別物。

## 2. システム不変条件 (System Invariants)

- **Invariant-1**: repo 内に実体があるファイル配置（単純ミラー）は `Makefile.d/install.mk` が単一の真実源。`home.file` は Nix 派生値エントリにのみ使う。
- **Invariant-2**: `home.activation` から make を呼ぶスクリプトは、実行前に `id -u` が 0 でないことを検証するガードを持つ。nix-darwin/home-manager の標準統合は home-manager activation を対象ユーザーの文脈で実行するが（実測済み）、このガードは前提が崩れた場合に黙って実行せずエラー停止するための防御。
- **Invariant-3**: `ARCH_LINK_MAP`/`ARCH_SUDO_*` 系（`linux.nix` の sway/waybar/fcitx5 等）は Invariant-1 の対象外。NixOS ホストの並行実装であり、genuine Arch Linux ホスト向け Make 経路との重複ではない。

## 3. 責務境界と入出力規約 (Boundary & Contracts)

- **許可される依存方向**: `nix/modules/home/dotfiles/*.nix` の `home.activation` → `Makefile.d/install.mk` の既存 install ターゲット（`ROOTDIR` にライブ checkout パスを渡す）。逆方向（Makefile が Nix の評価結果を参照する）は発生しない。
- **エラー処理規約**: home.activation スクリプトは `set -eu` 相当（home-manager のデフォルト activation runner の挙動）。make 呼び出しが失敗すれば activation 全体が失敗する。これは意図的（Q3: sudo 資格情報キャッシュへの依存を明示的に許容し、失敗時は隠蔽せず表面化させる）。

## 4. 既知の制約と非目標 (Constraints & Non-Goals)

- **制約**: `home.activation` からの make 呼び出しは、`nix/switch` 実行時の対話的 sudo 認証のキャッシュに依存する。キャッシュが切れていると activation 中に sudo の対話プロンプトが発生し得る（許容済みトレードオフ）。
- **制約**: NixOS ホスト（p1/x1/g2/tr）は実機で未検証。`make nix/test/eval`（評価のみ）の正しさのみ確認済み。
- **Non-Goals**: `darwin.nix` の `.gnupg/gpg-agent.conf`（Nix 派生値）を Make 側へ移行することはしない。`ARCH_LINK_MAP`/`ARCH_SUDO_*` 系の Make 経路への統合もしない（Invariant-3）。
