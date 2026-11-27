# Pi Agent Harness 30 技術 — 一次情報リサーチ・ダンプ

- 対象 PDF: `plans/pi-agent-improvement.pdf`（2026-11-21、earendil-works/pi v1.6.0 時点）
- 本ファイルの役割: **各技術を個別に一次情報へ当て、PDF の主張・上流機構・報告値・実装要件・
  ローカル証拠・採用判定を 1 技術 1 節で固定する**。実装状況の一覧は
  `agent/context/pi30-applicability.md`、実装は各 task の worktree が持つ。
- 表記:
  - `[arXiv abstract]` = `https://arxiv.org/abs/<id>` の title/abstract を 2026-11-22 に取得して確認。
  - `[上流 repo]` = 上流リポジトリ/README/コードを確認（scout 取得を含む）。
  - `[PDF のみ]` = PDF にしか無い数値・主張。独立再現・一次ページ未確認。
  - `[repo]` = この dotfiles worktree のコードを確認（file:line）。
  - 数値は**条件（モデル・ベンチ・split）を落とさない**。条件不明の数値は採用根拠にしない。
- 判定区分: `完全導入` / `部分導入` / `保留` / `不採用`。`完全` は「PDF の機構と検証可能な
  中核がローカルに存在し、決定論的テストで固定されている」場合だけ使う。

## 0. 先に結論（誤りの多い順）

1. **#21 Harness² の「完全導入」は誤り**。`harness2-offline.py:49-52` 自身が
   rollout/probe・improve・selection・judge を `NOT PORTED` と明記している。ローカルにあるのは
   「決定論的オフライン部分」（trace 入力・cluster・C1-C8 写像・tree 検証・delta≤0・held-out・
   EXPERIENCE 追記・bwrap gate）だけ。`完全` → `部分` へ訂正する。
2. **#5 Hashline の根拠引用が誤り**。PDF は arXiv:2607.12713 を Hashline 編集の根拠に使うが、
   この論文は **R 言語のコードレビューコメントを行アンカー+引用にする HAIC 形式**の研究で、
   エージェントの edit ツールではない。PDF の「Opus 22% / Sonnet 58% / 24–80%」も上流の
   output token −14.7% / −50.5%、hosted cost −20.0% / −46.3% へ**過大**。Hashline 自体は
   OMP ホストの `edit.mode` として実在するが、根拠は差し替える。
3. **#8 LongHorizon の「トークン24%削減」は上流に無い**。上流は OSWorld 出力 token
   28.9K→104K と**増加**を報告し、backbone 別では Qwen 10.7M→34.3M（増）、Opus 16.5M→11.1M
   （−33%）と方向が分かれる。スコア（WeaveBench 51.8→80.7、TB2.1 69.7→77.2）だけを引用する。
4. **#6 と #9 が同じ 66.5% を別手法として二重帰属**している。どちらも一次ページ未取得の
   二次情報で、少なくとも一方は誤り。両行の「実証済み」を撤回する。
5. **Harness² の `EXPERIENCE.md` の「component C3」と「Net Token Budget conservation law
   (Harness²)」は上流仕様ではない**。上流 README の 8 component は system prompt, guardrails,
   memory, tool guidance, subagents, skills, scripts, plugins で、c1–c8 の番号・名称は無い。
   ローカル発明を上流仕様として提示しているため、出所表示を訂正する。
6. **#11 RLM は「完全導入」ではない**。`repl-context-core.ts:29` は 100 KiB 超の出力傍受、
   `:55-63` は depth=1 の bounded map-reduce。永続 REPL 変数・再帰サブ LLM ではない。
7. **#18 Advisor は既定 off**。`config.yml:52-53` の `prewalk.enabled` は false、Advisor は
   受動設定のみ。PDF 自身が「effort 増と同等」と結論しているため、`完全` は過大。

---

## Tier S（PDF #1–#5）

### #1. KV-cache prefix 維持 + block Observation Masking（PACT）

- **一次情報**: arXiv:2611.12122（Agency、2026-11-09）[arXiv abstract]、arXiv:2508.21433
  （The Complexity Trap、JetBrains、SWE-bench Verified）[arXiv abstract]。PACT は ACL ARR
  投稿で arXiv 未上程（PDF の書誌のみ）[PDF のみ]。
- **PDF の主張**: Anthropic 2026 実測でプロンプトキャッシュが総コストの 53–73%、同 model で
  最大 2.6×。Agency は harness 間挿で 5 最適化、cost ratio 0.77（−23%）/最大 −35%、
  accuracy ratio 0.97。masking は SWE-agent でコスト半減・要約と同等、hybrid で更に −7%/−11%。
- **中核機構**: (a) prefix を不変に保ち cache read を最大化、(b) 古い observation を LLM 要約
  せず**単純に落とす**（block masking）、(c) 必要なら hybrid（masking + 要約）。
- **定量**: PDF の「200 タスク」は誤り。Agency の Table 1 は **100 タスク**（TB2 20 +
  SWE-bench 40 + Pro 40）[上流 repo/scout]。23%/35%/0.97/53–73%/2.6× は一次と一致。
  PACT の 28 step/2.7 edit/0.56 vs 0.46、Anthropic 2.5–3.7×・83/88%、Dor Amir 2.64× は
  **未確認**。
- **実装要件**: prefix 安定性（system prompt + tool schema + 古い observation の位置を動かさない）、
  observation の block 単位 mask、cache hit の計測、mask と要約の A/B。
- **ローカル**: ObservationPack が 10 KiB 超を archive し、2 provider request は full、3 回目
  以降は handle + excerpt（`sol-pi-core.ts` の `projectObservation`、`sol-pi.test.ts:1182`）。
  これは masking と同方向だが、**prefix cache の明示維持・cache hit 計測・Agency の 5 最適化は
  無い**。`validate-harness.sh` は `sol-pi.json` の ObservationPack 有効を固定。
- **判定**: `部分導入`（ObservationPack が masking の近似。prefix 維持は host 依存）。
- **次の一手**: 数値の「200→100 タスク」を訂正。PACT を根拠に使うなら ACL ARR の一次を
  取得するまで「未確認」と明記。cache hit の計測は host の usage に依存するため保留。

### #2. SoL-Pi — Action Fusion / ObservationPack / Evidence-Preserving Reducer / Online Context Compact

- **一次情報**: arXiv:2609.20519 v1（NVlabs、MIT、2026-09-17）[arXiv abstract]、
  `github.com/NVlabs/SoL-Pi` [上流 repo]。PDF の「SoL-Pi 2」「Blender demo」は v1 に無い
  [PDF のみ]。
- **PDF の主張**: EdgeBench 51 タスクで token −44.7〜49.0%、API cost 約 1/3、Efficiency 点
  1.10B vs 2.1538B（−49.0%）で 93.7% 保持（42.0 vs 44.8）、$1,339 基準で cost −33.2%。
  Action Fusion は「12.3% の projected token 減」。
- **中核機構**（論文 §2.4、HTML で確認）:
  1. **Action Fusion**: mutation と follow-up command を 1 tool request に統合し、中間の
     model round trip を消す。mutation 結果の inspection が必要な command は分離。
  2. **Online Context Compact (OCC)**: `update_plan` の step 完了境界で、完了 step 間の
     request 数と未完了 step 数から残 request を見積もり、context window を埋める request 数で
     cap。**input 節約の projection と prompt cache rewrite コストを比較**し、後続 compaction
     では未回収 rewrite コストも加味して margin を大きくする。gate 通過時のみ Pi native
     compaction を呼ぶ。
  3. **ObservationPack**: 10 KiB 超を local archive。**次の 2 provider request は full**、
     3 回目以降は stable handle + original size + 完全な head/tail 行の短い excerpt。agent は
     handle で exact page を取得。小さい結果は不変。
  4. **Evidence-Preserving Reducer (EPR)**: 4 KiB 以上の build/test log を対象（file read /
     search は bypass）。exact output を archive し、**安価な model** に schema/source hash/
     exit status/exact quote/size を検証させる。検証失敗・credential 疑い・削減なしは
     original へ fallback。ObservationPack は receipt marker を見て skip。
- **定量の訂正**: Action Fusion の **12.3% は誤り。論文は 11.5%**（full triggering 時の
  projected token 減）[上流 HTML/scout]。2.15B→1.10B、1339、93.7%、42.00/44.83、10 KiB、
  535 環境/152 方向/27 反復は一致。所属「NTU」は未確認。
- **実装要件**: tool request への follow-up 統合、plan step 完了イベント、cache rewrite の
  economics、archive の安定 handle、receipt schema と exact-quote 検証、fallback。
- **ローカル**: `sol-pi.json` で actionFusion/observationPack/evidencePreservingReducer が true、
  `onlineContextCompact` は **false**（opt-in）。`sol-pi-core.ts:2506` 以降は上流
  `economics.ts` の**逐語ポート**（remainingRequestScale/StddevK、cooldown、cache debt）。
  Action Fusion は host の edit tool が strict のため `then_run` を model に露出できず、
  `defaultValidators` による post-edit 自動実行が実効経路。EPR は**安価な model ではなく
  決定論的抽出器**（失敗行・quote・location）で、fallback 時に excerpt + archive pointer を返す。
- **実装監査の確定事項（2026-11-22 scout）**:
  - `then_run` は **dead code**。ホストの edit/write schema は `strict`（closed）で
    （`pi-coding-agent/dist/types/edit/index.d.ts:33`、`dist/types/tools/write.d.ts:43`）、
    `sol-pi.ts:1120,1208` は `update_plan`/`obs_recall` のみ登録するため、モデルは
    `then_run` を送れない。`sol-pi.ts:488-513` の fused 経路は到達不能で、
    `sol-pi.test.ts` の `sol-pi.ts: then_run wiring` テストは input を直接注入するため dead を検出しない。
    → 「同一 tool request への融合」ではなく「**validator 追記のみ**」と記載する。
  - ObservationPack の archive は**原文ではない**。秘密を redact し、行を 512B cap、
    512 KiB 超は head+tail のみ保存する（`sol-pi-core.ts:559-560,646-655,708`）。
    `obs_recall` は redact 済み秘密・落とした中間部を復元できない（可逆ではない）。
  - `barrier` は強制ブロックではない。共有ブロックは result への
    `<action-fusion-validation-failed>` 追記と次 bash での警告のみ（`sol-pi.ts:435-437`）。
  - `sol-pi.json` が無い/JSON 不正のとき `DEFAULT_CONFIG` が全機構 enabled に倒れ、
    EPR は anthropic へ送信し得る（`sol-pi-core.ts:148-203`）。配布ファイル前提の既定値と明記。
  - OCC の `maxCompactionsPerSession` は **host 主導/manual compaction も数える**。
    `0` は無制限（`sol-pi-core.ts:2445-2460`）。`tokenPressureThreshold` は advisory 専用。
  - `fullReplayTurns` は **request 数ではなく assistant message 数**（`sol-pi-core.ts:1552-1558`）。
  - `session_switch`/`session_clear` は archiveDir を再解決していなかったため、別 cwd へ
    `/resume` した際に旧 session dir の handle を指し `obs_recall` が不発見になり得た。T2 で
    `sol-pi.ts` の両ハンドラに再解決を追加し、`sol-pi.test.ts` の
    `session_switch re-resolves the archive dir` / `session_clear re-resolves the archive dir` で固定した
    （旧 handle は previous session dir に残り missing）。
- **判定**: `部分導入`。OCC は実装済みだが既定 off、EPR は LLM 抽出ではなく決定論 substitute。
  これは「忠実でない」ではなく「意図的な安全側 substitute」として文書化する。
- **次の一手**: T2 で論文の数値・順序・fallback を conformance test に固定済み（358 pass、`SPEC DEVIATION` をテスト内に明記）。docs の 12.3% を
  11.5% に訂正。EPR の「lower-cost model」差分を明記。

### #3. 段階的開示 Agent Skills + lazy/proxy tool discovery

- **一次情報**: arXiv:2602.12670 **v1**（SkillsBench）[arXiv abstract]、v4 は別数値
  [arXiv abstract]。`agent/context/pi-techniques-30.md` は既に記号定義を持つ [repo]。
- **PDF の主張**: SkillsBench は 11 ドメイン 84 タスク・7,308 軌跡、curated Skills で
  **+16.2pp**、self-generated は平均無効。Tool Search で 85% 削減（7.2–7.7万→8.7K）、
  4,000 ツール時に 30–64% 劣化。
- **一次の現行値**: v1 abstract は **86 タスク / 11 ドメイン / 7 config / 7,308 軌跡、
  33.9→50.5（+16.6pp、25.5% normalized）**、config 別 +4.1〜+25.7pp、**3 module 以下の
  focused Skills が長い Skills より優位**。v4 は 87 タスク / 8 ドメイン / +16.6pp。
  **PDF は v1 を引用している**ため、引用は `2602.12670v1` を明示する。
- **中核機構**: SKILL.md は name/description/path だけ常時露出し、一致時のみ本文を読む
  (progressive disclosure)。tool も同様に deferred/proxy し、必要時だけ schema を展開。
- **実装要件**: 常時ロードされる description の token 予算、発火条件の明示、本文の遅延読込、
  tool schema の遅延展開、発火しなかった skill の計測。
- **ローカル**: `agent/skills/*/SKILL.md` は description を常時提示し、必要時に本文を読む。
  `test-catalog-health.sh` が frontmatter と 160 文字制限を機械検証。tool 側は OMP の
  native tool 登録 + `repl_filter` の出力フィルタで、**Tool Search の完全な proxy 展開は無い**。
- **判定**: `部分導入`（skills は完全、tool discovery は部分）。
- **次の一手**: 文献表記を v1 に固定。84/11/+16.2 と 86/11/+16.6 の差を注記。

### #4. Pi Codemode / programmatic tool calling (PTC)

- **一次情報**: npm `@earendil-works/pi-codemode@1.6.0`（MIT、quickjs-wasi 3.6.2）[上流 repo]。
- **PDF の主張**: 唯一の capability が注入ツール呼び出しである sandboxed JS で、filter/集約後の
  結果だけ返す。5,300→3,300（37.7%）、PTC 43,588→27,297（37%）、GIA 46.5→51.2、
  入力 −24% / score +11% [PDF のみ]。
- **中核機構**: モデルに「ツールを呼ぶコード」を書かせ、sandbox 内で実行。ループ・分岐・
  集約をモデル round trip なしで行い、最終結果だけを context に返す。
- **実装要件**: sandbox（WASM/quickjs 等）、tool capability の注入、出力サイズ上限、
  失敗時の fallback、監査ログ。
- **ローカル**: OMP ホストの `eval` は `PY|JS` セルで状態がターン/セッションを跨いで持続し
  （`dist/types/tools/eval.d.ts:9-25`）、prelude に `agent()` と `tool.*` プロキシを持つ
  （`src/eval/backend.ts`、`preludes.txt:621`）＝ PTC の実体はある。ただし **サンドボックス
  ではない**（JS は Bun Worker + `vm.createContext`、PY は同一 UID の subprocess）。
  repo に codemode の指示・利用は無く（grep 0 件）、`config.yml` に `eval:` セクションも無い。
  専用 Codemode 拡張は未導入。数値は未確認。
- **判定**: `保留`（ホスト所有機能。repo で再実装しない）。
- **次の一手**: ホストの `eval` で `tool.*` が使えることを docs に明記。数値は引用しない。

### #5. Hash-anchor 編集（Hashline）

- **一次情報**: OMP ホストの `dist/types/edit/settings.d.ts` の `EDIT_MODES` に `hashline`
  [ホスト schema]。arXiv:2607.12713（Lamberti）は **Hashline の論文ではない**
  [arXiv abstract]。arXiv:2510.14972（TokDrift）は tokenizer 頑健性の研究 [arXiv abstract]。
- **PDF の主張**: 行アンカーで探索置換 O(S+R) を O(R) にし、Claude Opus 22% / Sonnet 58%
  （100 行超で 24–80%）の生成トークン削減とパッチ正答率向上。
- **一次の実態**: 2607.12713 は **R 言語のコードレビューコメントを FileMark（行アンカー+
  引用）で渡す** HAIC 研究。36 合成 R タスク × 7 model で **output token −14.7%（Opus）/
  −50.5%（Sonnet）**、total token −4.2〜+14.7%、100 行超の hosted cost **−20.0% / −46.3%**。
  anchor 誤配置で正確性は急落。**PDF の 22/58/24–80 は過大で、機構の帰属も誤り**。
- **中核機構**（Hashline 自体）: 編集対象行に内容ハッシュ付きアンカーを付け、モデルは
  アンカー + 置換内容だけを返す。行番号や探索文字列の再送を不要にし、stale anchor を弾く。
- **実装要件**: アンカー生成、stale/mismatch 検出、fuzzy match、編集後の再アンカー、
  失敗時の fallback（read + 再編集）。
- **ローカル**: ホストの既定値が `edit.mode = "hashline"`（`src/edit/settings.ts:19-48`、
  `cfgEditMode.default = "hashline"`）、read/search/write が内容タグを発行するセッション
  ストア（`src/edit/store.ts:1-7`）、hashline 分岐と schema（`src/edit/index.ts:157-158,410-411`）。
  dotfiles は `config.yml:38-41` で `mode: hashline`、`fuzzyMatch: true`、
  `fuzzyThreshold: 0.92` を固定し、`validate-harness.sh:30` が値を検証する。
  `vald-guard.ts:32-44,332` は実入力 `[PATH#TAG]`/`MV` を解析し、`vald-guard.test.ts:247-258`
  が形式を固定。`pi-hashline-context-edit`（隣接行をハッシュに含める派生）は未導入。
- **判定**: `完全導入`（**ホスト機能として**）。ただし **PDF の数値・引用は不採用**。
- **次の一手**: T5 でホスト schema と設定解決を検証。applicability の根拠を
  「2607.12713」から「ホスト `EDIT_MODES` + OMP docs」へ差し替え。

---

## Tier A（PDF #6–#12）

### #6. Middleware guardrail + 環境オンボーディング + mid-run steering

- **一次情報**: LangChain 2026-02-17 発表 [PDF のみ]。一次ページは取得不能（scout の
  docs/検索が失敗）。4 middleware は LocalContext / PreCompletionChecklist / LoopDetection /
  Time Budgeting + Pi Steer。
- **PDF の主張**: gpt-5.2-codex 固定で TB2.0 52.8→66.5（+13.7、30 位圏外→トップ5）。
- **中核機構**: 起動時に cwd 構造・tool path を自動探索して context に注入（onboarding）、
  pre-completion checklist、loop detection、time budget、実行中の steer。
- **定量**: **未確認**。同じ 66.5% が #9 の Reasoning Sandwich の最高値としても使われており、
  二重帰属。少なくとも一方は誤り。
- **実装要件**: 起動時 onboarding の token 上限、決定論的 pre-completion gate、loop 検出、
  予算、steer の注入点。
- **ローカル**: `stop-verify.ts` が session_stop 前に決定論的検証を強制（5 回上限 + waiver）、
  `security-gate.ts` が書込前 gate、`auto-memory.ts`、`rtk-optimizer.ts`。onboarding は
  `AGENTS.md`/`SYSTEM.md` の静的注入で、自動探索ではない。
- **判定**: `部分導入`（gate は強いが、LangChain の 4 middleware と 66.5% は未確認）。
- **次の一手**: 「実証済み」を撤回し、66.5% を引用しない。

### #7. リアルタイム LSP / 静的解析 / テスト feedback

- **一次情報**: npm `pi-lens@4.5.1`（`--lens-guard` は opt-in commit guard）[上流 repo]、
  arXiv:2602.03411 §5（SWE-Master の `lsp_tool`）[arXiv abstract/scout]。
- **PDF の主張**: pi-lens は write/edit/turn-end にフックし、常駐 LSP、Impact Cascade、
  formatter/linter、ast-grep。SWE-Master §5 の `lsp_tool` は入力 −23.7% / 出力 −16.3%、
  resolve 61.0 vs 61.4（劣化なし）。
- **中核機構**: 編集直後に型・semantic 診断を返し、逆依存ファイルへ影響を伝播。テスト/lint を
  決定論的 feedback として同じ turn に返す。
- **実装要件**: LSP 常駐、delta diagnostic、impact cascade、formatter/linter、失敗時の
  fail-open、診断の truncation。
- **ローカル**: `lsp.yml` の gopls/rust-analyzer、`post-edit-lint.sh`（Claude/Agy）、
  `test-omp-extensions.sh` の syntax check。**Agy の post-edit hook は診断を破棄する既知欠陥**
  （`agent/hooks/agy/` は保護対象のため本ミッションでは修正しない）。
- **判定**: `完全導入`（OMP/Claude は実効。Agy は既知欠陥を別途修正）。
- **次の一手**: Agy の診断破棄を別ミッション/承認済み変更として起案。

### #8. 外部化タスク状態 + 独立監査ループ

- **一次情報**: arXiv:2608.01964 v1（LongHorizon-Harness、AMAP-ML、MIT）[arXiv abstract]、
  `github.com/AMAP-ML/LongHorizon-Harness` [上流 repo]。
- **PDF の主張**: 状態を会話外へ完全外部化し、Manager（状態保持/次の有界ステップ）、
  fresh-context Executor、read-only Auditor の MEA loop。Qwen3.7-Plus で WeaveBench
  51.8→80.7、TB2.1 69.7→77.2、OSWorld2.0 2.8→8.3。**「トークン24%削減」**。
- **一次の実態**: スコアは一致。**「24%削減」は上流に存在しない**。OSWorld 出力 token は
  28.9K→104K と増加、backbone 別では Qwen 10.7M→34.3M（増）/ Opus 16.5M→11.1M（−33%）。
- **中核機構**: `@fix_plan.md` 等の外部状態、fresh-context executor、read-only auditor、
  状態更新は環境で独立検証された事実のみ。
- **実装要件**: 状態ファイルのスキーマ、executor の毎回 fresh context、auditor の read-only
  権限、検証済み事実だけの更新、完了判定の分離。
- **ローカル**: `mission-bridge.ts` が `@fix_plan.md` を authoritative にし、`swarm-graph` が
  node ごとに fresh context の Maker/Checker を割当。`stop-verify.ts` が完了を gate。
- **判定**: `完全導入`（機構は一致。トークン削減の主張だけ削除）。
- **次の一手**: docs から「24%削減」を削除し、スコアのみ引用。

### #9. 動的推論予算（Reasoning Sandwich）+ model/harness 切替

- **一次情報**: ブログ/社内報告のみ（LangChain / Databricks / Anthropic guide）。
  **arXiv・査読論文なし** [PDF のみ]。
- **PDF の主張**: TB2.0 で全 xhigh 53.9%、全 high 63.6%、sandwich（計画 xhigh → 実装 high →
  検証 xhigh）66.5%。Databricks: Opus 4.8 max 82%/$3.60 vs high 85%/$0.93、xhigh 90%。
  GPT-5.5 medium=xhigh 79.5% でコスト 2×。
- **中核機構**: 局面ごとに effort を切り替え、model 別の system prompt preset を当てる。
- **定量**: **未確認**。66.5% は #6 と衝突。`model-system-prompt` 拡張の実在も未確認。
- **実装要件**: task ごとの effort 指定、phase 遷移、model 別 preset、失敗時の昇降格。
- **ローカル**: `thinking-budget.ts` が reasoning effort を制御、`config.yml` の `modelRoles`
  が 10 role、`task.enableEffort` 経由。`prewalk.enabled` は false。
- **判定**: `部分導入`（機構はあるが、数値根拠は無い）。
- **次の一手**: 数値を引用しない。effort の phase 切替を運用で検証するまで「実証済み」にしない。

### #10. LCM — 階層要約 DAG + invariant store + `llm_map`

- **一次情報**: arXiv:2605.04050 v1（Ehrlich & Blackman）[arXiv abstract]。
- **PDF の主張**: Immutable Store + Active Context、Fresh Tail 保護、Depth 0–2 の Summary
  DAG、3 段エスカレーション、`lcm_grep/expand`、`llm_map`/`agentic_map`。OOLONG
  trec_coarse で Opus 4.6(+Haiku 4.5) 平均 74.8 vs 70.3（+4.5）、1M で +51.3 vs +47.0。
- **一次の実態**: 平均 74.8 vs 70.3、8K 13.1 vs 11.2 / 16K 26.3 vs 25.0（負け）、32K 以上で
  勝ち、256K +10.0、512K +12.6、1M +4.3（51.3 vs 47.0）。**PDF の「+51.3 vs +47.0」は
  Volt vs Claude Code の 1M 値**で、素の Opus 4.6 比ではない（素の Opus は +29.2 vs +24.7）。
- **中核機構**: immutable store、active context の Fresh Tail、階層 summary DAG、
  deterministic な 3 段エスカレーション、grep/expand、`llm_map`。
- **実装要件**: immutable store、DAG の depth 管理、Fresh Tail の token 予算、escalation、
  検索/展開 API、決定的な map。
- **ローカル**: 線形 compaction（`keepRecentTokens`）のみ。DAG・invariant store・
  `llm_map` は無い。`sol-pi-core.ts` の OCC は economics のみ。
- **判定**: `保留`（実装コスト大。LCM の DAG を入れるなら独立ミッション）。
- **次の一手**: docs の 1M 比較を「Volt vs Claude Code」と明記。

### #11. RLM — 永続 REPL + context variables

- **一次情報**: arXiv:2512.24601（Zhang, Kraska & Khattab）[arXiv abstract]、
  arXiv:2608.23552（Prime Agent）[arXiv abstract]、`github.com/manojlds/pi-rlm` [上流 repo]。
- **PDF の主張**: prompt-as-a-variable、Python で slice/inspect、サブタスクを再帰的に別 model
  へ関数呼び出し。Prime Agent は ARC-AGI-3 95.5% RHAE Best@1 / 99.97% Best@3、
  9 評価 8 勝。Composio で 1.4M tok/task・$0.131・62.5%。
- **一次の実態**: RLM は 2 桁長い入力、compaction 比 +26%、CodeAct 比 +130%（GPT-5 中央値）。
  Prime Agent の 95.5% は PDF/scout の報告で、arXiv abstract には ARC-AGI-3 の数値は無い
  （abstract は機構の記述）。数値は「PDF のみ」扱い。
- **中核機構**: 永続 REPL に prompt を変数として置き、モデルが code で slice/inspect、
  子 RLM を再帰呼び出し。子は独自カーネル/セッション木。
- **実装要件**: 永続カーネル、変数の生存、再帰深度、出力上限、sandbox、子の隔離。
- **ローカル**: `repl-context.ts` が >100KB 出力をメモリ退避し、`repl_filter` で
  slice/filter/head/tail、`rlm_map_reduce` で depth=1 の bounded map-reduce。**変数の生存・
  コード実行・再帰委任は無い**。`repl_query` は既定で offline `stub` backend を使い
  （`repl-context.ts:289`）、`RLM_BACKEND=exec` + `RLM_BACKEND_CMD` で model backend に切り替わる
  （`repl-context-core.ts:67`、`rlm-deep-audit/SKILL.md:19-27`）。RLM 相当の能力はホスト `eval`
  （永続カーネル + `agent()` 再帰）にあるが、dotfiles はそれを指示・設定していない。バッファは
  in-memory でセッション終了時に消える。`sol-pi.ts` の ObservationPack は別物。
- **判定**: `部分導入`（**完全ではない**）。docs の「完全」を訂正。
- **次の一手**: `rlm_map_reduce` の depth=1 と永続性なしを明記。深い再帰は host 依存で保留。

### #12. ローカル semantic code search + tree-sitter graph/AST 編集

- **一次情報**: arXiv:2610.05099（ColGrep-Agent-2B）[arXiv abstract]、arXiv:2603.27277
  （Codebase-Memory）[arXiv abstract]、`ast-grep`、trail MCP [上流 repo]。
- **PDF の主張**: Tree-sitter 35 言語、LateOn-Code-edge 17M の INT8 量子化、MaxSim 検索、
  13 repo/624 session で tok −34.3%（142K→93K）、cost −40%、turn 5.5→3.9、正答 80.8 vs
  83.3、latency 13.0→21.6s、Line F1 19.92。
- **一次の実態**: Codebase-Memory は 31 repo で 83% vs 92%、10× fewer tokens、2.1× fewer
  calls。ColGrep の数値は PDF のみ（abstract には性能値が無い）。
- **中核機構**: tree-sitter の構造 graph、local embedding の semantic search、2B 検索 agent、
  AST 構造編集。
- **実装要件**: tree-sitter index、embedding、検索 agent、AST 編集の安全境界。
- **ローカル**: `ast-grep-bridge.ts` の AST 検索、`ast_edit`、trail MCP の graph。
  **embedding index は無い**。`trail` は tree-sitter ベースの graph を提供。
- **判定**: `不採用`（embedding/2B 検索はコスト・依存が大きく、trail + ast-grep で足りる）。
- **次の一手**: なし（trail MCP の graph を維持）。

---

## Tier B（PDF #13–#24）

### #13. ツリー型セッション分岐 + 隔離 branch/handoff

- **一次情報**: Pi の JSONL セッション（`id`/`parentId`、`navigateTree`）[上流 repo]、
  OMP ホストの `/tree`・`/fork` [ホスト]。`pi-review` の空 branch 機構は v2.9.x で削除済み
  [上流 repo]。
- **PDF の主張**: id/parentId で分岐し、fork で元会話を汚さず、レビュー用の空 branch を持つ。
- **中核機構**: session node の木、branch 切替、fork 時の親 chain 複製、worktree との対応。
- **実装要件**: node id、parent 参照、branch 切替、fork の会話/コード同時復元、handoff。
- **ローカル**: ホストが `/tree`（分岐切替）と `/fork`（pane/window/tab）を持つ
  （`builtin-session.ts:682-687,648-680`、`session_before_branch` に `reason:"fork"`、
  `src/extensibility/shared-events.ts:63`）。repo の `session-tree.ts:156-198` の `/checkpoint` は HEAD を JSON 保存、
  `/cp-rewind` は `store.activeId` 更新と `git reset --soft` の**案内だけ**で、コードも会話も
  戻さない。`git-checkpoint.ts:90-112` は `session_before_fork` を購読していたが、**ホストに
  そのイベント型は無い**（正は `session_before_branch`）ため dead handler だった。
  T5 で `session_before_branch` + `reason:"fork"` guard に修正し、host check が PASS。
- **判定**: `部分導入`（会話分岐はホスト所有。repo 側の fork 復元は host check で検証）。
- **次の一手**: `/cp-rewind` の非復元性を help に明記するかは別途判断。

### #14. 隔離サブエージェント委任 + 専門チームファクトリ

- **一次情報**: Anthropic multi-agent research system（2025-06-13、+90.2%、
  token 15×）[PDF のみ]、npm `pi-subagents@0.14.2`（995,303 DL）[上流 repo]。
- **PDF の主張**: 独立 context の並列 subagent が単一 agent を +90.2% 上回る。team factory が
  役割を自動生成。
- **中核機構**: 独立 context、並列 fan-out、役割別 tool 制限、結果の親への集約、worktree 隔離。
- **実装要件**: delegated agent の定義、並列上限、tool capability の付与、結果の要約、失敗の隔離。
- **ローカル**: `subagents.ts` が single/parallel/chain/DAG と worktree 割当を実装。
  `agent/agents/*.md` は静的 roster で、**team factory（役割の自動生成）は無い**。
  `mapToolNames()` が capability 由来の tool 集合を正規化。
- **判定**: `部分導入`（**完全ではない**）。静的 roster と自動生成を混同しない。
- **次の一手**: なし（team factory はモデル依存の設計。必要になったら独立ミッション）。

### #15. Copy-on-Write worktree + マイクロ VM 隔離

- **一次情報**: Gondolin（`github.com/gondolin/gondolin`）[上流 repo]、bwrap、Anthropic
  sandboxing（2026-10-20）[PDF のみ]。SandboxEscapeBench 15–35% は研究プレプリント
  [PDF のみ]。
- **PDF の主張**: CoW で worktree 作成を高速化し、microVM で agent を隔離。Anthropic は
  承認 84% 減。
- **中核機構**: CoW overlay、microVM、network deny-by-default、credential を VM 外に保持。
- **実装要件**: CoW ファイルシステム、VM 起動、network policy、危険コマンドの gate、fallback。
- **ローカル**: `sandbox-run.ts` が Gondolin/bwrap を起動し、`config.yml` の
  `isolation.sandboxRun` で制御。`worktree-core.ts` は `git worktree add` で、**CoW ではない**
  （git の worktree はファイルを複製する）。microVM はホスト側の `sandbox_run` に委譲。
- **判定**: `部分導入`（sandbox は実装、CoW worktree は未実装）。
- **次の一手**: CoW は git の制約が大きく、必要になるまで保留。

### #16. 可観測性駆動トレース診断 + 反証可能ハーネス進化（AHE）

- **一次情報**: arXiv:2604.25850 v1（AHE）[arXiv abstract]。
- **PDF の主張**: editable 7 component の file-level 表現、experience observability、
  change manifest、counterfactual loop。TB2 69.7→77.0、GPT-5.5 84.7±2.1、transfer
  +5.1〜10.1。prompt-only 編集は悪化。
- **一次の実態**: 3 observability pillar（component / experience / outcome）と
  counterfactual loop は PDF と一致。数値は PDF のみ（abstract に個別値なし）。
- **中核機構**: 各 component をファイルに写像し、生 trace を signature でクラスタし、
  candidate を held-out で比較し、改善分だけを manifest で適用する。
- **実装要件**: component 写像、trace 収集、signature、held-out、change manifest、
  counterfactual comparison、rollback。
- **ローカル**: `harness2-offline.py` が trace 収集・クラスタ・C1–C8 写像・tree 検証・
  delta≤0 拒否・held-out・EXPERIENCE 追記・bwrap gate を実装。change manifest は
  **`file_path` のみ**（AHE の component-level manifest の subset）。`mission-bridge.ts` が
  deterministic failure を trace として供給。
- **判定**: `導入済み（AHE の subset）`。manifest の範囲を「file_path subset」と明記。
- **次の一手**: T3 の `--capabilities` で component-level manifest が未実装であることを表明。

### #17. ツール出力サンドボックス隔離 + 事前フィルタ（context-mode）

- **一次情報**: npm `context-mode@1.0.111`（Elastic-2.0）[上流 repo]、SQLite FTS5 [上流]。
- **PDF の主張**: MCP firewall が 376KB→16.5KB（96%）、構造 98% / 文書 82%、window
  22.7%→1.3%。
- **中核機構**: 全 tool 出力を SQLite FTS5 に索引し、モデルには pointer と必要断片だけを返す。
  BM25 で検索。
- **実装要件**: tool 出力の intercept、FTS5 index、BM25、pointer 解決、削除/保持 policy。
- **ローカル**: ObservationPack が 10 KiB 超をファイル archive + handle 化し、`obs_recall` で
  ページ取得。検索はプロセス内の regex/substring 走査で、**FTS5/BM25 index は無い**。
  なお FTS5 自体は既にプロンプト履歴で稼働している（`history-storage.ts:207-209`）ため、
  不採用理由を「SQLite 依存」にしてはならない。正しい理由は「**tool 出力索引の設計が無い**」。
- **判定**: `部分導入`（ObservationPack は近似。FTS5/BM25 の索引は無い）。
- **次の一手**: docs の不採用理由を訂正。索引導入は独立ミッション（保持 policy の設計が必要）。

### #18. 役割別モデルルーティング + Executor/Advisor ハイブリッド

- **一次情報**: Anthropic Advisor tool（2026-10-09、public beta）[PDF のみ]。
- **PDF の主張**: Executor（Sonnet 4.6 / Haiku）が Advisor（Opus 4.6）へ相談。Sonnet+Opus で
  +2.7pt / −11.9% cost、Haiku+Opus BrowseComp 19.7→41.2%（−85% cost、精度 −29%）、
  Opus5+Fable5 85.7 vs 84.4（cost 2.1×）。**PDF 自身が「effort 増と同等」と結論**。
- **中核機構**: 実行 model と相談 model を分け、必要な局面だけ強い model を呼ぶ。
- **実装要件**: role 別 model、advisor 呼び出しの trigger、cost gate、fallback。
- **ローカル**: `config.yml` の `modelRoles` が 10 role、`thinking-budget.ts` が effort を制御。
  **`prewalk.enabled` は false**、Advisor は受動設定のみで、実行時に advisor を呼ぶ配線は無い。
- **判定**: `部分導入`（**完全ではない**）。ルーティングはあるが hybrid 協調は既定 off。
- **次の一手**: 「完全導入」を撤回。advisor を有効化するなら cost/精度の実測が先。

### #19. RRSI — 正則化再帰自己改善ハーネス探索

- **一次情報**: arXiv:2609.24972 v1（RRSI）[arXiv abstract]。
- **PDF の主張**: worktree 分離、annealing、leak critic で OOD +4.3 / ID +6.0、token −30%。
- **中核機構**: 反復ごとにハーネスを変異・選択し、正則化で過適合を抑える。
- **実装要件**: 変異空間、評価セット、正則化、leak 検査、rollback。
- **ローカル**: 無し。OMP ホストの ratchet は無効。
- **判定**: `不採用`（研究段階。評価基盤と計算予算が無い）。
- **次の一手**: なし。

### #20. Meta-Harness — 生トレース駆動のオフライン最適化

- **一次情報**: arXiv:2603.28052 v1（Meta-Harness）[arXiv abstract]。
- **PDF の主張**: agentic proposer が source/scores/traces を filesystem で読み、+7.7pt、
  context token 1/4。TB2 76.4%（Opus 4.6）、Haiku 37.6%、math +4.7、ACE +7.7、
  11.4K vs 50.8K。
- **一次の実態**: 数値は PDF のみ。機構（filesystem 上の candidate 探索）は一致。
- **中核機構**: candidate の source/score/trace を保存し、proposer が過去全てを読んで次を提案。
- **実装要件**: candidate store、score、trace、proposer、held-out、採用 gate。
- **ローカル**: `harness2-offline.py` が trace 収集・クラスタ・held-out・Experience 追記を担う。
  proposer は LLM ではなく決定論的変換。
- **判定**: `部分導入`（決定論 subset。LLM proposer は無い）。
- **次の一手**: T3 の capabilities に「proposer は決定論」と明記。

### #21. Harness² — ラベルフリー2階層再帰ハーネス自己改善

- **一次情報**: arXiv:2610.14224 v1（Harness²）[arXiv abstract]、`github.com/.../harness2`
  [上流 repo]。
- **PDF の主張**: 8 component、label-free の rollout/probe/selection/experience。
  WorkBuddy +11.5、JobBench +4.5、LAB +11.8、tool error −36.8%、4–20 runs/task。
- **一次の実態**: 数値は PDF のみ。上流の 8 component は system prompt, guardrails, memory,
  tool guidance, subagents, skills, scripts, plugins で、**c1–c8 の番号・名称は無い**。
  ローカルの「C1–C8」写像と「component C3 = EXPERIENCE.md」は**ローカル発明**であり、
  上流仕様として提示してはならない。「Net Token Budget conservation law (Harness²)」も
  上流に無い（SWARM の予算則）。
- **中核機構**: 2 階層（harness 全体 → component）の再帰改善。rollout で candidate を試し、
  probe で失敗 signature を取り、selection で採用し、experience を蓄積する。
- **実装要件**: rollout 実行、probe、selection、judge、experience store、rollback、予算。
- **ローカル**: `harness2-offline.py:49-52` が **rollout/probe・improve・selection・judge を
  `NOT PORTED`** と明記。実装は決定論的オフライン部分（trace 入力・cluster・C1–C8 写像・
  tree 検証・delta≤0・held-out・EXPERIENCE 追記・bwrap gate）のみ。`--capabilities` は offline deterministic subset と NOT PORTED を返す（18 checks で固定）。
- **判定**: `部分導入`（**「完全導入」は誤り**）。T3 で `--capabilities` を追加し、
  未移植段階を機械可読に表明する。
- **次の一手**: docs の「完全」を「部分（offline deterministic subset）」へ訂正。
  C1–C8 は「ローカル写像」と明記。

### #22. クロスセッション永続セマンティック/エピソード記憶

- **一次情報**: `qmd`（`github.com/.../qmd`）、`pi-memory`、Mem0（arXiv:2504.19413、
  LoCoMo 92.5 / 5,000 会話）[PDF のみ]、Ori-Mnemos（arXiv:2603.19987）[PDF のみ]。
- **PDF の主張**: 意味検索 + エピソード記憶でセッションを跨ぐ。Mem0 は LoCoMo 92.5。
- **中核機構**: embedding index、episode store、検索、注入、忘却/保持。
- **実装要件**: embedding、index、検索 API、保持 policy、privacy。
- **ローカル**: `search_sessions` は JSONL を mtime 降順で走査（埋め込みなし）。
  `memory.backend` は `local` で、`recall`/`retain`/`reflect`/`memory_edit` は
  hindsight/mnemopi 限定のため**登録されない**（`memory-recall.ts:34-37` 他）。
  `local-backend.ts:42-44` が `searchable:false` を明記。`learn` → `learned.md` 追記と注入、
  `.trail/learnings/`（markdown）のみ。
- **判定**: `部分導入`（**semantic ではない**）。docs の「semantic」を削除。
- **次の一手**: なし（embedding は Out of Scope）。

### #23. RAH — Recursive Agent Harnesses

- **一次情報**: arXiv:2606.13643 v1（RAH）[arXiv abstract]。
- **PDF の主張**: 親 script が子ハーネスを大量に spawn。Oolong-Synthetic で Codex
  71.75→81.36、RLM 64.38、Sonnet 4.5 89.77、4M token 超で 76%。
- **中核機構**: harness を「子を spawn する script」として扱い、再帰的に並列化する。
- **実装要件**: spawn API、並列上限、結果集約、コスト制御、失敗隔離。
- **ローカル**: `swarm-graph` が node ごとに Maker/Checker を割当、`SWARM.md` が人間承認と
  並列上限を規定。**数千の並列 spawn はしない**（意図的な安全側）。
- **判定**: `部分導入`（機構は近似。スケールは意図的に制限）。
- **次の一手**: なし。

### #24. 永続化・イベントソーシング型 Durable ランタイム

- **一次情報**: `github.com/.../pi-durable`、SQLite event log [上流 repo]。
- **PDF の主張**: crash 後の replay、zero-copy fork、multi-user、監査。
- **中核機構**: append-only event log、snapshot、replay、idempotency、fork。
- **実装要件**: event schema、snapshot、replay、idempotency、multi-user 分離。
- **ローカル**: append-only JSONL の軌跡ログと idempotency（`idempotency.ts`）はあるが、
  **full replay / multi-user / zero-copy fork は無い**。
- **判定**: `部分導入`（イベント記録のみ）。
- **次の一手**: なし（ホストの session 永続化に依存）。

---

## Tier C（PDF #25–#30）

### #25. ベンチマーク駆動・自律実験ループ（pi-autoresearch）

- **一次情報**: `github.com/.../pi-autoresearch`、Liquid AI PR #2056 [PDF のみ]。
- **PDF の主張**: measure/checks、keep/revert、統計的信頼度 ≥2.0（3 run）。120 実験 /
  93 commit / 974 test、parse+render −52.7%、parse −61%、alloc −60.8%。**未マージ**。
- **中核機構**: 仮説 → 変更 → measure → keep/revert のループを自動化する。
- **実装要件**: benchmark harness、統計、keep/revert、CI、失敗の rollback。
- **ローカル**: `goal_loop` は predicate ベースの反復のみで、benchmark の measure/keep/revert
  は無い。
- **判定**: `保留`（評価基盤が前提。dotfiles 単体では導入しない）。
- **次の一手**: なし。

### #26. モデル駆動・可逆インクリメンタル圧縮プロキシ（billion-context）

- **一次情報**: `github.com/.../billion-context` [上流 repo]。
- **PDF の主張**: 30× 可逆圧縮、cache hit 95–97%、1.48M で 199/199、ContextBench F1
  0.31 vs 0.29、cost −58%、LongMemEval 79.2、NIAH 69→27%。
- **中核機構**: プロキシで圧縮し、必要時に展開する。cache を壊さない。
- **実装要件**: proxy、圧縮/展開、cache、整合性、失敗時の fallback。
- **ローカル**: プロキシは無い。ObservationPack は非可逆（redact/cap）。
- **判定**: `不採用`（NIAH 69→27 の劣化が示す通り、長文の精密検索と両立しない）。
- **次の一手**: なし。

### #27. 学習済みマルチモデル集合知 + 検証付き TTS

- **一次情報**: Sakana AI Fugu（2026-06-22）[PDF のみ]、TRINITY（arXiv:2512.04695）
  [PDF のみ]、Conductor（arXiv:2512.04388）[PDF のみ]。
- **PDF の主張**: Fugu Max $2/$6、Chartography 48.3 vs Opus5 27.3、DeepSWE 74.3。
  TTS 61.4→70.8→76.2。
- **中核機構**: 学習済みオーケストレータが model を選択/合成し、検証器が出力を選ぶ。
- **実装要件**: 独立 model の集合、router、verifier、cost 管理。
- **ローカル**: `consensus-verifier.ts` は**決定論的ヒューリスティックの pre-screen**で、
  独立 model の合議ではない。`/consensus` も同じ。
- **判定**: `保留`（**「部分導入」ではない**）。外部 model 集合と学習 router が無い。
- **次の一手**: docs の「部分導入」を「保留（pre-screen のみ）」へ訂正。

### #28. 軽量オンライン CRUD 自己適応ハーネス（Continual Harness /refine）

- **一次情報**: arXiv:2607.08959 [PDF のみ]、`pi-continual-harness` [上流 repo]。
- **PDF の主張**: H=(ρ,G,K,M) の CRUD、背景 async、ID rollback。独立検証が無く
  reward hacking の危険。
- **中核機構**: ハーネス構成をファイルとして CRUD し、実行中に更新する。
- **実装要件**: component store、CRUD、async refine、ID rollback、人間承認、監査。
- **ローカル**: `continual-harness.ts` が `harness_refine`/`refine` を実装し、
  apply を分離して人間承認を要求。独立した性能検証は無い（上流も無い）。
- **判定**: `完全導入`（**概念として**。独立性能証拠は無い）。
- **次の一手**: reward hacking 対策（apply 分離・承認）を維持。

### #29. クロスハーネス・メタオーケストレーション + ガバナンス（Omnigent）

- **一次情報**: Databricks Omnigent（2026-06-13、Apache-2.0）[PDF のみ]。
- **PDF の主張**: YAML 1 行で harness/model を差し替え、Polly（別 worktree + 別 vendor の
  クロスレビュー）、Debby（`/debate`）、policy/governance。alpha、ベンチ無し。
- **中核機構**: メタハーネス層、クロスレビュー、議論、ポリシー統制。
- **実装要件**: harness adapter、cross-review、debate、quota/policy、監査。
- **ローカル**: `sync-manifest.json` + `sync-verify.sh` が 4 harness の配線を検証、
  `bridge-hermes.ts` が Hermes へ委譲。**quota/policy governor と debate は無い**。
- **判定**: `部分導入`（配線検証のみ。ガバナンス層は無い）。
- **次の一手**: docs の「近似」を維持し、quota/policy は未実装と明記。

### #30. インプロセス・ネイティブツール実行 + サブプロセス排除

- **一次情報**: OMP の Rust コア + libuv、brush-shell、in-process ripgrep、syntect、pi-ast
  [ホスト]、Prime Agent v0.10.2 の Rust 移行 [上流 repo]、`sol-pig` [上流 repo]。
- **PDF の主張**: fork/exec を排除し、数千ファイル探索でミリ秒高速化。Composio で OMP は
  272.4 秒（最遅、Pi 132.2 秒）。
- **中核機構**: シェル・grep・構文解析・AST を同一プロセスで実行する。
- **実装要件**: in-process 実装、互換性、メモリ、クラッシュ隔離、fallback。
- **ローカル**: `session-search.ts` は native `registerTool` を持つが、`ast-grep-bridge.ts`・
  `cli-bridge.ts`・`consensus-verifier.ts`・`repl-context.ts` は**サブプロセス**。
  全面書き換えはしていない。
- **判定**: `不採用`（PDF 自身が「OMP は最遅」と書いており、「本番適用可」と矛盾する。
  書き換えコストに対して効果が不明）。
- **次の一手**: なし。

---

## 横断分析

### A. Harness Tax（拡張の累積劣化）

- PDF は「Pi に 31 以上の拡張を積むと劣化する」と報告する [PDF のみ]。OMP は約 42 の
  extension を持ち、このリスク域にある。
- ただし本ミッションでは extension を削除しない（Out of Scope）。代わりに
  `validate-harness.sh` / `test-omp-extensions.sh` の決定論的検証を維持し、拡張ごとの
  tool/token 影響を計測できる状態にする。
- **次の一手（別ミッション）**: extension ごとの常時ロード token と tool schema の
  サイズを一覧化し、四半期ごとに監査する。

### B. モデル特化ハーネス切替

- PDF は「最適構成は model 依存」とし、model 別 preset を主張する [PDF のみ]。
- OMP は `modelRoles`（10 role）と `models.yml` で routing を抽象化済み。preset の
  自動切替は未実装だが、`thinking-budget.ts` で effort は制御できる。
- **判定**: `部分導入`。数値根拠が無いため preset の自動生成はしない。

### C. Claude / Agy への適用

- **共有 SSoT**: `agent/context/pi30-primary-research.md` と `pi30-applicability.md` は
  repo 内 SSoT であり、各ハーネスの `$HOME` へは配線しない（参照するには repo パス指定が必要）。
  本ミッションで追加した共有スクリプトはホスト能力検証の 1 本のみ。
- **Claude**: Stop hook は `agent/harnesses/claude/settings.json` で**プロジェクトスコープ
  意図的**（`$CLAUDE_PROJECT_DIR`）。`post-edit-lint.sh` は診断を返す。
- **Agy**: `agent/hooks/agy/` の post-edit hook は診断を破棄する既知欠陥があるが、
  `hooks/*.sh` は保護対象のため本ミッションでは変更しない。別ミッションで承認を得て修正する。
- **共通の注意**: PDF の数値・arXiv 番号の誤り（#5, #8, #6/#9, #10, #21）は全ハーネスに
  共有されるため、本 dossier の訂正を SSoT とする。

### D. PDF の主要な誤り（一次情報との差分）

| #   | PDF の主張                                     | 一次情報                                                                         | 対応       |
| --- | ---------------------------------------------- | -------------------------------------------------------------------------------- | ---------- |
| 1   | Agency 200 タスク                              | **100 タスク**（TB2 20 + SWE 40 + Pro 40）                                       | 訂正       |
| 2   | Action Fusion 12.3%                            | **11.5%**（full triggering 時の projected）                                      | 訂正       |
| 5   | 2607.12713 = Hashline、22%/58%/24–80%          | 2607.12713 = **R コードレビュー HAIC**、output −14.7%/−50.5%、cost −20.0%/−46.3% | 引用差替え |
| 6/9 | 66.5% を別手法に二重帰属                       | 一次未取得                                                                       | 数値撤回   |
| 8   | 「トークン24%削減」                            | 上流に無い（OSWorld 出力は増加）                                                 | 削除       |
| 10  | 1M で +51.3 vs +47.0                           | それは **Volt vs Claude Code**。素の Opus は +29.2 vs +24.7                      | 条件明記   |
| 21  | Harness²「完全導入」、C3、Net Token Budget law | 上流は 8 component・c1–c8 無し。ローカル実装は offline subset                    | 訂正       |

### E. 次に採用するなら（優先順）

1. **T2/T3 の conformance test**（本ミッション）: SoL-Pi と Harness² の「実装が主張通りか」を
   機械的に固定する。これは新機能より優先。
2. **#16 AHE の component-level manifest**（中コスト）: 現在は `file_path` のみ。
3. **#24 durable runtime の replay**（中コスト）: ホスト依存。crash 復旧の実測が先。
4. **#10 LCM の DAG**（高コスト）: 独立ミッション。Fresh Tail と invariant store の設計が必要。
5. **#11 RLM の永続 REPL**（ホスト依存）: ホスト `eval` を運用で使う方が先。

### F. 保留・不採用の理由（要約）

- **保留**: #4 Codemode（ホスト所有）、#10 LCM（コスト）、#25 pi-autoresearch（評価基盤）、
  #27 Fugu（外部 model 集合・学習 router 待ち）。
- **不採用**: #12 embedding 検索（trail + ast-grep で足りる）、#19 RRSI（研究段階）、
  #26 billion-context（NIAH 劣化）、#30 in-process 全面書き換え（効果不明）。
