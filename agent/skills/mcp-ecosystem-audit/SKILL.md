---
name: mcp-ecosystem-audit
description: MCP (Model Context Protocol) 2026-07-28 仕様(ステートレス化・initialize ハンドシェイク廃止・server/discover 必須化・MRTR・Tasks 拡張・Roots/Sampling/Logging 非推奨化)に照らして、`~/.claude/settings.json` の `mcpServers`(および各プロジェクトの `.mcp.json`)に登録済みの MCP サーバー群の追従状況を棚卸しする軽量参照 skill。
trigger: /mcp-ecosystem-audit
---

# MCP エコシステム棚卸し — 2026-07-28 仕様準拠チェック

## When to Activate

- MCP 仕様の更新告知(公式ブログ・changelog)を見かけたとき
- `mcpServers` に新規サーバーを追加する前後
- 半期に一度程度の定期棚卸し
- 特定の MCP サーバーで `list changed` 通知が来ない・`roots`/`sampling` 系ツールが動かない等、
  仕様差異が疑われる不具合の切り分け時

**境界(重要 — 「read-only」は設定の閲覧にのみ適用される)**: 本 skill が read-only を保証するのは
`~/.claude/settings.json`/`.mcp.json` の**閲覧**（§2）と、認証を伴わないローカルサーバーの
**probe**（§3 の `codegraph`/`filesystem`/`memory`/`lsp-rust`）に限られる。`docker run` で起動する
`k8s`/`slack` 等、実クラウド/ワークスペースへ**実際に認証接続する**サーバーの probe は「read-only な
棚卸し」の範囲外であり、§3 で個別に人間確認を要求する（harness-design.md「外部送信を含む skill は
user 承認後に追加する」に整合させるため）。`mcpServers` を実際に書き換える設定変更作業自体は本 skill
では行わない — Claude Code 組み込みの `update-config` skill（本リポジトリの `claude/skills/` 配下には無い —
セッションのスキル一覧に "settings.json/settings.local.json ファイルへの変更全般" 用として現れる
CLI 同梱の標準 skill。実在は Claude Code セッション自身のツール一覧から確認できるが、リポジトリの
grep だけでは検出できない点に注意）へ引き継ぐ。SKILL.md/hooks 自体の改訂提案は `swarm-evolve` の管轄。

**既存 skill との関係**: `security-scan` も同じ `mcpServers`/`.mcp.json` を対象にするが観点が異なる
（`security-scan` はリスクのあるサーバー・secret 直書き・supply chain risk を検出するセキュリティ監査、
本 skill は MCP プロトコル仕様バージョンへの追従状況を確認する準拠監査）。両者は独立に実行してよく、
優先順位はない — 設定変更前にはむしろ両方を通すことを推奨する。

## 1. 2026-07-28 仕様で何が変わったか

出典: [MCP 公式 changelog](https://modelcontextprotocol.io/specification/2026-07-28/changelog)
(前版 2025-11-25 との差分)、[MCP 公式ブログ](https://blog.modelcontextprotocol.io/posts/2026-07-28/)、
[Claude 公式ブログ(Claude 側の追従)](https://claude.com/blog/bringing-mcp-2026-07-28-to-claude)。
下記の表は 2026-08-26 に公式 changelog を直接 WebFetch し「Major changes」項目1-9・「Deprecated」項目1-3
と逐語照合済み(GraSP 5分類とは異なり pilot/未検証ではなく一次ソース確認済みの内容)。

| 変更                                                      | 内容                                                                                                                                                                                                                                                                     | Transport 依存性                                                             |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| ステートレス化                                            | `initialize`/`notifications/initialized` ハンドシェイクを廃止。各リクエストが `_meta` に `io.modelcontextprotocol/protocolVersion`・`clientCapabilities` 等を都度添付する                                                                                                | **transport 非依存**(stdio 含む全 transport に適用)                          |
| `Mcp-Session-Id` ヘッダ・protocol-level sessions 廃止     | Streamable HTTP transport からヘッダ自体を除去                                                                                                                                                                                                                           | Streamable HTTP transport 固有(stdio には元々存在しないヘッダなので影響なし) |
| `server/discover` 新設                                    | サーバーは対応 protocol version・capabilities・identity を返す RPC を **MUST** 実装。「STDIO 上での後方互換プローブとしても使える」と明記                                                                                                                                | **stdio でも明示的に言及**されている必須 RPC                                 |
| MRTR (Multi Round-Trip Requests)                          | `roots/list`/`sampling/createMessage`/`elicitation/create` 等のサーバー起点リクエストの**送り方**を、`resultType: "input_required"` → クライアントが `inputResponses` を添えて元リクエストを再送する方式に置換。下記の Roots/Sampling 非推奨化と両立する関係(下記注参照) | transport 非依存                                                             |
| Tasks 拡張                                                | experimental だった tasks を `io.modelcontextprotocol/tasks` 拡張として正式化。`tasks/result` のブロッキング待受を廃し `tasks/get` ポーリング + `tasks/update` に置換                                                                                                    | サーバーが拡張を実装している場合のみ関係(任意)                               |
| `ping`/`logging/setLevel`/`roots/list_changed` 通知の削除 | ログレベルはリクエスト単位の `_meta` フィールドに移行。ログは stdio では stderr へ出力するのが仕様上の推奨                                                                                                                                                               | transport 非依存                                                             |
| Roots/Sampling/Logging **機能自体**の非推奨化             | 12ヶ月の deprecation window 付き(SEP-2577)。**deprecation 期間中は引き続き完全に機能する**が新規実装は非採用が推奨。移行先: Roots→tool引数でパス指定、Sampling→LLM provider APIへ直接統合、Logging→stderr/OpenTelemetry                                                  | サーバー実装依存                                                             |
| HTTP+SSE transport の Deprecated 再分類                   | `2025-03-26` 時点で既に非推奨だったものを正式に Deprecated 状態へ                                                                                                                                                                                                        | Streamable HTTP 系のみ(stdio 無関係)                                         |

> **MRTR と Roots/Sampling 非推奨化の関係(内部矛盾に見えるため明記)**: 上記表の「MRTR」行と
> 「Roots/Sampling/Logging 機能自体の非推奨化」行は同じ`roots`/`sampling`を指すが矛盾しない。
> MRTR(SEP-2322)は「サーバー起点リクエストをどう送るか」という**トランスポート層の再設計**であり、
> Roots/Sampling 自体の存続可否とは別軸。Roots/Sampling は Deprecated ではあるが deprecation window 中は
> 完全に機能し続けるため、その間に実際に roots/sampling を使うサーバーは新形式(MRTR)経由でやり取りする。
> 「新規実装が roots/sampling に依存すべきでない」ことと「既存の roots/sampling 呼び出しが MRTR という
> 新しい配線に乗る」ことは両立する。なお `elicitation/create` は Deprecated リストに含まれない
> (MRTR で配線が変わるのみで機能自体は非推奨化されていない)。
> 出典: [MCP 公式 changelog](https://modelcontextprotocol.io/specification/2026-07-28/changelog)
> 「Major changes」項目7・「Deprecated」項目1を2026-08-26にWebFetchで直接照合。

## 2. 対象インベントリの洗い出し

以下のコマンドで棚卸し対象を機械的に列挙する(推測せず実測する — `verify-before-assert.md` 準拠)。
出力には `env`/`headers` 等の secret を含みうるフィールドが含まれる可能性があるため、値ではなく
キー名のみを表示する(下記スクリプトは `env`/`headers` の値のみを意図的に伏せる — `args`/`url` 等の
他フィールドに secret が直書きされる MCP サーバー設定もありうるため、それらは本スクリプトの保証範囲外
であり目視確認が必要)。

```bash
# グローバル設定(全プロジェクト共通) — env/headers の値は伏せてキー名のみ表示する
python3 -c "
import json
d = json.load(open('$HOME/.claude/settings.json'))
servers = d.get('mcpServers', {})
for name, cfg in servers.items():
    redacted = dict(cfg)
    for secretish in ('env', 'headers'):
        if secretish not in redacted:
            continue
        val = redacted[secretish]
        # dict形状(env/headersの通常の形)以外(list等、KEY=VALUE文字列の配列形式で書く
        # 設定もありうる)は個別キーの列挙ができないため丸ごと伏せる。isinstance判定を
        # 省くと、dict内包表記がlistの各要素(KEY=VALUE文字列)をキーとして扱ってしまい、
        # 値側だけ伏せて元のKEY=VALUE文字列がキーとしてそのまま出力される
        # (2026-08-26 敵対的レビューで実証済みの回避経路。この段落はpython3 -cのbash二重引用符
        # の内側にあるためダブルクォート文字そのものを含めない — 含めると出現数の偶奇に
        # 挙動が依存する壊れやすい構造になる、2026-08-26 敵対的レビュー finding LOW-1)。
        redacted[secretish] = (
            {k: '<redacted>' for k in val} if isinstance(val, dict)
            else '<redacted:non-dict-shape>'
        )
    print(name, json.dumps(redacted, ensure_ascii=False))
"

# プロジェクトローカルの .mcp.json(存在すれば追加でリストする)
find "$HOME/go/src/github.com/kpango" "$HOME/go/src/github.com/vdaas/vald" -maxdepth 2 -iname ".mcp.json" 2>/dev/null
```

現行のサーバー一覧・起動方式は dotfiles `CLAUDE.md` の「## MCP Servers」節が正の情報源
(single source of truth)であり、本 skill では二重管理しない。上記コマンドの出力とその節の記述が
食い違っていたら、`CLAUDE.md` 側の更新漏れとして扱い(このリポジトリの `DOTFILES_MAP`/`claude/install`
配線で `~/.claude/CLAUDE.md` へ反映される)、本 skill 側では個別サーバーの版・pinning 実態を都度
実測する — 「`:latest` タグでも `--pull=missing` 併用時は自動追従しない」のような pinning の実態は
`CLAUDE.md` の表からは読み取れないため、疑わしい場合は当該サーバーの起動コマンド定義
(`args`/`command`)を直接確認する。

## 3. サーバー単位の準拠チェック手順

`server/discover` は 2026-07-28 で新設された RPC のため、これに応答するサーバーは新仕様側、
`initialize` にしか応答しないサーバーは旧仕様(〜2025-11-25)側にいると判定できる。

**対象は現時点で §2 の実測により env/headers に secret を持たないと確認済みの4サーバーに限る**
（`codegraph`/`filesystem`/`memory`/`lsp-rust`）。「認証を伴わないローカルサーバー」という性質だけでは
不十分である点に注意 — ローカル完結のツールでもライセンスキー等を env で要求する場合がありうるため、
新しい5番目のサーバーを追加する際は、この4件と同列に扱う前に必ず §2 のコマンドで当該サーバーの
`env`/`headers` を再確認し、secret が無いことを実測してから本節の対象に加えること(確認前に
「ローカル完結だから安全だろう」と推測で対象へ加えない)。これらは stdio へ素朴な JSON-RPC 1 行を
送るだけで probe できる:

```bash
# 例: 認証を伴わないローカル stdio MCP サーバーのみに使う(k8s/slack には使わない — 後述)。
# §2 で実測したとおりこの4サーバーの設定には env/headers による secret が無いため、stderr は
# 伏せ字化せずそのまま表示する(「secret 形状パターンを正規表現で網羅的に伏せる」試みは、
# 2026-08-26 の敵対的レビューで3ラウンドにわたり回避経路が実証され続けた — スキーム名を変える、
# 区切り文字をJSON/タブに変える、キーワード語彙を変える、のいずれでも新しい回避経路が見つかった。
# 任意形式の自由文字列から secret を機械的に redact することは一般に信頼できないため、
# 「redact して見せる」のではなく「secret が原理的に存在しない対象にだけ生ログを見せる」設計に
# 倒す — 認証情報を持つ k8s/slack には本関数を使わず、後述の probe_credentialed_server_status を使う)。
probe_mcp_server() {
  local cmd=("$@")
  local errlog
  errlog="$(mktemp)"
  trap 'rm -f "$errlog"' RETURN
  echo "--- server/discover probe ---"
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{}}' \
    | timeout 15 "${cmd[@]}" 2>"$errlog" | head -1
  echo "--- initialize (legacy handshake) probe ---"
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2026-07-28","capabilities":{},"clientInfo":{"name":"mcp-ecosystem-audit","version":"0"}}}' \
    | timeout 15 "${cmd[@]}" 2>>"$errlog" | head -1
  # MCP は stdio 上でログを stderr へ出す仕様(上記 §1 参照)。判定分岐3(無応答/タイムアウト)を
  # 誤診断しないため stderr はそのまま表示する(この4サーバーに限り secret を含まない前提のため)。
  if [ -s "$errlog" ]; then
    echo "--- stderr(このサーバーは §2 実測どおり secret を扱わないため伏せ字化しない) ---"
    cat "$errlog"
  fi
}

# 例: codegraph
probe_mcp_server codegraph serve --mcp
```

判定の読み方(いずれも実行結果を Read してから断定する。事前に決め打ちしない):

- `server/discover` に妥当な JSON-RPC 応答(`protocolVersion` を含む)が返る → 2026-07-28 系に追従済み
- `server/discover` が `Method not found` 相当のエラーを返し、`initialize` には正常応答する → 旧仕様のまま
- 両方無応答/タイムアウト → 上記 stderr を確認する。`bunx` の registry 解決はコールドスタートで 15 秒に
  近づくことがあるため、starvation かプロセス起動自体の問題かを切り分けてから `debugger`/`ci-investigator`
  へ引き継ぐ(timeout 値のみを機械的な判定根拠にしない)。

**`k8s`/`slack`(実クラウド/ワークスペースへ認証接続するサーバー)は上記 `probe_mcp_server` の対象に含めない。**
これらの起動コマンド(`docker run ... -v ~/.kube:...:ro ... quay.io/manusa/kubernetes_mcp_server` /
`docker run ... -e SLACK_BOT_TOKEN ...`)を実行すると、実際の Kubernetes クラスタ・Slack ワークスペースへ
本物の認証情報で接続が確立する — これは設定ファイルの閲覧ではなく外部システムへの実接続であり、
`harness-design.md`「外部送信を含む skill は user 承認後に追加する」の対象になる。この 2 種を probe する
必要がある場合は、(a) 本 skill を人間が明示的に `/mcp-ecosystem-audit` で起動した会話の中で、
(b) 「k8s/slack へ実接続してよいか」を個別に人間へ確認してから、(c) 下記の**専用関数**を使う:

```bash
# k8s/slack 専用。stdout/stderr の生内容は一切 Claude のコンテキストへ表示しない
# (secret-shaped パターンの網羅的 redaction は上記のとおり一般に信頼できないため、
# 「redact して見せる」のではなく「そもそも生ログを Claude の会話に載せない」設計)。
# 判定材料は exit code と出力の有無のみに限定する — 生ログの目視確認が必要な場合は
# 人間が自分の端末で直接同じコマンドを実行して確認する(エージェント経由で見せない)。
#
# **この関数が守るのは応答内容のみであり、呼び出しコマンド自体は守らない**: 下記の呼び出し例を
# 書く際、secret の実際の値を `-e VAR=<値>` の形でコマンドライン上に literal に書いてはならない
# (書いた時点でその値は Bash ツール呼び出し=会話トランスクリプトに残ってしまい、本関数の
# 出力抑制の範囲外で漏洩する)。`~/.claude/settings.json` の実際の slack/k8s エントリ自体が
# 既にこの安全な形になっている: secret を運ぶ変数(`SLACK_BOT_TOKEN` 等)は値なしの `-e VAR` 形式
# (呼び出し元シェルの環境変数を docker が継承する)。値つき `-e VAR=<値>` が実際に使われているのは
# `KUBECONFIG=/home/user/.kube/config` のようにそれ自体は secret ではない値(パス等)に限られる。
# 呼び出し時は `~/.claude/settings.json` の args 配列を過不足なくそのまま展開すること
# (`--cap-drop=ALL`/`--security-opt no-new-privileges`/`--read-only` 等のハードニングフラグも含む —
# 省略すると弱い設定のコンテナで実クラスタ/ワークスペースへ接続することになる)。
probe_credentialed_server_status() {
  local cmd=("$@")
  local out rc
  out="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{}}' \
    | timeout 15 "${cmd[@]}" 2>/dev/null)" || rc=$?
  rc="${rc:-0}"
  if [ -n "$out" ]; then
    echo "server/discover: 応答あり(2026-07-28系に追従済みの可能性 — 内容は表示しない。"
    echo "  詳細確認が必要なら人間が自分の端末で同じコマンドを直接実行して目視すること)"
  elif [ "$rc" -eq 124 ]; then
    echo "server/discover: タイムアウト(15s) — 無応答"
  else
    echo "server/discover: 無応答またはエラー(exit=$rc、内容は表示しない)"
  fi
}

# 例: k8s(2026-08-26時点の ~/.claude/settings.json 実エントリを過不足なく展開したもの。
# secret を運ぶ変数が無いため k8s には値つき引数のみで安全に書ける — slack を呼ぶ場合は
# `-e SLACK_BOT_TOKEN`(値なし)のように settings.json の実際の書き方をそのまま踏襲すること)
probe_credentialed_server_status docker run --rm -i --pull=missing --cap-drop=ALL \
  --security-opt no-new-privileges --pids-limit 256 --read-only --network host \
  --user 1000:1000 --tmpfs /tmp:rw,noexec,nosuid,nodev \
  -v ~/.kube:/home/user/.kube:ro -e KUBECONFIG=/home/user/.kube/config \
  quay.io/manusa/kubernetes_mcp_server:latest
```

**この境界の現状の技術的裏付け(既知の限界)**: 上記の「k8s/slack には専用関数のみ使う」という区別は
prose 規範であり本 skill 自体に機械強制は無い。現時点では `permission-request.sh` の docker 自動承認
allowlist(`docker (ps|logs|inspect|images|stats|version|info)`)に `run` が含まれないため、生の
`docker run` は(`probe_mcp_server`/`probe_credentialed_server_status` どちらを使う場合でも)通常の
対話的権限確認を経る — これが実質的な追加の安全弁になっている。**この allowlist を将来 `docker run` を
含む形へ広げる場合は、本 skill のこの節を再レビューしてから行うこと**(安全弁が暗黙に失われる経路のため)。

## 4. 実装依存の追加チェック項目

- **Roots/Sampling/Logging 非推奨への依存**: 各サーバーの README/ソースで `roots/list`・
  `sampling/createMessage`・`logging/setLevel` の使用有無を確認する。`lsp-rust`(LSP ブリッジ)は
  ファイルパスのやり取りに Roots を使っている実装がある点に留意し、実際に使用しているかは
  ソースを確認してから断定する。
- **HTTP+SSE transport 依存**: `CLAUDE.md` の現行構成は全件 stdio のため、現時点で該当なし
  (`type: "sse"` や HTTP エンドポイントを持つサーバーを新規追加する場合のみ再評価)。
- **Tasks 拡張**: 長時間実行ジョブ(大規模インデックス再構築等)を持つサーバー(`codegraph` の
  再インデックス処理等)が旧来のブロッキング待受のままか、`io.modelcontextprotocol/tasks` 拡張の
  ポーリング方式に対応済みかは、当該サーバーの changelog を個別に確認する。

## 5. 発見事項の扱い

- 設定変更(`mcpServers` の再構成、`docker pull` の定期実行、`go install`/`npm install -g` の
  再実行)が必要と判明した場合は、本 skill では実行せず Claude Code 組み込みの `update-config` skill、
  または通常の Bash 操作(読み取り専用の棚卸し範囲を超えるため人間の承認を経る)へ引き継ぐ。
- `CLAUDE.md` の「## MCP Servers」表の記載が実態(起動コマンド・pinning 実態)と食い違っていた場合は、
  その更新自体を発見事項として報告する(本 skill の対象範囲は棚卸しの実行であり `CLAUDE.md` の
  直接編集ではない — Tier B 保護ファイルであり通常の承認フローに従う)。
- SKILL.md/hooks 側の恒久的なルール変更(例: 「MCP サーバー追加時は必ずこの棚卸しを走らせる」を
  `CLAUDE.md` や別 skill のトリガー条件に組み込む等)が有用と判断した場合は、本 skill 自身が
  直接編集せず `swarm-evolve` への提案として起票する。
- 本 skill は監査手順書であり実装作業を持たないため、他の言語/技術別 skill(golang-patterns 等)と
  異なり専用の Expert Agent へは委譲しない — 発見事項の解釈・優先順位づけは上記のとおり
  `update-config`/人間承認フロー/`swarm-evolve` のいずれかへ個別に振り分ける。

## References

- MCP 公式 changelog (2026-07-28): https://modelcontextprotocol.io/specification/2026-07-28/changelog
- MCP 公式ブログ: https://blog.modelcontextprotocol.io/posts/2026-07-28/
- Claude 公式ブログ(Claude 側の 2026-07-28 追従): https://claude.com/blog/bringing-mcp-2026-07-28-to-claude
