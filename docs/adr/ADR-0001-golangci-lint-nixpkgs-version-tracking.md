# ADR-0001: golangci-lint を overlay で本家最新かつ go 追従ビルドにする

- **ステータス**: Accepted（2026-09-18 追記により一部修正、§7 参照）
- **日付**: 2026-09-18
- **対象コンポーネント**: `nix/overlays/default.nix`, `nix/modules/home/packages/shared.nix`,
  `nix/flake.lock`（`nixpkgs` 入力）
- **決定者**: kpango / Claude Code (grill-interview 面談による合意)

## 1. コンテキストと問題提起 (Context & Problem Statement)

`nix/modules/home/packages/shared.nix` は Linux/macOS 共通の `home.packages` として `go` と
`golangci-lint` を並べて提供している。両方とも nixpkgs (`nixos-unstable` を `flake.lock` で pin)
から取得しているが、面談時点の検証で以下の 2 点が判明した。

1. **本家からの遅延**: pin 済み nixpkgs revision の `golangci-lint` は `2.12.2` だが、
   golangci-lint 本家の最新タグは `v2.13.2`(2026-08-27 公開)で 1 マイナーバージョン遅れている。
   `nix flake update nixpkgs`(`make nix/update`)だけでは、nixpkgs 側のメンテナが
   `golangci-lint` の `package.nix` を更新するまでこの遅延は解消しない。
2. **go バージョンからの切断**: nixpkgs の `golangci-lint` package.nix
   (`pkgs/by-name/go/golangci-lint/package.nix`) は `buildGo126Module`(go 1.26 固定のビルダー)
   を使っており、`shared.nix` が提供する `go`(トップレベルの `pkgs.go`)とは別系統の
   derivation である。package.nix 自身のコメントに「golangci-lint は新しい go への追従に
   コード変更を要することが歴史的にあるため、意図的に固定バージョンを使う」とある通り、
   `pkgs.go` を単独で bump しても `golangci-lint` は再ビルドされない。

ユーザー要求は「golangci-lint を可能な限り最新に nix で管理する」「go のバージョンが上がったら
golangci-lint も必ず rebuild する」「Linux/macOS で同じ仕組み・同じバージョンを提供する」の 3 点。

## 2. 決定推進要因 (Decision Drivers)

- Driver 1: golangci-lint のバージョンを本家リリースにできるだけ近づけたい(nixpkgs のタイムラグを打ち消す)。
- Driver 2: `pkgs.go` の bump が golangci-lint の再ビルドを機構として強制するようにしたい(手動同期に頼らない)。
- Driver 3: 既存の overlay 運用パターン(`nix/overlays/default.nix` の lumen/prmt override)を再利用し、
  自前ビルド管理などの過剰実装(YAGNI 違反)を避けたい。
- Driver 4: Linux/macOS で設定を分岐させず、単一の overlay 適用点(`flake.nix` の `mkPkgs`)で
  両 OS に同じ仕組み・同じバージョンを配る。

## 3. 検討された選択肢 (Considered Options)

- **Option 1**: 現状の nixpkgs 追従のみに委ねる(何もしない)。
- **Option 2 [Selected]**: `overlays/default.nix` に override を追加し、
  (a) `src`/`vendorHash` を本家最新タグに更新、(b) builder を `buildGo126Module` から
  `pkgs.buildGoModule`(= `shared.nix` の `go` と同一 derivation を使う汎用ビルダー)に差し替える。
- **Option 3**: golangci-lint 専用の flake input を追加し、nixpkgs の package.nix を使わず完全に自前でビルド定義を保守する。

## 4. 決定結果と根拠 (Decision Outcome & Rationale)

Option 2 を選択した。

- Driver 1 は override で `src`(fetchFromGitHub の tag/hash)を本家最新タグに差し替えることで、
  nixpkgs のタイムラグを打ち消せる。
- Driver 2 は builder を明示的に `go = final.go`(= このオーバーレイが提供する `go`)へ束縛することで、
  `pkgs.go` の derivation が変われば golangci-lint の入力ハッシュも変わり、Nix の依存グラフ上 rebuild が
  自動的に強制される。当初は「`pkgs.buildGoModule` に差し替えるだけで自動追従する」と想定していたが、
  これは誤りだったことが実装時に判明した — §7 追記を参照。
- Driver 3 は、nixpkgs の package.nix(vendorHash 管理・ldflags・shell completion 生成など)を
  そのまま再利用し、`src` と builder だけを override する最小差分で実現できる。既存の
  lumen/prmt override と同じ `overlays/default.nix` 一箇所に集約される。
- Driver 4 は `overlays/default.nix` が `flake.nix` の `mkPkgs`(NixOS/Darwin 双方の
  `nixpkgs.pkgs` に使われる共通関数)から適用されるため、OS ごとの分岐を書かずに自動的に満たされる。

Option 1 は Driver 1/2 を満たさないため却下。Option 3 は nixpkgs の既存ビルド知見
(vendorHash 管理・go 互換性の当たり)を捨てる過剰実装であり、Driver 3 に反するため却下した。

## 5. 不変条件と影響 (Invariants & Consequences)

### 正の影響 (Positive Consequences)

- golangci-lint のバージョンは、overlay の `version`/`hash` を更新するだけで本家最新に追従できる。
- `pkgs.go` の bump は golangci-lint の rebuild を機構として強制する(手動同期不要)。
- Linux/macOS で設定の分岐がなく、同一の overlay・同一のバージョンが両 OS に配られる。

### 負の影響・トレードオフ (Negative Consequences)

- nixpkgs メンテナが検証していない go × golangci-lint の組み合わせになる。将来 `pkgs.go` が
  golangci-lint 未対応のマイナーバージョンに上がった場合、ビルドまたは実行時(型チェッカー API
  互換性など)に壊れる可能性がある。発生時は overlay 側で個別に対処する(パッチ適用、または
  一時的に builder を `buildGoModule` から特定バージョンの `buildGoNNNModule` へフォールバック)。
- golangci-lint 本家の新タグが出るたびに、overlay の `version`/`src hash`/`vendorHash` を
  手動更新する必要がある(自動追従の仕組みは持たない — 過剰実装を避けるため意図的に手動運用とした)。

### システム不変条件 (Invariants)

- `nix/overlays/default.nix` の golangci-lint override は、常に「builder が `shared.nix` の `go`
  と同一 derivation を参照している」状態を維持する(builder を別の固定バージョンに戻す変更をする場合、
  本 ADR の Driver 2 が満たせなくなることを明記してから行う)。
- golangci-lint のバージョン/ハッシュ管理は `nix/overlays/default.nix` 一箇所に集約する
  (`shared.nix` 側にはバージョン情報を持たせない)。

## 6. 検証方法 (Verification Method)

```sh
# golangci-lint のバージョンが overlay で指定した本家最新タグと一致することを確認
nix eval --impure --expr '
  let flake = builtins.getFlake (toString ./nix);
      pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; overlays = import ./nix/overlays; };
  in pkgs.golangci-lint.version'

# golangci-lint のビルドに使われる go が shared.nix の go と同一 derivation であることを確認
nix eval --impure --expr '
  let flake = builtins.getFlake (toString ./nix);
      pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; overlays = import ./nix/overlays; };
  in pkgs.golangci-lint.go.version == pkgs.go.version'

# 実ビルドが通ることの確認 (Darwin)
nix build ./nix#darwinConfigurations.<host>.system --dry-run
```

## 7. 追記 (Amendment, 2026-09-18)

`go.mod` が `go 1.27.0` を要求する下流プロジェクト(wevox-knowledge-base)の要求を満たすため、
`nix/flake.lock` の `nixpkgs` 入力を `nix flake lock --update-input nixpkgs` で
`e72e4f2`(2026-08-04)→ `b1b8759`(2026-09-16)に更新した。この作業で本 ADR の前提 2 点に
ずれが見つかったため、以下の通り修正する。

### 7.1 `go` 自体のオーバーライドが追加で必要だった

`nixpkgs` の無印 `go`/`buildGoModule` は「常に同じ go バージョンを指す」よう
`pkgs/top-level/all-packages.nix` で `go = go_1_26; buildGoModule = buildGo126Module;`
と明示的にエイリアスされており、`go_1_27`(GA, 追記時点で `1.27.1`)へは自動追従しない。
このため `nix/overlays/default.nix` に `go = final.go_1_27;` を追加した。
`shared.nix` 側は変更していない(Invariant-1 のとおり、バージョン選択はこのオーバーレイ一箇所に
残る)。

### 7.2 `buildGoModule` は「go 非依存の汎用ビルダー」ではなかった(Driver 2 の前提修正)

決定当初、`.override { buildGo126Module = prev.buildGoModule; }` で golangci-lint の builder を
`buildGoModule` に差し替えれば「`pkgs.go` が変われば自動的に追従する」と想定していた。
しかし `nix/flake.lock` の更新後に検証したところ、これは誤りだと判明した:

- `nixpkgs` の `buildGoModule` は `buildGo126Module` への**固定エイリアス**であり
  (`pkgs/top-level/all-packages.nix`: `buildGoModule = buildGo126Module;`)、
  `buildGo126Module` 自体も `callPackage ../build-support/go/module.nix { go = buildPackages.go_1_26; }`
  と `go` を明示的に go 1.26 へ固定してビルドされる。「`pkgs.go` を参照する汎用ビルダー」ではなく、
  単にもう一つの固定ピンだった。
- 加えて、`nixpkgs` は本 ADR 決定時点(2026-09-18 未明、`e72e4f2` 時点)の
  golangci-lint(2.12.2, go1.26 固定)から、`b1b8759` 時点では golangci-lint 本家最新の 2.13.2 自体を
  `buildGo127Module`(go 1.27 固定)でビルドする package.nix に自ら追従していた(パラメータ名も
  `buildGo126Module` → `buildGo127Module` に変更されていた)。そのため旧来の
  `override { buildGo126Module = prev.buildGoModule; }` は評価時に
  `unexpected argument 'buildGo126Module' … Did you mean buildGo127Module?` で失敗し、
  仮にパラメータ名だけを追随させても(`buildGo127Module = prev.buildGoModule;`)、
  `prev.buildGoModule` = `buildGo126Module` のままなので go 1.26.7 に**逆行**していた
  (`nixpkgs` 標準の golangci-lint は go 1.27.1 を使うのに、このオーバーレイが go 1.26.7 に
  ダウングレードしてしまう状態)。
- 修正: `override { buildGo127Module = prev.buildGoModule.override { go = final.go; }; }`。
  `buildGoModule`(≡`buildGo126Module`)自身が `callPackage` で `.override`
  可能な `go` 引数を持つことを利用し、`go` だけを明示的に `final.go`(= 7.1 の `go_1_27`)へ
  差し替える。これで golangci-lint のビルドに使われる go は常にこのオーバーレイの `go` と
  一致し、Driver 2 が実際に機構として成立する。

検証(`nix eval`, `nix build` 双方で確認済み、2026-09-18):

```sh
nix eval --impure --expr '
  let flake = builtins.getFlake (toString ./nix);
      pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; overlays = import ./nix/overlays; };
  in { go = pkgs.go.version; golangciLintGo = pkgs.golangci-lint.go.version; }'
# => { go = "1.27.1"; golangciLintGo = "1.27.1"; }

nix build --impure --expr \
  '(import (builtins.getFlake (toString ./nix)).inputs.nixpkgs { system = builtins.currentSystem; overlays = import ./nix/overlays; }).golangci-lint' \
  --no-link --print-out-paths
# => golangci-lint has version 2.13.2 built with go1.27.1 …
```

### 7.3 バージョン追従オーバーライド(§4 Option 2b)は現時点で no-op

`nixpkgs` の `pkgs/by-name/go/golangci-lint/package.nix` は `b1b8759` 時点で本家最新の
`v2.13.2` に自ら追従済みで、`src` hash・`vendorHash` も本オーバーレイの値と完全に一致する
(2026-09-18 確認)。したがって現時点では `.overrideAttrs` によるバージョン/ハッシュの
明示指定は実質的に無意味だが、CONTEXT.md Invariant-1(バージョン管理はこのオーバーレイ一箇所に
集約する)を保つため、また将来 `nixpkgs` が再び本家に遅れた際に更新対象を一箇所に保つため、
削除せずそのまま残す(YAGNI の観点で「今すぐ削除すべきか」も検討したが、既存の Accepted
決定を無許可で縮小するのは避け、次に `nixpkgs` が遅れて実際に値が乖離した時点で通常の
fakeHash 更新手順(CONTEXT.md「バージョン更新の運用」)に従って更新する)。
