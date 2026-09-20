# CONTEXT — nix/ (パッケージバージョン管理)

## 1. ドメイン用語集 (Domain Glossary)

- **overlay**: `nix/overlays/default.nix` が返す overlay 関数のリスト。`flake.nix` の `mkPkgs`
  経由で NixOS (`mkNixosSystem`) / Darwin (`mkDarwinSystem`) 双方の `nixpkgs.pkgs` に適用される、
  唯一のパッケージ override 集約点。
- **builder 差し替え (builder override)**: `pkg.override { <buildXxxModule 引数名> = <別の buildXxxModule>; }`
  の形で、パッケージがコンパイルに使う Go/Rust 等のツールチェイン derivation を差し替えること。
  `pkg.overrideAttrs`(ビルド後の属性上書き)とは別の機構。
- **本家追従 override**: nixpkgs の `package.nix` のビルドロジック(vendorHash 管理・ldflags 等)は
  再利用しつつ、`src`(fetchFromGitHub の `tag`/`hash`)と `vendorHash` だけを上流の最新リリースに
  差し替える override。`nix/overlays/default.nix` の既存コメントにある lumen/prmt のケースと同じ運用。

## 2. システム不変条件 (System Invariants)

- **Invariant-1**: `nix/modules/home/packages/{shared,darwin,linux}.nix` はパッケージの
  *利用*(`home.packages` への列挙)のみを行い、特定パッケージのバージョン/ハッシュのピン留めは
  行わない。バージョン管理が必要な override は必ず `nix/overlays/default.nix` に集約する。
- **Invariant-2**: `nix/overlays/default.nix` は `flake.nix` の `mkPkgs`(NixOS/Darwin 共通)からのみ
  適用される。OS 別の overlay ファイルを新設しない — Linux/macOS で同じパッケージ・同じバージョンを
  保証するための不変条件。
- **Invariant-3**: golangci-lint の builder は `go = final.go`(= `shared.nix` の `go` と
  同一 derivation)を明示的に束縛した builder を参照する
  (`nix/overlays/default.nix`: `buildGo127Module = prev.buildGoModule.override { go = final.go; };`)。
  `pkgs.go`(= このオーバーレイの `go` override)の bump は golangci-lint の rebuild を自動的に
  強制する。
  **注意**: `prev.buildGoModule` 単体(`.override { go = final.go; }` を伴わない形)は
  この不変条件を満たさない — nixpkgs の無印 `buildGoModule` は `buildGo126Module` への固定
  エイリアスであり、`pkgs.go` を自動的に参照する汎用ビルダーではない(2026-09-18 の nixpkgs bump
  対応時に判明)。この結合を外す/固定バージョンの builder に戻す変更をする場合、本 Invariant-3 を
  更新すること。

## 3. 責務境界と入出力規約 (Boundary & Contracts)

- **許可される依存方向**: `nix/modules/home/packages/*.nix` → (パッケージ名を参照) →
  `nix/overlays/default.nix` が提供する override 済み `pkgs.<name>`。逆方向(overlay が
  `modules/home/packages/*.nix` の内容を参照する)は発生しない。
- **バージョン更新の運用**: golangci-lint 本家の新タグが出た場合、`nix/overlays/default.nix` 内の
  `version`/`src hash`/`vendorHash` を手動で更新する(自動追従の仕組みは持たない — 過剰実装回避のため
  意図的に手動運用)。更新時は `nix build` で vendorHash の再取得(fakeHash からの
  mismatch エラーで正しい hash を得る標準手順)を行う。

## 4. 既知の制約と非目標 (Constraints & Non-Goals)

- **制約**: golangci-lint の builder を `pkgs.buildGoModule` に差し替えたことで、nixpkgs
  メンテナが検証していない go × golangci-lint の組み合わせになる。`pkgs.go` の bump 後にビルド/実行が
  壊れた場合は overlay 側で個別対処する。
- **Non-Goals**: golangci-lint 以外の Go 系ツール(`go-tools`, `gopls`, `delve`, `errcheck` 等)の
  builder 結合方式の変更は本節のスコープ外。必要になった場合は個別に検討する。
