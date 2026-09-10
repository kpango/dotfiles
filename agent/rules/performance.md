---
paths:
  - "**/*.{go,rs,py,c,cc,cpp,h,hpp,ts,tsx,zig,proto}"
---

# Performance 規約 (言語非依存)

「とりあえず動く」で止めず、計算量・メモリ・I/O・レイテンシを設計時点で意識する。言語固有イディオムは
`golang-patterns` / `rust-patterns` / `cpp-patterns` / `zig-patterns` 等の各言語 skill 側が SoT。

## 計算量 / メモリ

- ループ内のループ / ループ内 I/O / ループ内 allocation は意識的に flag する。**N が小さくて問題ないなら根拠を明示する**
- **O(N²) 以上を書く場合、入力サイズの上限と根拠を1行残す**。既存コードの計算量を悪化させない
- 繰り返す線形検索は hash set / map 化を検討する。データ構造は順序 / 一意性 / lookup・insert 頻度で選ぶ
  （ArcFlare / NGT / NGTAQ 等の SIMD 距離カーネルは `ann-benchmark-patterns` skill が別に詳細を持つ）
- 大きな collection / buffer は容量ヒント付きで事前確保する。不要な copy / 型変換 / serialize ↔ deserialize を入れない
- streaming で処理できるもの（file / HTTP body / DB query / log）を全部読み込まない

## I/O / コンカレンシー

- N+1 query を避ける（bulk / batch / join 相当）。必要なフィールドだけ取得し、pagination は cursor 系を default にする
- **timeout は必ず設定する**（デフォルト無限の client は明示的に上書きする）
- **リトライは回数 / 対象エラー / backoff / idempotency を明示する**。rate limit / circuit breaker を default で意識する
- 独立 I/O は並列化 + 並列度上限、依存 I/O は直列（Go は `errgroup`、Rust は `tokio::join!` 等、各言語 skill 参照）
- **cancellation / timeout / tracing は最深部まで伝播させる**。起動した並行タスクは必ず終了経路を持つ
- 共有状態は immutable / 排他制御 / message passing の3択で設計する。read-modify-write / check-then-act は
  atomic / lock / CAS で守る

## キャッシュ

- 同じ計算・I/O を1リクエスト内で繰り返さない（request-scoped cache）
- **process-scoped cache は TTL / 無効化戦略 / 容量上限 / eviction を必ず明示する**。分散環境では stampede /
  stale read を意識する
- **LLM / API client は provider のキャッシュ機能を default で組み込む**（Claude なら prompt caching →
  `claude-api` / `claude-api-go` skill）

## レイテンシ / 計測

- **p50 / p95 / p99 のどれを最適化するか最初に決める**
- critical path にブロッキング I/O / 重い計算を置かない
- **修正前に計測する**（profiler / benchmark / trace。`perf-analyzer` agent / `benchmark` skill 参照）。
  憶測で書き換えず、ボトルネック特定前の micro-optimization に走らない。**「速くなった」は before / after の
  数値で示す**
- 重要処理は metrics + logs + traces の3軸。高 cardinality label を metrics に入れない

## trade-off は user 判断（比較形式で提示）

可読性 vs パフォーマンス / メモリ vs CPU / レイテンシ vs スループット / 整合性 vs 可用性 / 正確性 vs 速度
