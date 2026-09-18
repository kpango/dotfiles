# ADR-0003: Docker daemon 設定を `dockers/daemon.json` に単一ソース化する

- **ステータス**: Accepted
- **日付**: 2026-09-18
- **対象コンポーネント**: `dockers/daemon.json`, `Makefile.d/install.mk`（`dotfiles/install`）, `nix/modules/nixos/virtualization/docker.nix`, `nix/hosts/tr/virtualization/docker.nix`
- **決定者**: kpango / Claude Code（ADR-0002 の実装検証中に派生した grill-interview 面談による合意）

## 1. コンテキストと問題提起

ADR-0002（dotfiles 配置の Makefile symlink 統一）の実装検証中、`Makefile.d/install.mk`の`dotfiles/install`が非 Darwin ホストで`/etc/docker/daemon.json`等へ sudo で書き込むことが判明した。NixOS ホスト（p1/x1/g2/tr）は`virtualisation.docker.daemon.settings`という NixOS 標準の宣言的オプションで、既に`/etc/docker/daemon.json`相当を完全にネイティブへ翻訳・生成していた（`nix/hosts/tr/virtualization/docker.nix`のコメントに「Settings translated from /etc/docker/daemon.json」と明記）。

Make 側の`dockers/daemon.json`と NixOS 側の手動翻訳版を突き合わせたところ、両者は既に部分的に乖離していた（`max-concurrent-downloads`が10 vs 24、`builder.gc.defaultKeepStorage`が20GB vs 50GB、`storage-driver`/`experimental`/`selinux-enabled`の有無、`default-ulimits`のキー大文字小文字、`dns`の参照先設定キーなど）。特に tr の`dns = settings.network.dnsmasqServers`は、`nix/core/settings.nix`のコメントで「現在 NetworkManager/Docker では使用されていない」と明記された非推奨値を参照しているバグだった（p1/x1/g2 側は正しく`settings.network.dockerDns`を参照している）。

## 2. 決定推進要因

- Driver 1: Docker daemon の実効設定（同時実行数・GC 容量・ネットワーク設定等）は、genuine Arch Linux ホストと NixOS ホストで意図的に変える理由がなく、同じ値であるべき。
- Driver 2: 2箇所の手書き JSON/Nix 翻訳を今後も手で同期し続けるコストと、既に発生していた乖離（tr の DNS 設定バグを含む）を解消したい。
- Driver 3: NixOS の`/etc`宣言的管理と Make の生の`sudo cp`/`ln`が同じパスを取り合うことを避けたい（ADR-0002 Q7 で発見）。

## 3. 検討された選択肢

- **Option 1**: `dotfiles/install`の`/etc/docker/*`書き込みを NixOS では単純にスキップするだけに留め、値の乖離自体は別途扱う。
- **Option 2 [Selected]**: `dockers/daemon.json`を実行時に稼働中の値（tr の調整値）を正として更新し、単一ソースとする。genuine Arch Linux は Make が引き続きこのファイルを`/etc/docker/daemon.json`へ配置し、NixOS 側（`nix/modules/nixos/virtualization/docker.nix`・`nix/hosts/tr/virtualization/docker.nix`）は`builtins.fromJSON (builtins.readFile ...)`で同じファイルを読み込んで`daemon.settings`のベースにする。OS/ホスト固有の差異（DNS の解決元、gVisor ランタイムパス）だけを各プラットフォームの正しい機構で個別に載せる。
- **Option 3**: gVisor（`runtimes.runsc/runu`）も含め完全に1つのJSONへ統合し、NixOS側にもgVisorパッケージを追加する。NixOS側でgVisorが実際に必要かどうか未確認のままスコープを広げることになるため見送った。

## 4. 決定結果と根拠

Option 2 を選択した。

- 稼働中の Threadripper（tr）のチューニング値（`max-concurrent-downloads/uploads`=24、`shutdown-timeout`=10、`builder.gc.defaultKeepStorage`=50GB、`storage-driver`=overlay2、`experimental`=true、`selinux-enabled`=false、`default-ulimits`の`Name`/`Hard`/`Soft`表記）を正として`dockers/daemon.json`に反映した。
- `features`は Docker API 上`containerd-snapshotter`と`buildkit`が独立した併用可能なフラグのため、両方を共有 base に含めた。
- `dns`は JSON の値と`settings.network.dockerDns`の解決値が実質同一であることを確認した上で、将来 DNS プロバイダを変更した際に Nix 側の全消費者が自動追従できるよう、Nix 側では JSON の値を信頼せず`settings.network.dockerDns`で明示的に上書きする（tr の`dnsmasqServers`参照バグはこの上書きで是正される）。
- `runtimes.runsc/runu`（gVisor、`/usr/local/bin/*`）は共有 JSON から除外した。NixOS は`/usr/local/bin`スタイルのパスを使わない慣行であり、NixOS 側のどのホストも現時点で gVisor をパッケージしていないため、genuine Arch Linux 向けにのみ`Makefile.d/install.mk`側で`jq`によるマージを行い、`/etc/docker/daemon.json`へ書き込む直前に追加する。

## 5. 不変条件と影響

### 正の影響 (Positive Consequences)

- Docker daemon 設定の実効値が genuine Arch Linux と NixOS の全ホストで一致する。
- tr の DNS 設定バグ（未使用の`dnsmasqServers`参照）が是正された。
- 今後の設定変更は`dockers/daemon.json`一箇所で完結する（DNS プロバイダ変更は`nix/core/settings.nix`、gVisor ランタイムパス変更は`Makefile.d/install.mk`のみ例外）。

### 負の影響・トレードオフ (Negative Consequences)

- tr の docker daemon の実効設定が本 ADR 適用前と後で変わる（p1/x1/g2 も同様に`buildkit`+`containerd-snapshotter`両方が有効になる等の変化がある）。`make nix/switch`適用後、稼働中コンテナ・ビルドキャッシュへの影響をホスト側で確認する必要がある。
- genuine Arch Linux 側の`/etc/docker/daemon.json`は、`DEPLOY_FUNC`によるシンボリックリンクから、`jq`でマージした内容を書き込む方式に変わった（symlink ではなく実体ファイルになる）。

### システム不変条件 (Invariants)

- **Invariant-1**: `dockers/daemon.json`は Docker daemon 設定の唯一の共有ソースである。genuine Arch Linux 固有の追加（`runtimes.runsc/runu`）と NixOS 固有の上書き（`dns`）は、それぞれのプラットフォームの正しい機構（Make の`jq`マージ／Nix の`//`演算子によるオーバーライド）でのみ行い、共有 JSON 自体には混ぜない。
- **Invariant-2**: NixOS ホストでは`dotfiles/install`が`/etc/docker/*`・`/etc/containerd/*`への書き込みを行わない（`[ -f /etc/NIXOS ]`ガード）。

## 6. 検証方法

```sh
# genuine Arch Linux 側でマージ後の内容を確認（ドライラン、実際には書き込まない）
jq '. + {"runtimes": {"runsc": {"path": "/usr/local/bin/runsc"}, "runu": {"path": "/usr/local/bin/runu"}}}' dockers/daemon.json

# NixOS 側の最終的な daemon.settings を確認
nix eval --impure --json "./nix#nixosConfigurations.tr.config.virtualisation.docker.daemon.settings" | jq .
nix eval --impure --json "./nix#nixosConfigurations.p1.config.virtualisation.docker.daemon.settings.dns"

# 全 NixOS ホストの評価・依存グラフ解決
make nix/test/eval
make nix/test/dry-run NIX_HOST_NAME=tr
make nix/test/dry-run NIX_HOST_NAME=p1
make nix/test/dry-run NIX_HOST_NAME=x1
make nix/test/dry-run NIX_HOST_NAME=g2
```
